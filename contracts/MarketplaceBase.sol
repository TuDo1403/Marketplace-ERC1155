// SPDX-License-Identifier: Unlisened
pragma solidity >=0.8.13;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";

import "./interfaces/IGovernance.sol";
import "./interfaces/IMarketplace.sol";
import "./interfaces/ICollectible.sol";
import "./interfaces/ICollectible1155.sol";

contract MarketplaceBase is
    IMarketplace,
    EIP712Upgradeable,
    //Ownable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using ReceiptUtil for ReceiptUtil.Receipt;
    using ReceiptUtil for ReceiptUtil.BulkReceipt;

    address public admin;

    uint256 public immutable serviceFee;
    uint256 public immutable creatorFeeUB; // creator fee upper bound

    bytes32 public constant VERSION = keccak256("v1");
    bytes32 public constant NAME = keccak256("Marketplace");

    CountersUpgradeable.Counter public nonce;

    modifier onlyManager() {
        if (_msgSender() != IGovernance(admin).manager()) {
            revert Unauthorized();
        }
        _;
    }

    constructor(
        address admin_,
        uint256 serviceFee_,
        uint256 creatorFeeUB_
    )
        // Pausable()
        // ReentrancyGuard()
        // EIP712(
            // string(abi.encodePacked(NAME)),
            // string(abi.encodePacked(VERSION))
        // )
    {
        if (!admin_.isContract()) {
            revert InvalidInput();
        }
        admin = admin_;
        serviceFee = serviceFee_ % (2**16 - 1);
        creatorFeeUB = creatorFeeUB_ % (2**16 - 1);

        __Pausable_init();
        __ReentrancyGuard_init();
        __EIP712_init(string(abi.encodePacked(NAME)), string(abi.encodePacked(VERSION)));
    }

    // receive() external payable {
    //     emit Received(_msgSender(), msg.value, "Received Token");
    // }

    //fallback() external payable {}

    // function kill() external onlyManager {
    //     selfdestruct(payable(IGovernance(admin).treasury()));
    // }

    function multiDelegatecall(bytes[] calldata data)
        external
        payable
        override
        onlyManager
        whenNotPaused
        returns (bytes[] memory results)
    {
        for (uint256 i; i < data.length; ) {
            (bool ok, bytes memory result) = address(this).delegatecall(
                data[i]
            );
            if (!ok) {
                revert ExecutionFailed();
            }
            results[i] = result;
            unchecked {
                ++i;
            }
        }
    }

    function redeem(
        address seller_,
        address paymentToken_,
        address creatorPayoutAddr_,
        uint256 deadline_,
        ReceiptUtil.Item calldata item_,
        string calldata tokenURI_,
        bytes calldata signature_
    ) external payable override whenNotPaused nonReentrant {
        address _admin = admin;
        __verifyIntegrity(deadline_, _admin, paymentToken_);

        ReceiptUtil.Payment memory payment;
        address buyer = _msgSender();
        // get rid of stack to deep
        {
            ReceiptUtil.Receipt memory receipt = ReceiptUtil.createReceipt(
                buyer,
                seller_,
                paymentToken_,
                creatorPayoutAddr_,
                nonce.current(),
                serviceFee,
                item_
            );
            payment = receipt.payment;

            bytes32 hashedReceipt = _hashTypedDataV4(receipt.hash());
            __verifySignature(
                IGovernance(_admin).verifier(),
                hashedReceipt,
                signature_
            );
        }

        nonce.increment();

        __transact(paymentToken_, buyer, seller_, payment.subTotal);
        __transact(
            paymentToken_,
            buyer,
            creatorPayoutAddr_,
            payment.creatorPayout
        );
        __transact(
            paymentToken_,
            buyer,
            IGovernance(_admin).treasury(),
            payment.servicePayout
        );

        ICollectible nft = ICollectible(item_.nftContract);
        bool minted = nft.isMintedBefore(seller_, item_.tokenId, item_.amount);

        if (!minted) {
            nft.lazyMintSingle(seller_, item_.tokenId, item_.amount, tokenURI_);
        }

        nft.transferSingle(seller_, buyer, item_.amount, item_.tokenId);
    }

    function redeemBulk(
        uint256 deadline_,
        address seller_,
        address paymentToken_,
        address creatorPayoutAddr_,
        bytes calldata signature_,
        ReceiptUtil.Bulk calldata bulk_,
        string[] calldata tokenURIs_
    ) external payable override whenNotPaused nonReentrant {
        if (
            tokenURIs_.length != bulk_.tokenIds.length ||
            bulk_.tokenIds.length != bulk_.amounts.length ||
            bulk_.amounts.length != bulk_.unitPrices.length
        ) {
            revert LengthMismatch();
        }
        address _admin = admin;
        __verifyIntegrity(deadline_, _admin, paymentToken_);

        address buyer = _msgSender();
        ReceiptUtil.Payment memory payment;
        // get rid of stack too deep
        {
            ReceiptUtil.BulkReceipt memory receipt = ReceiptUtil
                .createBulkReceipt(
                    nonce.current(),
                    serviceFee,
                    buyer,
                    seller_,
                    paymentToken_,
                    creatorPayoutAddr_,
                    bulk_
                );
            payment = receipt.payment;
            bytes32 hashedReceipt = _hashTypedDataV4(receipt.hash());
            __verifySignature(
                IGovernance(_admin).verifier(),
                hashedReceipt,
                signature_
            );
        }

        nonce.increment();
        // get rid of stack too deep
        {
            __transact(paymentToken_, buyer, seller_, payment.subTotal);
            __transact(
                paymentToken_,
                buyer,
                creatorPayoutAddr_,
                payment.creatorPayout
            );
            address treasury = IGovernance(_admin).treasury();
            __transact(paymentToken_, buyer, treasury, payment.servicePayout);
        }

        ICollectible1155 nft;
        nft = ICollectible1155(bulk_.nftContract);
        __mintUnexist(seller_, nft, bulk_, tokenURIs_);
        nft.transferBatch(seller_, buyer, bulk_.tokenIds, bulk_.amounts);
    }

    function pause() external override whenNotPaused onlyManager {
        _pause();
    }

    function unpause() external override whenPaused onlyManager {
        _unpause();
    }

    function setAdmin(address admin_) external override whenPaused onlyManager {
        admin = admin_;
    }

    function __transact(
        address paymentToken_,
        address from_,
        address to_,
        uint256 amount_
    ) private {
        if (paymentToken_ == address(0)) {
            (bool ok, ) = payable(to_).call{value: amount_}("");
            if (!ok) {
                revert PaymentFailed();
            }
        } else {
            IERC20Upgradeable(paymentToken_).safeTransferFrom(from_, to_, amount_);
        }
    }

    function __mintUnexist(
        address seller_,
        ICollectible1155 nft_,
        ReceiptUtil.Bulk calldata bulk_,
        string[] calldata tokenURIs_
    ) private {
        uint256 counter;
        uint256[] memory tokensToMint;
        uint256[] memory amountsToMint;
        for (uint256 i; i < bulk_.tokenIds.length; ) {
            bool minted = nft_.isMintedBefore(
                seller_,
                bulk_.tokenIds[i],
                bulk_.amounts[i]
            );

            unchecked {
                if (!minted) {
                    tokensToMint[counter] = bulk_.tokenIds[i];
                    amountsToMint[counter] = bulk_.amounts[i];
                    ++counter;
                }
                ++i;
            }
        }
        nft_.lazyMintBatch(seller_, tokensToMint, amountsToMint, tokenURIs_);
    }

    function __isPaymentSupported(address admin_, address paymentToken_)
        private
        view
        returns (bool)
    {
        return IGovernance(admin_).acceptedPayments(paymentToken_);
    }

    function __verifyIntegrity(
        uint256 deadline_,
        address admin_,
        address paymentToken_
    ) private view {
        if (!__isPaymentSupported(admin_, paymentToken_)) {
            revert PaymentUnsuported();
        }
        if (block.timestamp > deadline_) {
            revert Expired();
        }
    }

    function __verifySignature(
        address verifier_,
        bytes32 data_,
        bytes calldata signature_
    ) private pure {
        address signer = ECDSAUpgradeable.recover(data_, signature_);
        if (signer != verifier_) {
            revert InvalidSignature();
        }
    }
}
