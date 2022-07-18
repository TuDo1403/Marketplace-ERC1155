// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.13;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./IPausable.sol";
import "../libraries/ReceiptUtil.sol";

interface IMarketplace is IPausable {
    error MP__Expired();
    error MP__InvalidInput();
    error MP__Unauthorized();
    error MP__PaymentFailed();
    error MP__LengthMismatch();
    error MP__ExecutionFailed();
    error MP__InvalidSignature();
    error MP__PaymentUnsuported();
    error MP__InsufficientPayment();

    event ItemRedeemed(
        address indexed nftContract,
        address indexed buyer,
        uint256 indexed tokenId,
        address paymentToken,
        uint256 total
    );

    event BulkRedeemed(
        address indexed nftContract,
        address indexed buyer,
        uint256[] tokenIds,
        address paymentToken,
        uint256 total
    );

    function multiDelegatecall(bytes[] calldata data)
        external
        payable
        returns (bytes[] memory results);

    function redeem(
        ReceiptUtil.Receipt calldata receipt_,
        bytes calldata signature_
    ) external payable;

    // function redeemBulk(
    //     ReceiptUtil.BulkReceipt calldata receipt_,
    //     bytes calldata signature_
    // ) external payable;
}
