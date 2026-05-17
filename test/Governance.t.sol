// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../src/tokens/GovernanceToken.sol";
import "../src/governance/PredictionGovernor.sol";
import "../src/governance/Treasury.sol";

/// @notice Full end-to-end governance lifecycle test.
///
/// Verified flow:  propose → vote → queue → execute
///
/// Exact parameters under test:
///   Voting delay     : 7 200 blocks  (1 day)
///   Voting period    : 50 400 blocks (1 week)
///   Quorum           : 4 % of total supply at snapshot
///   Proposal threshold: 1 000 000 PDAO (1 % of MAX_SUPPLY)
///   Timelock delay   : 2 days = 172 800 seconds
contract GovernanceTest is Test {

    // ── Contracts ─────────────────────────────────────────────────────────────

    GovernanceToken    internal token;
    TimelockController internal timelock;
    PredictionGovernor internal governor;
    Treasury           internal treasury;

    // ── Actors ────────────────────────────────────────────────────────────────

    address internal deployer  = makeAddr("deployer");
    address internal proposer  = makeAddr("proposer");  // holds 1 % of supply
    address internal voter1    = makeAddr("voter1");    // large holder
    address internal voter2    = makeAddr("voter2");    // large holder
    address internal stranger  = makeAddr("stranger"); // no tokens

    address internal recipient = makeAddr("recipient"); // ETH release target

    // ── Parameters ────────────────────────────────────────────────────────────

    uint256 internal constant TIMELOCK_DELAY   = 2 days;         // 172 800 s
    uint256 internal constant VOTING_DELAY     = 7_200;          // blocks
    uint256 internal constant VOTING_PERIOD    = 50_400;         // blocks
    uint256 internal constant PROPOSAL_THRESH  = 1_000_000e18;   // 1 % of MAX_SUPPLY
    uint256 internal constant QUORUM_PCT       = 4;              // 4 %

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(deployer);

        // 1. Deploy governance token (deployer gets 10 M initial supply)
        token = new GovernanceToken(deployer);

        // 2. Deploy Timelock — governor is the only proposer; anyone can execute
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0); // will be set to governor after deploy
        executors[0] = address(0); // address(0) = anyone can execute
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);

        // 3. Deploy governor
        governor = new PredictionGovernor(IVotes(address(token)), timelock);

        // 4. Deploy treasury (owned by timelock)
        treasury = new Treasury(address(timelock));

        // 5. Wire Timelock roles: grant PROPOSER to governor, revoke deployer's admin
        timelock.grantRole(timelock.PROPOSER_ROLE(),  address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // 6. Distribute tokens
        //    voter1 + voter2 each get 5 M (total 10 M distributed; 10 M stays with deployer)
        token.mint(voter1,   5_000_000e18);
        token.mint(voter2,   5_000_000e18);
        token.mint(proposer, PROPOSAL_THRESH); // exactly threshold

        vm.stopPrank();

        // 7. Delegate voting power (must be done before snapshot block)
        vm.prank(voter1);   token.delegate(voter1);
        vm.prank(voter2);   token.delegate(voter2);
        vm.prank(proposer); token.delegate(proposer);

        // 8. Seed the treasury with ETH
        vm.deal(address(treasury), 10 ether);

        // 9. Advance one block so delegation checkpoints are strictly in the past.
        //    OZ Governor checks getPastVotes(account, clock()-1), so the proposer's
        //    voting power is only visible from the block AFTER delegation.
        vm.roll(block.number + 1);
    }

    // ── Helper: build the release-ETH proposal payload ───────────────────────

    function _buildReleaseProposal(address to, uint256 amount)
        internal
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[]   memory calldatas,
            string    memory description
        )
    {
        targets    = new address[](1);
        values     = new uint256[](1);
        calldatas  = new bytes[](1);

        targets[0]   = address(treasury);
        values[0]    = 0;
        calldatas[0] = abi.encodeCall(Treasury.releaseETH, (payable(to), amount));
        description  = "Release 1 ETH to recipient - governance test proposal";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UNIT TESTS — parameters
    // ─────────────────────────────────────────────────────────────────────────

    function test_param_votingDelay() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
    }

    function test_param_votingPeriod() public view {
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
    }

    function test_param_proposalThreshold() public view {
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESH);
    }

    function test_param_quorumNumerator() public view {
        assertEq(governor.quorumNumerator(), QUORUM_PCT);
    }

    function test_param_timelockDelay() public view {
        assertEq(timelock.getMinDelay(), TIMELOCK_DELAY);
    }

    function test_param_governorName() public view {
        assertEq(governor.name(), "PredictionGovernor");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UNIT TESTS — access control & role setup
    // ─────────────────────────────────────────────────────────────────────────

    function test_roles_governorHasProposerRole() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
    }

    function test_roles_deployerNoLongerAdmin() public view {
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer));
    }

    function test_roles_treasuryOwnedByTimelock() public view {
        assertEq(treasury.owner(), address(timelock));
    }

    function test_roles_tokenOwnerIsDeployer() public view {
        assertEq(token.owner(), deployer);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UNIT TESTS — propose guards
    // ─────────────────────────────────────────────────────────────────────────

    function test_propose_belowThresholdReverts() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d)
            = _buildReleaseProposal(recipient, 1 ether);

        // stranger has 0 tokens — below threshold
        vm.prank(stranger);
        vm.expectRevert();
        governor.propose(t, v, c, d);
    }

    function test_propose_atThresholdSucceeds() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d)
            = _buildReleaseProposal(recipient, 1 ether);

        vm.prank(proposer); // holds exactly PROPOSAL_THRESH
        uint256 pid = governor.propose(t, v, c, d);
        assertGt(pid, 0);
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Pending));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // END-TO-END: propose → vote → queue → execute
    // ─────────────────────────────────────────────────────────────────────────

    function test_e2e_fullGovernanceLifecycle() public {
        uint256 releaseAmount = 1 ether;

        // ── Step 1: Propose ──────────────────────────────────────────────────
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[]   memory calldatas,
            string    memory description
        ) = _buildReleaseProposal(recipient, releaseAmount);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Pending),
            "E2E: proposal must be Pending after creation"
        );

        // ── Step 2: Advance past voting delay ────────────────────────────────
        vm.roll(block.number + VOTING_DELAY + 1);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Active),
            "E2E: proposal must be Active after voting delay"
        );

        // ── Step 3: Cast votes (both voters vote FOR) ────────────────────────
        // Support: 0=Against, 1=For, 2=Abstain
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        // Verify vote counts
        (uint256 against, uint256 forVotes, uint256 abstain)
            = governor.proposalVotes(proposalId);
        assertGt(forVotes, 0,  "E2E: forVotes must be > 0");
        assertEq(against,  0,  "E2E: againstVotes must be 0");
        assertEq(abstain,  0,  "E2E: abstainVotes must be 0");

        // ── Step 4: Advance past voting period ───────────────────────────────
        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Succeeded),
            "E2E: proposal must Succeed after voting period with quorum met"
        );

        // ── Step 5: Queue into Timelock ───────────────────────────────────────
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Queued),
            "E2E: proposal must be Queued after queue()"
        );

        // ── Step 6: Advance past Timelock delay ──────────────────────────────
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // ── Step 7: Execute ───────────────────────────────────────────────────
        uint256 recipientBefore  = recipient.balance;
        uint256 treasuryBefore   = address(treasury).balance;

        governor.execute(targets, values, calldatas, descHash);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Executed),
            "E2E: proposal must be Executed after execute()"
        );

        // ── Step 8: Verify on-chain effect ────────────────────────────────────
        assertEq(recipient.balance - recipientBefore, releaseAmount,
                 "E2E: recipient must receive exactly the released ETH");
        assertEq(address(treasury).balance, treasuryBefore - releaseAmount,
                 "E2E: treasury balance must decrease by release amount");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UNIT TESTS — quorum enforcement
    // ─────────────────────────────────────────────────────────────────────────

    function test_quorum_proposalDefeatedWhenQuorumNotMet() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[]   memory calldatas,
            string    memory description
        ) = _buildReleaseProposal(recipient, 1 ether);

        // Total supply after setUp = 21M PDAO. 4% quorum = 840k.
        // Create a small voter with 500k < 840k — their lone vote cannot meet quorum.
        address smallVoter = makeAddr("smallVoter");
        vm.prank(deployer);
        token.mint(smallVoter, 500_000e18);
        vm.prank(smallVoter);
        token.delegate(smallVoter);
        vm.roll(block.number + 1); // checkpoint must be in the past

        // Proposer creates the proposal (1M PDAO > proposal threshold)
        vm.prank(proposer);
        uint256 pid = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + VOTING_DELAY + 1);

        // Only smallVoter casts a vote — 500k votes < 840k quorum
        vm.prank(smallVoter);
        governor.castVote(pid, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        // Quorum not reached → Defeated
        assertEq(
            uint8(governor.state(pid)),
            uint8(IGovernor.ProposalState.Defeated),
            "quorum: proposal must be Defeated when quorum not met"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UNIT TESTS — voting
    // ─────────────────────────────────────────────────────────────────────────

    function test_vote_cannotVoteTwice() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d)
            = _buildReleaseProposal(recipient, 1 ether);

        vm.prank(proposer);
        uint256 pid = governor.propose(t, v, c, d);
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(pid, 1);

        vm.prank(voter1);
        vm.expectRevert();
        governor.castVote(pid, 1); // duplicate vote must revert
    }

    function test_vote_strangerHasNoVotingPower() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d)
            = _buildReleaseProposal(recipient, 1 ether);

        vm.prank(proposer);
        uint256 pid = governor.propose(t, v, c, d);
        vm.roll(block.number + VOTING_DELAY + 1);

        // Cast vote as stranger (0 PDAO, 0 voting power) — allowed to cast but contributes nothing
        vm.prank(stranger);
        governor.castVote(pid, 1);

        (, uint256 forVotes,) = governor.proposalVotes(pid);
        assertEq(forVotes, 0, "stranger with 0 tokens must contribute 0 voting power");
    }

    function test_vote_cannotVoteBeforeDelay() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d)
            = _buildReleaseProposal(recipient, 1 ether);

        vm.prank(proposer);
        uint256 pid = governor.propose(t, v, c, d);
        // Do NOT advance past voting delay

        vm.prank(voter1);
        vm.expectRevert();
        governor.castVote(pid, 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UNIT TESTS — Treasury
    // ─────────────────────────────────────────────────────────────────────────

    function test_treasury_onlyTimelockCanRelease() public {
        vm.prank(deployer); // not the timelock
        vm.expectRevert();
        treasury.releaseETH(payable(recipient), 1 ether);
    }

    function test_treasury_ethBalanceCorrect() public view {
        assertEq(treasury.ethBalance(), 10 ether);
    }

    function test_treasury_releaseETHZeroAddressReverts() public {
        // Impersonate the timelock
        vm.prank(address(timelock));
        vm.expectRevert(Treasury.ZeroAddress.selector);
        treasury.releaseETH(payable(address(0)), 1 ether);
    }

    function test_treasury_releaseETHZeroAmountReverts() public {
        vm.prank(address(timelock));
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.releaseETH(payable(recipient), 0);
    }

    function test_treasury_releaseETHInsufficientReverts() public {
        vm.prank(address(timelock));
        vm.expectRevert();
        treasury.releaseETH(payable(recipient), 100 ether); // more than balance
    }
}
