// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @title SecureTreasury
/// @notice SECURITY CASE STUDY #2 — Access Control bypass (FIXED)
///
/// Fixes applied vs VulnerableTreasury
/// ─────────────────────────────────────
/// FIX 1 — Replace tx.origin with msg.sender via OZ Ownable:
///   `onlyOwner` checks `msg.sender == owner()`, NOT `tx.origin`.
///   An intermediary contract's address will never equal the owner's EOA,
///   so the phishing attack is structurally impossible.
///
/// FIX 2 — ReentrancyGuardTransient on withdraw():
///   Prevents a malicious recipient from re-entering withdraw() during the
///   ETH transfer (separate defence-in-depth layer).
///
/// FIX 3 — fund() gated by onlyOwner:
///   The original contract left fund() open to anyone. Fixed here.
///
/// Security properties after fix
/// ──────────────────────────────
///   • No use of tx.origin anywhere.
///   • Every privileged function protected by OZ Ownable (msg.sender check).
///   • ETH sent via call{value:} with success check (no deprecated transfer/send).
///   • ReentrancyGuardTransient on all ETH-sending paths.

contract SecureTreasury is Ownable, ReentrancyGuardTransient {
    uint256 public totalWithdrawn;

    event Received(address indexed sender, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event Funded(address indexed from, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH from the treasury. Owner only.
    /// @dev    SECURE: msg.sender checked via OZ Ownable; nonReentrant guard applied.
    function withdraw(address payable to, uint256 amount)
        external
        onlyOwner // FIX 1: msg.sender == owner(), never tx.origin
        nonReentrant // FIX 2: belt-and-suspenders reentrancy protection

    {
        require(amount <= address(this).balance, "SecureTreasury: insufficient funds");
        require(to != address(0), "SecureTreasury: zero recipient");

        totalWithdrawn += amount;

        // FIX 3: call{value:} with success check (no deprecated transfer/send)
        (bool ok,) = to.call{value: amount}("");
        require(ok, "SecureTreasury: ETH transfer failed");

        emit Withdrawn(to, amount);
    }

    /// @notice Fund the treasury. Owner only.
    function fund() external payable onlyOwner {
        // FIX 3: was unguarded
        require(msg.value > 0, "SecureTreasury: zero fund");
        emit Funded(msg.sender, msg.value);
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}
