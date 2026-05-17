// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title MockV3Aggregator
/// @notice Test-only mock implementing AggregatorV3Interface.
///
/// Features needed for OracleResolver tests:
///   • Configurable price (positive, zero, negative).
///   • Configurable updatedAt (to simulate staleness).
///   • Configurable roundId / answeredInRound (to simulate incomplete rounds).
///   • Configurable decimals and description.
///
/// NOT FOR PRODUCTION USE.
contract MockV3Aggregator is AggregatorV3Interface {

    uint8   public override decimals;
    string  public override description;
    uint256 public override version = 1;

    // Current round data
    uint80  public currentRoundId;
    int256  public latestAnswer;
    uint256 public latestStartedAt;
    uint256 public latestUpdatedAt;
    uint80  public latestAnsweredInRound;

    // Historical rounds (roundId → data)
    struct RoundData {
        int256  answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80  answeredInRound;
    }
    mapping(uint80 => RoundData) private _rounds;

    constructor(uint8 decimals_, int256 initialAnswer) {
        decimals    = decimals_;
        description = "Mock / USD";
        _updateRound(initialAnswer, block.timestamp);
    }

    // ── Mutations (test helpers) ──────────────────────────────────────────────

    /// @notice Push a new round with the given answer and updatedAt timestamp.
    function updateRoundData(int256 answer, uint256 updatedAt_) external {
        _updateRound(answer, updatedAt_);
    }

    /// @notice Simulate a stale feed by setting updatedAt far in the past.
    function setStaleRound(int256 answer, uint256 updatedAt_) external {
        _updateRound(answer, updatedAt_);
    }

    /// @notice Simulate an incomplete round (answeredInRound < roundId).
    function setIncompleteRound(int256 answer) external {
        currentRoundId++;
        latestAnswer       = answer;
        latestStartedAt    = block.timestamp;
        latestUpdatedAt    = block.timestamp;
        // answeredInRound intentionally behind roundId → incomplete
        latestAnsweredInRound = currentRoundId - 1;
        _rounds[currentRoundId] = RoundData(answer, block.timestamp, block.timestamp, currentRoundId - 1);
    }

    /// @notice Force updatedAt to 0 (simulate a feed that has never updated).
    function setNeverUpdated() external {
        latestUpdatedAt = 0;
        _rounds[currentRoundId].updatedAt = 0;
    }

    // ── AggregatorV3Interface ─────────────────────────────────────────────────

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        )
    {
        return (
            currentRoundId,
            latestAnswer,
            latestStartedAt,
            latestUpdatedAt,
            latestAnsweredInRound
        );
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        )
    {
        RoundData memory r = _rounds[_roundId];
        return (_roundId, r.answer, r.startedAt, r.updatedAt, r.answeredInRound);
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    function _updateRound(int256 answer, uint256 updatedAt_) internal {
        currentRoundId++;
        latestAnswer          = answer;
        latestStartedAt       = updatedAt_;
        latestUpdatedAt       = updatedAt_;
        latestAnsweredInRound = currentRoundId;
        _rounds[currentRoundId] = RoundData(answer, updatedAt_, updatedAt_, currentRoundId);
    }
}
