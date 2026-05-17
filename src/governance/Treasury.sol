// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Treasury
/// @notice DAO treasury controlled exclusively by the TimelockController.
///
/// The governance flow is:
///   Governor.propose() → vote → queue() → TimelockController delay → execute()
///   → TimelockController calls Treasury.releaseERC20() or Treasury.releaseETH()
///
/// Only the TimelockController (set as owner at construction) can move funds.
/// All ERC-20 transfers use SafeERC20; all ETH transfers use call{value:} with
/// success check (no deprecated transfer/send).
contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    event ETHReceived(address indexed sender, uint256 amount);
    event ETHReleased(address indexed to, uint256 amount);
    event ERC20Released(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientETH(uint256 requested, uint256 available);
    error ETHTransferFailed();

    /// @param timelockController Address of the TimelockController that owns this treasury.
    constructor(address timelockController) Ownable(timelockController) {
        if (timelockController == address(0)) revert ZeroAddress();
    }

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    // ── Privileged actions (Timelock only via onlyOwner) ──────────────────────

    /// @notice Release ETH to a recipient. Called by TimelockController after governance.
    function releaseETH(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0)      revert ZeroAmount();
        if (amount > address(this).balance) revert InsufficientETH(amount, address(this).balance);

        // CEI: emit before external call
        emit ETHReleased(to, amount);

        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert ETHTransferFailed();
    }

    /// @notice Release ERC-20 tokens to a recipient.
    function releaseERC20(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        emit ERC20Released(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    // ── View helpers ──────────────────────────────────────────────────────────

    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function erc20Balance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
