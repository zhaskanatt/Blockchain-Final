// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

/// @title PredictionGovernor
/// @notice Full OpenZeppelin Governor stack for the Prediction Market DAO.
///
/// Exact parameters (Section 3.1 — Governance):
/// ─────────────────────────────────────────────
///   Voting delay     : 7 200 blocks  ≈ 1 day   (@ 12 s/block on mainnet)
///   Voting period    : 50 400 blocks ≈ 1 week
///   Quorum           : 4 % of totalSupply at proposal snapshot
///   Proposal threshold: 1 % of MAX_SUPPLY = 1 000 000 PDAO tokens
///   Timelock delay   : 2 days (172 800 seconds) — set in TimelockController
///
/// Roles & flow:
///   1. Propose   — any holder with ≥ 1 % of PDAO tokens.
///   2. Vote      — any PDAO holder (delegated power at snapshot block).
///   3. Queue     — call queue() after voting period ends with quorum met.
///   4. Execute   — call execute() after the 2-day Timelock delay.
///
/// The Timelock controls the Treasury (and future market parameters), so
/// all on-chain governance actions flow through the time-lock.

contract PredictionGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    constructor(IVotes token_, TimelockController timelock_)
        Governor("PredictionGovernor")
        GovernorSettings(
            7_200, // voting delay  : 7 200 blocks ≈ 1 day
            50_400, // voting period : 50 400 blocks ≈ 1 week
            1_000_000e18 // proposal threshold: 1 % of 100 M PDAO = 1 M tokens
        )
        GovernorVotes(token_)
        GovernorVotesQuorumFraction(4) // 4 % quorum
        GovernorTimelockControl(timelock_)
    {}

    // ── Required overrides ────────────────────────────────────────────────────

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
