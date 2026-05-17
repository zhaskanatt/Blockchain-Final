// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/oracle/OracleResolver.sol";
import "../src/mocks/MockV3Aggregator.sol";

contract OracleResolverTest is Test {
    OracleResolver internal oracle;
    MockV3Aggregator internal mock;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    uint8 internal constant DECIMALS = 8;
    int256 internal constant INIT_PRICE = 2_600e8; // $2 600 in 8-decimal Chainlink units
    uint256 internal constant THRESHOLD = 3_600; // 1 hour staleness window

    function setUp() public {
        mock = new MockV3Aggregator(DECIMALS, INIT_PRICE);

        vm.prank(owner);
        oracle = new OracleResolver(address(mock), THRESHOLD, owner);
    }

    // ── Unit: construction ────────────────────────────────────────────────────

    function test_feedAddress() public view {
        assertEq(address(oracle.feed()), address(mock));
    }

    function test_stalenessThreshold() public view {
        assertEq(oracle.stalenessThreshold(), THRESHOLD);
    }

    function test_owner() public view {
        assertEq(oracle.owner(), owner);
    }

    function test_feedDecimals() public view {
        assertEq(oracle.feedDecimals(), DECIMALS);
    }

    function test_feedDescription() public view {
        assertEq(oracle.feedDescription(), "Mock / USD");
    }

    // ── Unit: happy path ──────────────────────────────────────────────────────

    function test_getPrice_returnsCorrectPrice() public view {
        (int256 price,) = oracle.getPrice();
        assertEq(price, INIT_PRICE);
    }

    function test_getPrice_returnsUpdatedAt() public view {
        (, uint256 updatedAt) = oracle.getPrice();
        assertEq(updatedAt, block.timestamp);
    }

    function test_getPriceScaled18_correct() public view {
        // INIT_PRICE = 2_600e8 with 8 dec → scaled to 18 dec = 2_600e18
        uint256 scaled = oracle.getPriceScaled18();
        assertEq(scaled, 2_600e18);
    }

    // ── Unit: staleness check ─────────────────────────────────────────────────

    function test_getPrice_revertsWhenStale() public {
        // Warp past the staleness threshold
        vm.warp(block.timestamp + THRESHOLD + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                OracleResolver.StalePrice.selector,
                block.timestamp - THRESHOLD - 1, // updatedAt
                THRESHOLD,
                block.timestamp
            )
        );
        oracle.getPrice();
    }

    function test_getPrice_acceptsExactlyAtThreshold() public {
        // Exactly at threshold boundary: block.timestamp - updatedAt == THRESHOLD
        uint256 deployedAt = block.timestamp;
        vm.warp(deployedAt + THRESHOLD);
        // Should NOT revert (age == threshold, not strictly greater)
        (int256 price,) = oracle.getPrice();
        assertEq(price, INIT_PRICE);
    }

    function test_getPrice_revertsOneSecondPastThreshold() public {
        vm.warp(block.timestamp + THRESHOLD + 1);
        vm.expectRevert();
        oracle.getPrice();
    }

    // ── Unit: negative / zero price ───────────────────────────────────────────

    function test_getPrice_revertsOnNegativeAnswer() public {
        mock.updateRoundData(-1, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(OracleResolver.InvalidPrice.selector, int256(-1)));
        oracle.getPrice();
    }

    function test_getPrice_revertsOnZeroAnswer() public {
        mock.updateRoundData(0, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(OracleResolver.InvalidPrice.selector, int256(0)));
        oracle.getPrice();
    }

    // ── Unit: updatedAt == 0 ──────────────────────────────────────────────────

    function test_getPrice_revertsWhenNeverUpdated() public {
        mock.setNeverUpdated();
        vm.expectRevert(OracleResolver.FeedNeverUpdated.selector);
        oracle.getPrice();
    }

    // ── Unit: incomplete round ────────────────────────────────────────────────

    function test_getPrice_revertsOnIncompleteRound() public {
        mock.setIncompleteRound(INIT_PRICE);
        vm.expectRevert(); // IncompleteRound
        oracle.getPrice();
    }

    // ── Unit: fresh update clears staleness ───────────────────────────────────

    function test_getPrice_freshUpdateAfterStale() public {
        // Go stale
        vm.warp(block.timestamp + THRESHOLD + 1);

        // Oracle pushes a fresh round
        mock.updateRoundData(3_000e8, block.timestamp);

        // Should succeed now
        (int256 price,) = oracle.getPrice();
        assertEq(price, 3_000e8);
    }

    // ── Unit: admin — setFeed ─────────────────────────────────────────────────

    function test_setFeed_ownerCanUpdate() public {
        MockV3Aggregator newMock = new MockV3Aggregator(DECIMALS, 3_000e8);
        vm.prank(owner);
        oracle.setFeed(address(newMock));
        assertEq(address(oracle.feed()), address(newMock));
    }

    function test_setFeed_emitsEvent() public {
        MockV3Aggregator newMock = new MockV3Aggregator(DECIMALS, 3_000e8);
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit OracleResolver.FeedUpdated(address(mock), address(newMock));
        oracle.setFeed(address(newMock));
    }

    function test_setFeed_zeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert(OracleResolver.InvalidConfiguration.selector);
        oracle.setFeed(address(0));
    }

    function test_setFeed_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.setFeed(address(mock));
    }

    // ── Unit: admin — setStalenessThreshold ───────────────────────────────────

    function test_setStalenessThreshold_ownerCanUpdate() public {
        vm.prank(owner);
        oracle.setStalenessThreshold(7_200);
        assertEq(oracle.stalenessThreshold(), 7_200);
    }

    function test_setStalenessThreshold_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit OracleResolver.StalenessThresholdUpdated(THRESHOLD, 7_200);
        oracle.setStalenessThreshold(7_200);
    }

    function test_setStalenessThreshold_zeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(OracleResolver.InvalidConfiguration.selector);
        oracle.setStalenessThreshold(0);
    }

    function test_setStalenessThreshold_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.setStalenessThreshold(100);
    }

    // ── Unit: constructor guards ──────────────────────────────────────────────

    function test_constructor_zeroFeedReverts() public {
        vm.expectRevert(OracleResolver.InvalidConfiguration.selector);
        new OracleResolver(address(0), THRESHOLD, owner);
    }

    function test_constructor_zeroThresholdReverts() public {
        vm.expectRevert(OracleResolver.InvalidConfiguration.selector);
        new OracleResolver(address(mock), 0, owner);
    }

    // ── Fuzz: valid price always passes all checks ────────────────────────────

    function testFuzz_getPrice_validPriceAlwaysPasses(int128 answer) public {
        vm.assume(answer > 0);
        mock.updateRoundData(answer, block.timestamp);
        (int256 price,) = oracle.getPrice();
        assertEq(price, answer);
    }

    /// Any age ≤ threshold must succeed; any age > threshold must revert.
    function testFuzz_getPrice_stalenessGate(uint32 age) public {
        uint256 deployTime = block.timestamp;
        mock.updateRoundData(INIT_PRICE, deployTime);
        vm.warp(deployTime + age);

        if (age <= THRESHOLD) {
            (int256 price,) = oracle.getPrice();
            assertEq(price, INIT_PRICE);
        } else {
            vm.expectRevert();
            oracle.getPrice();
        }
    }

    /// getPriceScaled18 is always 1e10 × raw answer for an 8-decimal feed.
    function testFuzz_getPriceScaled18_correctScaling(uint64 rawPrice) public {
        vm.assume(rawPrice > 0);
        mock.updateRoundData(int256(uint256(rawPrice)), block.timestamp);
        uint256 scaled = oracle.getPriceScaled18();
        assertEq(scaled, uint256(rawPrice) * 1e10);
    }

    // ── Fuzz: MockV3Aggregator round management ───────────────────────────────

    function testFuzz_mock_roundIdIncrementsOnEveryUpdate(uint8 updates) public {
        vm.assume(updates > 0 && updates < 50);
        uint80 startId = mock.currentRoundId();
        for (uint256 i; i < updates; i++) {
            mock.updateRoundData(INIT_PRICE, block.timestamp);
        }
        assertEq(mock.currentRoundId(), startId + updates);
    }
}
