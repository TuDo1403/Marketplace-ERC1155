// SPDX-License-Identifier: Unlisened
pragma solidity >=0.8.13;

//import "./IPausable.sol";
import "../libraries/TokenIdGenerator.sol";

interface ICollectible {
    error Overflow();
    error Unauthorized();
    error InvalidInput();

    function initialize(
        address admin_,
        address owner_,
        string calldata name_,
        string calldata symbol_,
        string calldata baseURI_
    ) external;

    function setBaseURI(string calldata baseURI_) external;

    function setTokenURI(uint256 tokenId_, string calldata tokenURI_) external;

    function mint(uint256 tokenId_, uint256 amount_) external;

    function mint(
        uint256 amount_,
        TokenIdGenerator.Token calldata token_,
        string calldata tokenURI_
    ) external;

    function lazyMintSingle(
        address creator_,
        uint256 tokenId_,
        uint256 amount_,
        string calldata tokenURI_
    ) external;

    function transferSingle(
        address from_,
        address to_,
        uint256 amount_,
        uint256 tokenId_
    ) external;

    function isMintedBefore(
        address seller_,
        uint256 tokenId_,
        uint256 amount_
    ) external view returns (bool);

    function getTokenURI(uint256 tokenId_)
        external
        view
        returns (string memory);

    function TYPE() external view returns (bytes32);
}
