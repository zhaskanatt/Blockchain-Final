// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title VulnerableRewardPool
/// @notice SECURITY CASE STUDY #1 — Reentrancy (CEI violation)
///
/// !! THIS CONTRACT IS INTENTIONALLY VULNERABLE — DO NOT USE IN PRODUCTION !!
///
/// Vulnerability
/// ─────────────
/// `claim()` violates the Checks-Effects-Interactions (CEI) pattern:
///   1. Check  : reads rewards[msg.sender]          ✓
///   2. Interact: sends ETH via call{value}          ← EXTERNAL CALL FIRST
///   3. Effect  : zeros rewards[msg.sender]          ← STATE UPDATE TOO LATE
///
/// Because the state update happens AFTER the external call, a malicious
/// contract can re-enter `claim()` from its `receive()` fallback before
/// `rewards[msg.sender]` is zeroed, effectively claiming multiple times.
///
/// Attack sequence
/// ───────────────
///   1. Attacker deposits 1 ETH → rewards[attacker] = 1 ETH
///   2. Attacker calls claim()
///   3. Pool sends 1 ETH to attacker (external call)
///   4. Attacker's receive() triggers → calls claim() again
///   5. rewards[attacker] is still 1 ETH (not zeroed yet)
///   6. Pool sends another 1 ETH → pool is drained
///   7. Original call resumes: rewards[attacker] = 0  (too late)
///
/// Fix (see SecureRewardPool.sol)
/// ───────────────────────────────
///   Step 1: Zero the balance BEFORE the external call (CEI).
///   Step 2: Add ReentrancyGuardTransient as a belt-and-suspenders guard.

contract VulnerableRewardPool {

    mapping(address => uint256) public rewards;
    uint256 public totalDeposited;

    event Deposited(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);

    /// @notice Deposit ETH to accrue a reward balance.
    function deposit() external payable {
        require(msg.value > 0, "VulnerableRewardPool: zero deposit");
        rewards[msg.sender] += msg.value;
        totalDeposited      += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Claim all accrued ETH rewards.
    /// @dev    VULNERABLE: external call happens before state update.
    function claim() external {
        uint256 amount = rewards[msg.sender];
        require(amount > 0, "VulnerableRewardPool: nothing to claim");

        // !! VULNERABLE: interact before effect !!
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "VulnerableRewardPool: ETH transfer failed");

        // State update happens too late — a reentrant call sees the old balance
        rewards[msg.sender] = 0;

        emit Claimed(msg.sender, amount);
    }

    /// @notice Pool ETH balance (may differ from totalDeposited after an attack).
    function poolBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
