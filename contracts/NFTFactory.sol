// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "./base/MarketplaceIntegratable.sol";
import "./base/INFTBase.sol";
import "./interfaces/INFT.sol";

import "./interfaces/INFTFactory.sol";
import "./interfaces/IGovernance.sol";

contract NFTFactory1155 is
    INFTFactory,
    MarketplaceIntegratable,
    ContextUpgradeable
{
    using ClonesUpgradeable for address;

    //keccak256("NFTFactory_v1")
    bytes32 public constant VERSION =
        0xc42665b4953fdd2cb30dcf1befa0156911485f4e84e3f90b1360ddfb4fa2f766;

    mapping(uint256 => address) public deployedContracts;

    function initialize(address admin_) external initializer {
        _initialize(admin_);
    }

    function deployCollectible(
        address implement_,
        string calldata name_,
        string calldata symbol_,
        string calldata baseURI_
    ) external override returns (address clone) {
        address owner = _msgSender();
        bytes32 salt = keccak256(
            abi.encodePacked(VERSION, name_, symbol_, baseURI_)
        );

        clone = implement_.cloneDeterministic(salt);
        INFT(clone).initialize(address(admin), owner, name_, symbol_, baseURI_);

        deployedContracts[uint256(salt)] = clone;
        emit TokenDeployed(
            name_,
            symbol_,
            baseURI_,
            INFTBase(clone).TYPE(),
            owner,
            clone
        );
    }
}
