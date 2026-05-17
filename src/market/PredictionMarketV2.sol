// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./PredictionMarketV1.sol";

/// @title PredictionMarketV2
/// @notice UUPS upgrade of PredictionMarketV1.
///
/// V1 → V2 upgrade path
/// ─────────────────────
/// 1. Deploy this contract as a new implementation.
/// 2. Call proxy.upgradeToAndCall(address(v2Impl), "") via the Timelock.
/// 3. All V1 state (markets, reserves, LP balances) is preserved in-place.
///
/// Storage collision proof
/// ────────────────────────
/// V2 ONLY appends new slots AFTER the last V1 slot (slot 7 = lpBalances).
/// No existing slot is reordered, removed, or retyped.
///
/// New V2 slots (OZ v5 uses ERC-7201 namespaced storage for OwnableUpgradeable,
/// so sequential slots start at 0 for our own state variables):
///   slot 6  : maxSwapBps    (uint256)
///   slot 7  : pausedMarkets (mapping(uint256 => bool))
///
/// Run `forge inspect PredictionMarketV1 storage` and
///     `forge inspect PredictionMarketV2 storage` to verify slot numbers.

contract PredictionMarketV2 is PredictionMarketV1 {
    // ── New V2 state (appended after V1 slot 7) ───────────────────────────────

    /// @notice Maximum swap expressed in basis points of the smaller reserve.
    ///         Default 0 = unlimited (backwards-compatible with V1 behaviour).
    uint256 public maxSwapBps;

    /// @notice Per-market pause flag settable by the owner (Timelock).
    mapping(uint256 => bool) public pausedMarkets;

    // ── V2 events ─────────────────────────────────────────────────────────────

    event MaxSwapBpsUpdated(uint256 oldBps, uint256 newBps);
    event MarketPaused(uint256 indexed marketId);
    event MarketUnpaused(uint256 indexed marketId);

    // ── V2 errors ─────────────────────────────────────────────────────────────

    error MarketPausedError(uint256 marketId);
    error SwapExceedsMaxSize(uint256 amountIn, uint256 maxAllowed);

    // ── Initializer for V2 (called once via upgradeToAndCall) ─────────────────

    /// @notice One-time V2 initialisation — sets maxSwapBps.
    /// @dev    Uses reinitializer(2) so it can only be called once on this version.
    function initializeV2(uint256 maxSwapBps_) external reinitializer(2) {
        maxSwapBps = maxSwapBps_;
    }

    // ── V2 admin ──────────────────────────────────────────────────────────────

    function setMaxSwapBps(uint256 bps) external onlyOwner {
        require(bps <= 10_000, "V2: bps > 100%");
        emit MaxSwapBpsUpdated(maxSwapBps, bps);
        maxSwapBps = bps;
    }

    function pauseMarket(uint256 marketId) external onlyOwner {
        _requireMarketExists(marketId);
        pausedMarkets[marketId] = true;
        emit MarketPaused(marketId);
    }

    function unpauseMarket(uint256 marketId) external onlyOwner {
        pausedMarkets[marketId] = false;
        emit MarketUnpaused(marketId);
    }

    // ── Overridden swap with V2 guards ────────────────────────────────────────

    function swap(uint256 marketId, bool buyYes, uint256 amountIn, uint256 minAmountOut)
        external
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        if (pausedMarkets[marketId]) revert MarketPausedError(marketId);

        // Enforce max swap size if configured
        if (maxSwapBps > 0) {
            Market storage mkt = markets[marketId];
            uint256 smallerReserve = mkt.yesReserve < mkt.noReserve ? mkt.yesReserve : mkt.noReserve;
            uint256 maxAllowed = (smallerReserve * maxSwapBps) / 10_000;
            if (amountIn > maxAllowed) revert SwapExceedsMaxSize(amountIn, maxAllowed);
        }

        return _swap(marketId, buyYes, amountIn, minAmountOut);
    }

    // ── Version identifier ────────────────────────────────────────────────────

    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}
