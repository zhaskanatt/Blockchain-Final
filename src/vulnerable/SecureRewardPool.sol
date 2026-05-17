// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @title SecureRewardPool
/// @notice SECURITY CASE STUDY #1 — Reentrancy (FIXED)
///
/// Fixes applied vs VulnerableRewardPool
/// ───────────────────────────────────────
/// FIX 1 — Checks-Effects-Interactions (CEI):
///   The balance is zeroed BEFORE the external ETH transfer.
///   Even if the callee re-enters claim(), rewards[msg.sender] is already 0
///   so the `require(amount > 0)` check will revert the reentrant call.
///
/// FIX 2 — ReentrancyGuardTransient (belt-and-suspenders):
///   OZ's transient-storage reentrancy guard (EIP-1153) rejects any nested
///   call to a `nonReentrant` function within the same transaction.
///   This makes the protection explicit and auditor-visible, independent of
///   the CEI ordering.
///
/// Together these two fixes make reentrancy impossible:
///   • CEI ensures state is consistent before any external call.
///   • ReentrancyGuardTransient provides a hard revert on any re-entry attempt.

contract SecureRewardPool is ReentrancyGuardTransient {
    mapping(address => uint256) public rewards;
    uint256 public totalDeposited;

    event Deposited(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);

    /// @notice Deposit ETH to accrue a reward balance.
    function deposit() external payable {
        require(msg.value > 0, "SecureRewardPool: zero deposit");
        rewards[msg.sender] += msg.value;
        totalDeposited += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Claim all accrued ETH rewards.
    /// @dev    SECURE: CEI order enforced + nonReentrant guard.
    function claim() external nonReentrant {
        uint256 amount = rewards[msg.sender];
        require(amount > 0, "SecureRewardPool: nothing to claim");

        // FIX 1 — Effect BEFORE Interaction (CEI)
        rewards[msg.sender] = 0;

        // FIX 2 — nonReentrant modifier blocks any re-entry at the EVM level
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "SecureRewardPool: ETH transfer failed");

        emit Claimed(msg.sender, amount);
    }

    function poolBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
