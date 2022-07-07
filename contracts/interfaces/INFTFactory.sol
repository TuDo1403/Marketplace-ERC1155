// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.13;

interface INFTFactory {
    error Unauthorized();
    error InvalidAddress();
    error ExecutionFailed();

    event TokenDeployed(
        string name_,
        string symbol_,
        string baseURI_,
        string indexed standard_,
        address indexed deployer_,
        address indexed deployedAddr_
    );

    function setMarketplace(address marketplace_) external;

    function setGovernance(address governance_) external;

    function deployCollectible(
        address implement_,
        string calldata name_,
        string calldata symbol_,
        string calldata baseURI_
    ) external returns (address deployedAddress);

    function multiDelegatecall(bytes[] calldata data)
        external
        returns (bytes[] memory);
}
