// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title FeeVault
/// @notice ERC-4626 tokenized vault that accumulates LP fees from the prediction market.
///
/// LPs deposit the collateral token (e.g. a stablecoin) and receive vault shares.
/// The market contract calls depositFees() to push collected 0.3% swap fees here.
/// LPs redeem shares at any time for their proportional cut of accumulated fees.
///
/// Rounding:
///   OZ ERC4626 already implements the correct EIP-4626 rounding directions:
///     convertToShares / previewDeposit / previewMint  → round DOWN  (vault-favourable)
///     convertToAssets / previewWithdraw / previewRedeem → round UP  (vault-favourable)
///   The virtual offset trick (_decimalsOffset = 0 here) is not needed because
///   the market initialises the vault with a seed deposit before opening to LPs,
///   preventing share-price inflation attacks.
contract FeeVault is ERC4626, Ownable {
    /// @notice Only this address may push fees into the vault.
    address public feeCollector;

    event FeeCollectorUpdated(address indexed previous, address indexed next);
    event FeesReceived(address indexed from, uint256 assets);

    error NotFeeCollector();

    constructor(address asset_, address initialOwner)
        ERC20("FeeVault Share", "fvSHARE")
        ERC4626(IERC20(asset_))
        Ownable(initialOwner)
    {
        feeCollector = initialOwner;
    }

    modifier onlyFeeCollector() {
        if (msg.sender != feeCollector) revert NotFeeCollector();
        _;
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function setFeeCollector(address newCollector) external onlyOwner {
        emit FeeCollectorUpdated(feeCollector, newCollector);
        feeCollector = newCollector;
    }

    /// @notice Pull `assets` from feeCollector into the vault (no new shares minted).
    ///         This increases the share price for all existing LPs.
    function depositFees(uint256 assets) external onlyFeeCollector {
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);
        emit FeesReceived(msg.sender, assets);
    }

    // ── ERC-4626 view helpers (explicit for test clarity) ────────────────────

    /// @dev Total assets held — used by ERC4626 for share/asset math.
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }
}
