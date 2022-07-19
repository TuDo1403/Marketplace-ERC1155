// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.13;

import "../ERC1155Lite.sol";

import "../../../../libraries/TokenIdGenerator.sol";

abstract contract ERC1155SupplyLite is ERC1155Lite {
    using TokenIdGenerator for uint256;
    mapping(uint256 => uint256) private _totalSupply;

    /**
     * @dev Total amount of tokens in with a given id.
     */
    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return _totalSupply[id];
    }

    /**
     * @dev Indicates whether any token exist with a given id, or not.
     */
    function exists(uint256 id) public view virtual returns (bool) {
        return ERC1155SupplyLite.totalSupply(id) > 0;
    }

    /**
     * @dev See {ERC1155-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        uint256 length = ids.length;
        if (from == address(0)) {
            for (uint256 i; i < length; ) {
                _supplyCheck(ids[i], amounts[i]);
                _totalSupply[ids[i]] += amounts[i];
                unchecked {
                    ++i;
                }
            }
        }

        if (to == address(0)) {
            for (uint256 i = 0; i < length; ) {
                uint256 id = ids[i];
                uint256 amount = amounts[i];
                uint256 supply = _totalSupply[id];
                if (supply < amount) {
                    revert ERC1155__AllocationExceeds();
                }
                unchecked {
                    _totalSupply[id] = supply - amount;
                    ++i;
                }
            }
        }
    }

    function _supplyCheck(uint256 tokenId_, uint256 amount_)
        internal
        view
        virtual
    {
        if (amount_ > 2**TokenIdGenerator.SUPPLY_BIT - 1) {
            revert ERC1155__AllocationExceeds();
        }
        uint256 maxSupply = tokenId_.getTokenMaxSupply();
        if (maxSupply != 0) {
            unchecked {
                if (amount_ + totalSupply(tokenId_) > maxSupply) {
                    revert ERC1155__AllocationExceeds();
                }
            }
        }
    }
}
