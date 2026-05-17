// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title VulnerableTreasury
/// @notice SECURITY CASE STUDY #2 — Access Control bypass via tx.origin
///
/// !! THIS CONTRACT IS INTENTIONALLY VULNERABLE — DO NOT USE IN PRODUCTION !!
///
/// Vulnerability
/// ─────────────
/// `withdraw()` uses `tx.origin` instead of `msg.sender` to authenticate the
/// caller.  `tx.origin` is always the original EOA that initiated the
/// transaction — it does NOT change when the call passes through intermediate
/// contracts.
///
/// This means any contract can impersonate the admin by simply sitting in the
/// call chain while the admin's EOA is the transaction initiator.
///
/// Attack sequence (phishing)
/// ──────────────────────────
///   1. Attacker deploys PhishingContract (see exploit test).
///   2. Attacker tricks the admin into calling PhishingContract.attack()
///      (e.g., disguised as a "claim rewards" UI button).
///   3. PhishingContract.attack() calls VulnerableTreasury.withdraw(attacker, bal).
///   4. Inside withdraw(): tx.origin == admin  ← PASSES (admin signed the tx)
///                         msg.sender == PhishingContract ← ignored
///   5. Funds are transferred to the attacker.
///
/// Fix (see SecureTreasury.sol)
/// ─────────────────────────────
///   Replace `tx.origin` with `msg.sender` and inherit OZ `Ownable`.
///   An intermediate contract can never satisfy `msg.sender == owner`
///   unless the owner explicitly delegates to it.

contract VulnerableTreasury {

    address public admin;
    uint256 public totalWithdrawn;

    event Received(address indexed sender, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    constructor(address admin_) {
        require(admin_ != address(0), "VulnerableTreasury: zero admin");
        admin = admin_;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH from the treasury.
    /// @dev    VULNERABLE: uses tx.origin for authorization.
    function withdraw(address payable to, uint256 amount) external {
        // !! VULNERABLE: tx.origin can be spoofed via an intermediary contract !!
        require(tx.origin == admin, "VulnerableTreasury: not admin");
        require(amount <= address(this).balance, "VulnerableTreasury: insufficient funds");
        require(to != address(0), "VulnerableTreasury: zero recipient");

        totalWithdrawn += amount;

        (bool ok,) = to.call{value: amount}("");
        require(ok, "VulnerableTreasury: ETH transfer failed");

        emit Withdrawn(to, amount);
    }

    /// @notice Add funds directly (owner-only in the secure version).
    /// @dev    No access control here either — another issue in real contracts.
    function fund() external payable {
        require(msg.value > 0, "VulnerableTreasury: zero fund");
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}
