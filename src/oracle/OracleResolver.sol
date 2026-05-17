// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title OracleResolver
/// @notice Wraps a Chainlink AggregatorV3 price feed with mandatory safety checks:
///
///   1. Positive answer       — reverts if answer ≤ 0 (feed malfunction / deprecation).
///   2. Non-zero updatedAt    — reverts if the feed has never been updated.
///   3. Staleness check       — reverts if block.timestamp − updatedAt > stalenessThreshold.
///   4. Round completeness    — reverts if answeredInRound < roundId (incomplete round).
///
/// Usage in the prediction market:
///   The Timelock-controlled owner registers one OracleResolver per collateral/asset pair.
///   When resolving a binary market (e.g. "Will ETH hit $5 000?"), the market contract
///   calls `getPrice()` to read the current validated price on-chain.
///
/// Security notes:
///   • All privileged configuration (feed address, threshold) is gated by OZ Ownable.
///   • No use of tx.origin.  No use of block.timestamp as a source of randomness.
///   • stalenessThreshold is configurable so it can tighten over time without redeployment.

contract OracleResolver is Ownable {
    // ── Configuration ─────────────────────────────────────────────────────────

    AggregatorV3Interface public feed;

    /// @notice Maximum age of a valid price update (seconds).
    ///         Default: 3 600 s (1 hour) — suitable for most Chainlink heartbeats.
    uint256 public stalenessThreshold;

    // ── Events ────────────────────────────────────────────────────────────────

    event FeedUpdated(address indexed oldFeed, address indexed newFeed);
    event StalenessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // ── Custom errors ─────────────────────────────────────────────────────────

    /// @dev Thrown when the Chainlink answer is zero or negative.
    error InvalidPrice(int256 answer);

    /// @dev Thrown when the feed has never written updatedAt.
    error FeedNeverUpdated();

    /// @dev Thrown when block.timestamp − updatedAt exceeds stalenessThreshold.
    error StalePrice(uint256 updatedAt, uint256 threshold, uint256 currentTime);

    /// @dev Thrown when answeredInRound < roundId (round not yet finalised).
    error IncompleteRound(uint80 answeredInRound, uint80 roundId);

    /// @dev Thrown on a zero-address feed or zero threshold.
    error InvalidConfiguration();

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param feed_               Chainlink AggregatorV3 address.
    /// @param stalenessThreshold_ Maximum price age in seconds.
    /// @param initialOwner_       Owner (Timelock in production).
    constructor(address feed_, uint256 stalenessThreshold_, address initialOwner_) Ownable(initialOwner_) {
        if (feed_ == address(0) || stalenessThreshold_ == 0) revert InvalidConfiguration();
        feed = AggregatorV3Interface(feed_);
        stalenessThreshold = stalenessThreshold_;
    }

    // ── Core: validated price read ────────────────────────────────────────────

    /// @notice Return the latest validated price from the Chainlink feed.
    /// @return price   Latest answer (feed's native precision, e.g. 8 decimals for USD pairs).
    /// @return updatedAt Unix timestamp of the last feed update.
    function getPrice() external view returns (int256 price, uint256 updatedAt) {
        (uint80 roundId, int256 answer,, uint256 _updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        // Validation 1: answer must be positive
        if (answer <= 0) revert InvalidPrice(answer);

        // Validation 2: feed must have been updated at least once
        if (_updatedAt == 0) revert FeedNeverUpdated();

        // Validation 3: staleness check — revert if price is older than threshold
        if (block.timestamp - _updatedAt > stalenessThreshold) {
            revert StalePrice(_updatedAt, stalenessThreshold, block.timestamp);
        }

        // Validation 4: round completeness — answeredInRound must equal roundId
        if (answeredInRound < roundId) {
            revert IncompleteRound(answeredInRound, roundId);
        }

        return (answer, _updatedAt);
    }

    /// @notice Convenience helper: return price scaled to 18 decimals.
    /// @return price18 Latest answer normalised to 1e18 precision.
    function getPriceScaled18() external view returns (uint256 price18) {
        (int256 raw,) = this.getPrice();

        require(raw >= 0, "Negative price");

        uint8 dec = feed.decimals();

        // Upscale from feed decimals to 18
        price18 = uint256(raw) * (10 ** (18 - dec));
    }

    // ── Feed metadata helpers (view, no validation needed) ───────────────────

    function feedDecimals() external view returns (uint8) {
        return feed.decimals();
    }

    function feedDescription() external view returns (string memory) {
        return feed.description();
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    /// @notice Replace the Chainlink feed (owner/Timelock only).
    function setFeed(address newFeed) external onlyOwner {
        if (newFeed == address(0)) revert InvalidConfiguration();
        emit FeedUpdated(address(feed), newFeed);
        feed = AggregatorV3Interface(newFeed);
    }

    /// @notice Adjust the staleness window (owner/Timelock only).
    function setStalenessThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold == 0) revert InvalidConfiguration();
        emit StalenessThresholdUpdated(stalenessThreshold, newThreshold);
        stalenessThreshold = newThreshold;
    }
}
