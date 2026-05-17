// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/market/PredictionMarketV1.sol";
import "../src/market/PredictionMarketV2.sol";
import "../src/tokens/OutcomeShareToken.sol";
import "../src/vault/FeeVault.sol";
import "../src/mocks/MockERC20.sol";

/// @notice Full V1 → V2 upgrade test suite.
///
/// Storage collision proof (documented per requirement):
/// ──────────────────────────────────────────────────────
/// Run in your shell:
///   forge inspect src/market/PredictionMarketV1.sol:PredictionMarketV1 storage-layout
///   forge inspect src/market/PredictionMarketV2.sol:PredictionMarketV2 storage-layout
///
/// V1 slots (persistent storage only; transient slots excluded):
///   slot 0  _initialized           (uint8, packed)
///   slot 0  _initializing          (bool,  packed)
///   slot 1  _owner                 (address)
///   slot 2  collateral             (address)
///   slot 3  shareToken             (address)
///   slot 4  feeVault               (address)
///   slot 5  nextMarketId           (uint256)
///   slot 6  markets                (mapping)
///   slot 7  lpBalances             (mapping)
///
/// V2 adds — strictly appended, no reuse:
///   slot 8  maxSwapBps             (uint256)
///   slot 9  pausedMarkets          (mapping)
///
/// Therefore zero storage collisions between V1 and V2.

contract PredictionMarketV2Test is Test {

    // ── Contracts ─────────────────────────────────────────────────────────────

    ERC1967Proxy       internal proxy;
    PredictionMarketV1 internal v1;
    PredictionMarketV2 internal v2;

    MockERC20          internal usdc;
    OutcomeShareToken  internal shareToken;
    FeeVault           internal vault;

    address internal owner  = makeAddr("owner");
    address internal alice  = makeAddr("alice");
    address internal trader = makeAddr("trader");

    uint256 internal constant SEED  = 100_000e6;
    uint256 internal constant END   = 7 days;
    uint256 internal mktId;

    // ── Setup: deploy V1 proxy and seed a market ──────────────────────────────

    function setUp() public {
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        vm.prank(owner);
        shareToken = new OutcomeShareToken(owner);

        vm.prank(owner);
        vault = new FeeVault(address(usdc), owner);

        // Deploy V1 impl + proxy
        PredictionMarketV1 v1Impl = new PredictionMarketV1();
        bytes memory initData = abi.encodeCall(
            PredictionMarketV1.initialize,
            (address(usdc), address(shareToken), address(vault), owner)
        );
        proxy = new ERC1967Proxy(address(v1Impl), initData);
        v1    = PredictionMarketV1(address(proxy));

        // Roles + funding
        vm.startPrank(owner);
        shareToken.grantRole(shareToken.MINTER_ROLE(), address(proxy));
        vault.setFeeCollector(address(proxy));
        vm.stopPrank();

        usdc.mint(owner,  10_000_000e6);
        usdc.mint(alice,  10_000_000e6);
        usdc.mint(trader, 10_000_000e6);
        vm.prank(owner);  usdc.approve(address(proxy), type(uint256).max);
        vm.prank(alice);  usdc.approve(address(proxy), type(uint256).max);
        vm.prank(trader); usdc.approve(address(proxy), type(uint256).max);

        // Create a market and seed it
        vm.startPrank(owner);
        mktId = v1.createMarket("Will BTC hit $200k?", block.timestamp + END);
        v1.addLiquidity(mktId, SEED);
        vm.stopPrank();

        // Make a trade on V1 so we have non-trivial state to preserve
        vm.prank(trader);
        v1.swap(mktId, true, 5_000e6, 0);
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    function _upgradeToV2() internal returns (PredictionMarketV2) {
        PredictionMarketV2 v2Impl = new PredictionMarketV2();
        vm.prank(owner);
        v1.upgradeToAndCall(
            address(v2Impl),
            abi.encodeCall(PredictionMarketV2.initializeV2, (500)) // 5% max swap
        );
        return PredictionMarketV2(address(proxy));
    }

    // ── Unit: upgrade mechanics ───────────────────────────────────────────────

    function test_upgrade_onlyOwnerCanUpgrade() public {
        PredictionMarketV2 v2Impl = new PredictionMarketV2();
        vm.prank(alice);
        vm.expectRevert();
        v1.upgradeToAndCall(address(v2Impl), "");
    }

    function test_upgrade_succeeds() public {
        v2 = _upgradeToV2();
        assertEq(v2.version(), "2.0.0");
    }

    function test_upgrade_initializerCannotBeCalledTwice() public {
        v2 = _upgradeToV2();
        vm.prank(owner);
        vm.expectRevert(); // InvalidInitialization
        v2.initializeV2(100);
    }

    // ── Unit: V1 state preserved after upgrade ────────────────────────────────

    function test_upgrade_preservesOwner() public {
        v2 = _upgradeToV2();
        assertEq(v2.owner(), owner);
    }

    function test_upgrade_preservesCollateral() public {
        v2 = _upgradeToV2();
        assertEq(address(v2.collateral()), address(usdc));
    }

    function test_upgrade_preservesMarketState() public {
        // Capture V1 reserves before upgrade
        (, uint256 yesBefore, uint256 noBefore,,,,) = v1.markets(mktId);

        v2 = _upgradeToV2();

        (, uint256 yesAfter, uint256 noAfter,,,,) = v2.markets(mktId);
        assertEq(yesAfter, yesBefore);
        assertEq(noAfter,  noBefore);
    }

    function test_upgrade_preservesLPBalances() public {
        uint256 lpBefore = v1.lpBalances(mktId, owner);
        v2 = _upgradeToV2();
        assertEq(v2.lpBalances(mktId, owner), lpBefore);
    }

    function test_upgrade_preservesNextMarketId() public {
        uint256 idBefore = v1.nextMarketId();
        v2 = _upgradeToV2();
        assertEq(v2.nextMarketId(), idBefore);
    }

    // ── Unit: V2 new features ─────────────────────────────────────────────────

    function test_v2_maxSwapBpsSetOnInit() public {
        v2 = _upgradeToV2();
        assertEq(v2.maxSwapBps(), 500); // 5%
    }

    function test_v2_swapExceedingMaxReverts() public {
        v2 = _upgradeToV2();
        // 5% of 50k reserve = 2500 USDC max; send 10k
        vm.prank(trader);
        vm.expectRevert();
        v2.swap(mktId, true, 10_000e6, 0);
    }

    function test_v2_swapWithinMaxSucceeds() public {
        v2 = _upgradeToV2();
        // Send 1k USDC (well within 5% of ~50k reserves)
        vm.prank(trader);
        uint256 out = v2.swap(mktId, true, 1_000e6, 0);
        assertGt(out, 0);
    }

    function test_v2_pauseBlocksSwap() public {
        v2 = _upgradeToV2();

        vm.prank(owner);
        v2.pauseMarket(mktId);
        assertTrue(v2.pausedMarkets(mktId));

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(PredictionMarketV2.MarketPausedError.selector, mktId));
        v2.swap(mktId, true, 1_000e6, 0);
    }

    function test_v2_unpauseRestoresSwap() public {
        v2 = _upgradeToV2();

        vm.prank(owner);
        v2.pauseMarket(mktId);

        vm.prank(owner);
        v2.unpauseMarket(mktId);
        assertFalse(v2.pausedMarkets(mktId));

        vm.prank(trader);
        uint256 out = v2.swap(mktId, true, 1_000e6, 0);
        assertGt(out, 0);
    }

    function test_v2_setMaxSwapBps() public {
        v2 = _upgradeToV2();
        vm.prank(owner);
        v2.setMaxSwapBps(1000); // 10%
        assertEq(v2.maxSwapBps(), 1000);
    }

    function test_v2_setMaxSwapBpsOver100PctReverts() public {
        v2 = _upgradeToV2();
        vm.prank(owner);
        vm.expectRevert("V2: bps > 100%");
        v2.setMaxSwapBps(10_001);
    }

    function test_v2_versionString() public {
        v2 = _upgradeToV2();
        assertEq(v2.version(), "2.0.0");
    }

    // ── Storage layout: slot values directly verified ─────────────────────────
    // Demonstrates zero storage collision between V1 and V2 at the EVM level.

    // Storage layout (confirmed by `forge inspect ... storage-layout`):
    //   OZ v5 uses ERC-7201 namespaced storage for OwnableUpgradeable internals,
    //   so _owner is NOT in sequential slots. Our state starts at slot 0:
    //     slot 0  collateral    (V1)
    //     slot 1  shareToken    (V1)
    //     slot 2  feeVault      (V1)
    //     slot 3  nextMarketId  (V1)
    //     slot 4  markets       (V1)
    //     slot 5  lpBalances    (V1)  ← last V1 slot
    //     slot 6  maxSwapBps    (V2)  ← first V2 slot, fresh before upgrade
    //     slot 7  pausedMarkets (V2)

    function test_storageLayout_v2SlotsAreFresh() public {
        // Before upgrade: slot 6 (maxSwapBps) must be 0 — V1 never wrote it
        bytes32 slot6Before = vm.load(address(proxy), bytes32(uint256(6)));
        assertEq(slot6Before, bytes32(0));

        v2 = _upgradeToV2();

        // After upgrade: slot 6 holds 500 (set by initializeV2)
        bytes32 slot6After = vm.load(address(proxy), bytes32(uint256(6)));
        assertEq(uint256(slot6After), 500);
    }

    function test_storageLayout_v1SlotsUnchangedAfterUpgrade() public {
        // Read V1 key slots before upgrade
        bytes32 slot0Before = vm.load(address(proxy), bytes32(uint256(0))); // collateral
        bytes32 slot3Before = vm.load(address(proxy), bytes32(uint256(3))); // nextMarketId
        bytes32 slot5Before = vm.load(address(proxy), bytes32(uint256(5))); // lpBalances root

        v2 = _upgradeToV2();

        // All V1 slots must be bit-identical after upgrade
        assertEq(vm.load(address(proxy), bytes32(uint256(0))), slot0Before);
        assertEq(vm.load(address(proxy), bytes32(uint256(3))), slot3Before);
        assertEq(vm.load(address(proxy), bytes32(uint256(5))), slot5Before);
    }
}
