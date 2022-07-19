// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.13;

import "@openzeppelin/contracts-upgradeable/utils/Create2Upgradeable.sol";
import "./Collectible1155.sol";
import "./base/INFTBase.sol";
import "./interfaces/INFTFactory.sol";
import "./interfaces/IGovernance.sol";

contract NFTFactory1155 is INFTFactory {
    address public governance;

    bytes32 public constant VERSION = keccak256("NFTFactory1155_v1");

    mapping(uint256 => address) public deployedContracts;

    modifier onlyOwner() {
        if (msg.sender != IGovernance(governance).manager()) {
            revert Factory__Unauthorized();
        }
        _;
    }

    modifier validAddress(address addr_) {
        if (addr_ == address(0)) {
            revert Factory__InvalidAddress();
        }
        _;
    }

    //796772
    constructor(address governance_) validAddress(governance_) {
        governance = governance_;
    }

    function setGovernance(address governance_)
        external
        override
        validAddress(governance_)
        onlyOwner
    {
        governance = governance_;
    }

    function deployCollectible(
        string calldata name_,
        string calldata symbol_,
        string calldata baseURI_
    ) external override returns (address clone) {
        address owner = msg.sender;
        bytes32 salt = keccak256(
            abi.encodePacked(VERSION, name_, symbol_, baseURI_)
        );

        bytes memory bytecode = abi.encodePacked(
            type(Collectible1155).creationCode,
            abi.encode(address(governance), owner, name_, symbol_, baseURI_)
        );
        clone = Create2Upgradeable.deploy(0, salt, bytecode);
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

    function multiDelegatecall(bytes[] calldata data)
        external
        onlyOwner
        returns (bytes[] memory)
    {
        bytes[] memory results = new bytes[](data.length);
        for (uint256 i; i < data.length; ) {
            (bool ok, bytes memory result) = address(this).delegatecall(
                data[i]
            );
            if (!ok) {
                revert Factory__ExecutionFailed();
            }
            results[i] = result;
            unchecked {
                ++i;
            }
        }
        return results;
    }
}
