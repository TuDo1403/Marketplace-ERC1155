// SPDX-License-Identifier: Unlisened
pragma solidity ^0.8.15;

import "./interfaces/ICollectible.sol";
// import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract Collectible is
    ICollectible,
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    // State variables
    address private _factory;

    string public name;
    string public symbol;

    modifier onlyFactory(address address_) {
        require(_factory == address_, "Collectible: Only Factory");
        _;
    }

    // Functional
    function initialize(
        address admin_,
        string calldata name_,
        string calldata symbol_,
        string calldata uri_
    ) external override initializer {
        name = name_;
        symbol = symbol_;
        _factory = _msgSender();

        _initialize(admin_, name_, symbol_, uri_);
    }

    function _initialize(
        address admin_,
        string memory name_,
        string memory symbol_,
        string memory uri_
    ) internal virtual;

    function mint(address to, uint256 tokenId, uint256 amount) external virtual;

    function mint(address to, uint256 tokenId) external virtual;

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external virtual;

    function setTokenUri(uint256 tokenId, string memory uri) external virtual;

    function freezeTokenData(uint256 id) external virtual;

    function getType() external pure virtual returns (uint96);

    function getCreator(uint256 tokenId) external view virtual returns (address);
}
