// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/tokens/GovernanceToken.sol";

contract GovernanceTokenTest is Test {
    GovernanceToken internal token;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant INITIAL_SUPPLY = 10_000_000e18;
    uint256 internal constant MAX_SUPPLY = 100_000_000e18;

    function setUp() public {
        vm.prank(owner);
        token = new GovernanceToken(owner);
    }

    // ── Unit: construction ────────────────────────────────────────────────────

    function test_name() public view {
        assertEq(token.name(), "PredictDAO");
    }

    function test_symbol() public view {
        assertEq(token.symbol(), "PDAO");
    }

    function test_decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_initialSupplyMintedToOwner() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    function test_maxSupplyConstant() public view {
        assertEq(token.MAX_SUPPLY(), MAX_SUPPLY);
    }

    // ── Unit: minting ─────────────────────────────────────────────────────────

    function test_ownerCanMint() public {
        uint256 amount = 1_000e18;
        vm.prank(owner);
        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + amount);
    }

    function test_mintEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit GovernanceToken.Minted(alice, 500e18);
        token.mint(alice, 500e18);
    }

    function test_nonOwnerCannotMint() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1e18);
    }

    function test_mintRevertsWhenCapExceeded() public {
        uint256 remaining = MAX_SUPPLY - INITIAL_SUPPLY;
        vm.prank(owner);
        token.mint(alice, remaining); // exactly at cap

        vm.prank(owner);
        vm.expectRevert("GovernanceToken: cap exceeded");
        token.mint(alice, 1); // one wei over
    }

    // ── Unit: ERC20Votes – delegation & checkpoints ───────────────────────────

    function test_votingPowerZeroBeforeSelfDelegate() public view {
        // No delegation → no voting power
        assertEq(token.getVotes(owner), 0);
    }

    function test_selfDelegateGrantsVotingPower() public {
        vm.prank(owner);
        token.delegate(owner);
        assertEq(token.getVotes(owner), INITIAL_SUPPLY);
    }

    function test_delegateTransfersVotingPower() public {
        vm.prank(owner);
        token.delegate(alice);
        assertEq(token.getVotes(alice), INITIAL_SUPPLY);
        assertEq(token.getVotes(owner), 0);
    }

    function test_votingPowerUpdatesOnTransfer() public {
        vm.startPrank(owner);
        token.delegate(owner);
        require(
            token.transfer(alice, 1_000e18),
            "Transfer failed"
        );
        vm.stopPrank();

        // owner delegated to self; transferring tokens reduces their votes
        assertEq(token.getVotes(owner), INITIAL_SUPPLY - 1_000e18);
    }

    function test_pastVotesCheckpoint() public {
        // Use a literal block number to avoid via_ir reordering block.number reads
        vm.roll(10);
        vm.prank(owner);
        token.delegate(owner); // checkpoint written at block 10

        vm.roll(12); // clock = 12, strictly > 10

        assertEq(token.getPastVotes(owner, 10), INITIAL_SUPPLY);
    }

    // ── Unit: ERC20Permit ─────────────────────────────────────────────────────

    function test_permitGrantsAllowance() public {
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);

        // Fund signer
        vm.prank(owner);
        token.mint(signer, 100e18);

        uint256 value = 50e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonceBefore = token.nonces(signer);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                bob,
                value,
                nonceBefore,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        token.permit(signer, bob, value, deadline, v, r, s);

        assertEq(token.allowance(signer, bob), value);
        assertEq(token.nonces(signer), nonceBefore + 1);
    }

    function test_permitRevertsOnExpiredDeadline() public {
        uint256 privateKey = 0xB0B;
        address signer = vm.addr(privateKey);
        uint256 deadline = block.timestamp - 1; // already expired

        vm.expectRevert();
        token.permit(signer, bob, 1e18, deadline, 0, bytes32(0), bytes32(0));
    }

    // ── Fuzz: mint within cap ─────────────────────────────────────────────────

    /// @dev Any amount that keeps totalSupply ≤ MAX_SUPPLY must succeed.
    function testFuzz_mintWithinCap(uint256 amount) public {
        uint256 remaining = MAX_SUPPLY - token.totalSupply();
        amount = bound(amount, 0, remaining);

        vm.prank(owner);
        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertLe(token.totalSupply(), MAX_SUPPLY);
    }

    /// @dev Any amount that pushes totalSupply over MAX_SUPPLY must revert.
    function testFuzz_mintOverCapReverts(uint256 excess) public {
        excess = bound(excess, 1, type(uint128).max);
        uint256 remaining = MAX_SUPPLY - token.totalSupply();

        // Fill up to cap first (skip if remaining is very large to keep fuzz fast)
        if (remaining > 0 && remaining <= type(uint128).max) {
            vm.prank(owner);
            token.mint(alice, remaining);
        }

        vm.prank(owner);
        vm.expectRevert("GovernanceToken: cap exceeded");
        token.mint(alice, excess);
    }

    // ── Fuzz: delegation voting power ─────────────────────────────────────────

    function testFuzz_votingPowerAfterDelegate(address delegatee) public {
        vm.assume(delegatee != address(0));
        vm.prank(owner);
        token.delegate(delegatee);
        assertEq(token.getVotes(delegatee), token.balanceOf(owner));
    }

    // ── Fuzz: transfer preserves total supply ─────────────────────────────────

    function testFuzz_transferPreservesTotalSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != owner);
        amount = bound(amount, 0, token.balanceOf(owner));
        uint256 supplyBefore = token.totalSupply();

        vm.prank(owner);
        require(
            token.transfer(to, amount),
            "Transfer failed"
        );

        assertEq(token.totalSupply(), supplyBefore);
    }
}
