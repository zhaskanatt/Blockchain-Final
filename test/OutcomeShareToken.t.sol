// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/tokens/OutcomeShareToken.sol";

contract OutcomeShareTokenTest is Test {
    OutcomeShareToken internal token;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant MKT_0 = 0;
    uint256 internal constant MKT_1 = 1;

    // Cached roles and IDs — computed before any vm.prank so external calls
    // never accidentally consume a prank.
    bytes32 internal MINTER_ROLE;
    uint256 internal YES0; // yesId(MKT_0)
    uint256 internal NO0; // noId(MKT_0)

    // Pure local helpers — never make external calls, safe under vm.prank.
    function _yesId(uint256 m) internal pure returns (uint256) {
        return m << 1;
    }

    function _noId(uint256 m) internal pure returns (uint256) {
        return (m << 1) | 1;
    }

    function setUp() public {
        vm.prank(admin);
        token = new OutcomeShareToken(admin);

        // Cache roles/IDs before any prank
        MINTER_ROLE = token.MINTER_ROLE();
        YES0 = _yesId(MKT_0);
        NO0 = _noId(MKT_0);

        // Grant minter role; use startPrank so the whole block runs as admin
        vm.startPrank(admin);
        token.grantRole(MINTER_ROLE, minter);
        vm.stopPrank();
    }

    // ── Unit: token-ID encoding ───────────────────────────────────────────────

    function test_yesIdEncoding() public pure {
        assertEq(_yesId(0), 0);
        assertEq(_yesId(1), 2);
        assertEq(_yesId(5), 10);
    }

    function test_noIdEncoding() public pure {
        assertEq(_noId(0), 1);
        assertEq(_noId(1), 3);
        assertEq(_noId(5), 11);
    }

    function test_yesAndNoIdsAreDistinct() public pure {
        for (uint256 m = 0; m < 10; m++) {
            assertTrue(_yesId(m) != _noId(m));
        }
    }

    function test_decodeIdRoundtrip() public view {
        (uint256 mktId, bool isNo) = token.decodeId(_yesId(42));
        assertEq(mktId, 42);
        assertFalse(isNo);

        (mktId, isNo) = token.decodeId(_noId(42));
        assertEq(mktId, 42);
        assertTrue(isNo);
    }

    // ── Unit: market registration ─────────────────────────────────────────────

    function test_registerMarket() public {
        vm.prank(minter);
        vm.expectEmit(true, false, false, true);
        emit OutcomeShareToken.MarketRegistered(MKT_0, "Will ETH hit $5k?");
        token.registerMarket(MKT_0, "Will ETH hit $5k?");

        assertTrue(token.marketRegistered(MKT_0));
        assertEq(token.getQuestion(MKT_0), "Will ETH hit $5k?");
    }

    function test_registerMarketDuplicateReverts() public {
        vm.prank(minter);
        token.registerMarket(MKT_0, "Q");

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(OutcomeShareToken.MarketAlreadyRegistered.selector, MKT_0));
        token.registerMarket(MKT_0, "Q again");
    }

    function test_getQuestionUnregisteredReverts() public {
        vm.expectRevert(abi.encodeWithSelector(OutcomeShareToken.MarketNotRegistered.selector, 999));
        token.getQuestion(999);
    }

    function test_nonMinterCannotRegister() public {
        vm.prank(alice);
        vm.expectRevert();
        token.registerMarket(MKT_0, "Q");
    }

    // ── Unit: minting ─────────────────────────────────────────────────────────

    function test_mintYesShares() public {
        vm.prank(minter);
        token.mint(alice, YES0, 100e18, "");
        assertEq(token.balanceOf(alice, YES0), 100e18);
    }

    function test_mintNoShares() public {
        vm.prank(minter);
        token.mint(alice, NO0, 200e18, "");
        assertEq(token.balanceOf(alice, NO0), 200e18);
    }

    function test_mintBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = YES0;
        ids[1] = NO0;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50e18;
        amounts[1] = 50e18;

        vm.prank(minter);
        token.mintBatch(alice, ids, amounts, "");

        assertEq(token.balanceOf(alice, ids[0]), 50e18);
        assertEq(token.balanceOf(alice, ids[1]), 50e18);
    }

    function test_nonMinterCannotMint() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, YES0, 1e18, "");
    }

    // ── Unit: burning ─────────────────────────────────────────────────────────

    function test_burnReducesBalance() public {
        vm.prank(minter);
        token.mint(alice, YES0, 100e18, "");

        vm.prank(minter);
        token.burn(alice, YES0, 40e18);

        assertEq(token.balanceOf(alice, YES0), 60e18);
    }

    function test_burnBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = YES0;
        ids[1] = NO0;

        uint256[] memory mintAmounts = new uint256[](2);
        mintAmounts[0] = 100e18;
        mintAmounts[1] = 80e18;

        vm.prank(minter);
        token.mintBatch(alice, ids, mintAmounts, "");

        uint256[] memory burnAmounts = new uint256[](2);
        burnAmounts[0] = 30e18;
        burnAmounts[1] = 20e18;

        vm.prank(minter);
        token.burnBatch(alice, ids, burnAmounts);

        assertEq(token.balanceOf(alice, ids[0]), 70e18);
        assertEq(token.balanceOf(alice, ids[1]), 60e18);
    }

    function test_nonMinterCannotBurn() public {
        vm.prank(minter);
        token.mint(alice, YES0, 100e18, "");

        vm.prank(alice);
        vm.expectRevert();
        token.burn(alice, YES0, 1e18);
    }

    // ── Unit: ERC-1155 transfer ───────────────────────────────────────────────

    function test_safeTransferFrom() public {
        vm.prank(minter);
        token.mint(alice, YES0, 100e18, "");

        vm.prank(alice);
        token.safeTransferFrom(alice, bob, YES0, 40e18, "");

        assertEq(token.balanceOf(alice, YES0), 60e18);
        assertEq(token.balanceOf(bob, YES0), 40e18);
    }

    function test_transferDoesNotCrossYesNo() public {
        vm.prank(minter);
        token.mint(alice, YES0, 100e18, "");

        vm.prank(alice);
        token.safeTransferFrom(alice, bob, YES0, 100e18, "");

        assertEq(token.balanceOf(bob, NO0), 0);
    }

    // ── Unit: AccessControl ───────────────────────────────────────────────────

    function test_adminCanGrantMinterRole() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, alice);
        assertTrue(token.hasRole(MINTER_ROLE, alice));
    }

    function test_adminCanRevokeMinterRole() public {
        vm.prank(admin);
        token.revokeRole(MINTER_ROLE, minter);
        assertFalse(token.hasRole(MINTER_ROLE, minter));

        vm.prank(minter);
        vm.expectRevert();
        token.mint(alice, YES0, 1e18, "");
    }

    function test_supportsERC1155Interface() public view {
        assertTrue(token.supportsInterface(0xd9b67a26)); // ERC-1155
    }

    function test_supportsAccessControlInterface() public view {
        assertTrue(token.supportsInterface(0x7965db0b)); // AccessControl
    }

    // ── Fuzz: token-ID encoding is collision-free ─────────────────────────────

    function testFuzz_yesNoIdsNeverCollide(uint128 marketId) public pure {
        assertNotEq(_yesId(marketId), _noId(marketId));
    }

    function testFuzz_differentMarketsNeverShareIds(uint128 a, uint128 b) public pure {
        vm.assume(a != b);
        assertNotEq(_yesId(a), _yesId(b));
        assertNotEq(_noId(a), _noId(b));
        assertNotEq(_yesId(a), _noId(b));
    }

    function testFuzz_decodeInvertsEncode(uint128 marketId) public view {
        (uint256 mktA, bool isNoA) = token.decodeId(_yesId(marketId));
        assertEq(mktA, marketId);
        assertFalse(isNoA);

        (uint256 mktB, bool isNoB) = token.decodeId(_noId(marketId));
        assertEq(mktB, marketId);
        assertTrue(isNoB);
    }

    // ── Fuzz: mint + burn balance invariant ───────────────────────────────────

    function testFuzz_mintThenBurnRestoresBalance(uint128 amount) public {
        vm.assume(amount > 0);
        uint256 before = token.balanceOf(alice, YES0);

        vm.prank(minter);
        token.mint(alice, YES0, amount, "");
        assertEq(token.balanceOf(alice, YES0), before + amount);

        vm.prank(minter);
        token.burn(alice, YES0, amount);
        assertEq(token.balanceOf(alice, YES0), before);
    }

    // ── Fuzz: yes + no shares are independent ────────────────────────────────

    function testFuzz_yesAndNoBalancesAreIndependent(uint96 yesAmt, uint96 noAmt) public {
        vm.prank(minter);
        token.mint(alice, YES0, yesAmt, "");

        vm.prank(minter);
        token.mint(alice, NO0, noAmt, "");

        assertEq(token.balanceOf(alice, YES0), yesAmt);
        assertEq(token.balanceOf(alice, NO0), noAmt);
    }
}
