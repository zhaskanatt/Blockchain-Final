// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title GovernanceToken
/// @notice ERC20 + ERC20Votes + ERC20Permit governance token for the Prediction Market DAO.
///         The TimelockController-controlled Governor uses this token's voting power.
///         Satisfies: ERC20Votes (delegation, checkpoints), ERC20Permit (gasless approvals).
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant MAX_SUPPLY = 100_000_000e18; // 100 million PDAO

    event Minted(address indexed to, uint256 amount);

    constructor(address initialOwner)
        ERC20("PredictDAO", "PDAO")
        ERC20Permit("PredictDAO")
        Ownable(initialOwner)
    {
        _mint(initialOwner, 10_000_000e18); // 10 % initial distribution
    }

    /// @notice Mint additional tokens. Only callable by the owner (Timelock).
    /// @param to     Recipient address.
    /// @param amount Token amount (18 decimals).
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "GovernanceToken: cap exceeded");
        _mint(to, amount);
        emit Minted(to, amount);
    }

    // ── Solidity overrides required when inheriting ERC20Votes + ERC20Permit ──

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
