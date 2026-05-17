// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title OutcomeShareToken
/// @notice ERC-1155 multi-token representing binary outcome shares in every
///         prediction market.
///
/// Token-ID encoding (deterministic, collision-free):
///   YES share for market M  →  (M << 1)
///   NO  share for market M  →  (M << 1) | 1
///
/// Only addresses with MINTER_ROLE (the market contract) may mint or burn.
/// The admin (Timelock) may grant/revoke roles.
contract OutcomeShareToken is ERC1155, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @dev Tracks which market IDs have been registered to prevent duplicates.
    mapping(uint256 => bool) public marketRegistered;

    /// @dev Human-readable question stored per market.
    mapping(uint256 => string) private _questions;

    event MarketRegistered(uint256 indexed marketId, string question);

    error MarketAlreadyRegistered(uint256 marketId);
    error MarketNotRegistered(uint256 marketId);

    constructor(address admin) ERC1155("") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // ── Token-ID helpers ──────────────────────────────────────────────────────

    function yesId(uint256 marketId) public pure returns (uint256) {
        return marketId << 1;
    }

    function noId(uint256 marketId) public pure returns (uint256) {
        return (marketId << 1) | 1;
    }

    /// @notice Decode a token ID back into (marketId, isNo).
    function decodeId(uint256 tokenId) public pure returns (uint256 marketId, bool isNo) {
        marketId = tokenId >> 1;
        isNo = (tokenId & 1) == 1;
    }

    // ── Market registration ───────────────────────────────────────────────────

    function registerMarket(uint256 marketId, string calldata question) external onlyRole(MINTER_ROLE) {
        if (marketRegistered[marketId]) revert MarketAlreadyRegistered(marketId);
        marketRegistered[marketId] = true;
        _questions[marketId] = question;
        emit MarketRegistered(marketId, question);
    }

    function getQuestion(uint256 marketId) external view returns (string memory) {
        if (!marketRegistered[marketId]) revert MarketNotRegistered(marketId);
        return _questions[marketId];
    }

    // ── Minting / burning ─────────────────────────────────────────────────────

    function mint(address to, uint256 id, uint256 amount, bytes calldata data) external onlyRole(MINTER_ROLE) {
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data)
        external
        onlyRole(MINTER_ROLE)
    {
        _mintBatch(to, ids, amounts, data);
    }

    function burn(address from, uint256 id, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, id, amount);
    }

    function burnBatch(address from, uint256[] calldata ids, uint256[] calldata amounts)
        external
        onlyRole(MINTER_ROLE)
    {
        _burnBatch(from, ids, amounts);
    }

    // ── ERC-165 ───────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
