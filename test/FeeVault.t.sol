// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/vault/FeeVault.sol";
import "../src/mocks/MockERC20.sol";

// ── Shared setup ──────────────────────────────────────────────────────────────

contract FeeVaultBase is Test {
    FeeVault   internal vault;
    MockERC20  internal asset;

    address internal owner     = makeAddr("owner");
    address internal alice     = makeAddr("alice");
    address internal bob       = makeAddr("bob");
    address internal collector = makeAddr("collector");

    function setUp() public virtual {
        asset = new MockERC20("Mock USDC", "mUSDC", 6);
        vm.prank(owner);
        vault = new FeeVault(address(asset), owner);

        // Fund accounts with type(uint64).max so fuzz tests never run out of tokens
        asset.mint(alice,     type(uint64).max);
        asset.mint(bob,       type(uint64).max);
        asset.mint(collector, type(uint64).max);

        // Approvals
        vm.prank(alice);     asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);       asset.approve(address(vault), type(uint256).max);
        vm.prank(collector); asset.approve(address(vault), type(uint256).max);
        vm.prank(owner);     asset.approve(address(vault), type(uint256).max);

        // Set collector
        vm.prank(owner);
        vault.setFeeCollector(collector);
    }
}

// ── Unit tests ────────────────────────────────────────────────────────────────

contract FeeVaultUnitTest is FeeVaultBase {

    // ── Construction ─────────────────────────────────────────────────────────

    function test_assetAddress() public view {
        assertEq(vault.asset(), address(asset));
    }

    function test_initialTotalAssets() public view {
        assertEq(vault.totalAssets(), 0);
    }

    function test_initialTotalSupply() public view {
        assertEq(vault.totalSupply(), 0);
    }

    function test_nameAndSymbol() public view {
        assertEq(vault.name(),   "FeeVault Share");
        assertEq(vault.symbol(), "fvSHARE");
    }

    // ── Deposit ──────────────────────────────────────────────────────────────

    function test_depositMintsShares() public {
        uint256 assets = 1_000e6;
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(),   assets);
    }

    function test_depositEmitsEvent() public {
        uint256 expectedShares = vault.previewDeposit(100e6);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        // ERC4626 Deposit(sender, owner, assets, shares)
        emit IERC4626.Deposit(alice, alice, 100e6, expectedShares);
        vault.deposit(100e6, alice);
    }

    // ── Withdraw / Redeem ────────────────────────────────────────────────────

    function test_redeemBurnsShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000e6, alice);

        vm.prank(alice);
        uint256 assetsOut = vault.redeem(shares, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(assetsOut, 1_000e6);
    }

    function test_withdrawReducesAssets() public {
        vm.prank(alice);
        vault.deposit(1_000e6, alice);

        vm.prank(alice);
        vault.withdraw(500e6, alice, alice);

        assertEq(vault.totalAssets(), 500e6);
    }

    // ── depositFees ──────────────────────────────────────────────────────────

    function test_depositFeesIncreasesAssets() public {
        // Seed vault with one LP
        vm.prank(alice);
        vault.deposit(1_000e6, alice);

        uint256 assetsBefore = vault.totalAssets();
        uint256 sharesBefore = vault.balanceOf(alice);

        // Push fees — no new shares issued
        vm.prank(collector);
        vault.depositFees(100e6);

        assertEq(vault.totalAssets(),   assetsBefore + 100e6);
        assertEq(vault.balanceOf(alice), sharesBefore); // shares unchanged
    }

    function test_depositFeesRaisesSharePrice() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000e6, alice);

        vm.prank(collector);
        vault.depositFees(500e6); // +50% assets

        // Same shares now worth more assets — allow 1 wei rounding tolerance (ERC-4626 rounds down)
        uint256 redeemable = vault.previewRedeem(shares);
        assertApproxEqAbs(redeemable, 1_500e6, 1);
    }

    function test_depositFeesEventEmitted() public {
        vm.prank(alice);
        vault.deposit(1_000e6, alice);

        vm.prank(collector);
        vm.expectEmit(true, false, false, true);
        emit FeeVault.FeesReceived(collector, 200e6);
        vault.depositFees(200e6);
    }

    function test_nonCollectorCannotDepositFees() public {
        vm.prank(alice);
        vm.expectRevert(FeeVault.NotFeeCollector.selector);
        vault.depositFees(1e6);
    }

    // ── setFeeCollector ───────────────────────────────────────────────────────

    function test_ownerCanUpdateCollector() public {
        vm.prank(owner);
        vault.setFeeCollector(alice);
        assertEq(vault.feeCollector(), alice);
    }

    function test_nonOwnerCannotUpdateCollector() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setFeeCollector(alice);
    }

    // ── ERC-4626 rounding: preview vs actual ─────────────────────────────────

    function test_previewDepositMatchesActual() public {
        uint256 assets = 12_345e6;
        uint256 expected = vault.previewDeposit(assets);

        vm.prank(alice);
        uint256 actual = vault.deposit(assets, alice);
        assertEq(actual, expected);
    }

    function test_previewRedeemMatchesActual() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        uint256 expected = vault.previewRedeem(shares);
        vm.prank(alice);
        uint256 actual = vault.redeem(shares, alice, alice);
        assertEq(actual, expected);
    }

    // ── Two LP share-price fairness ───────────────────────────────────────────

    function test_twoLPsShareFeesProportionally() public {
        // Alice deposits 1000, Bob deposits 1000 → equal shares
        vm.prank(alice);
        vault.deposit(1_000e6, alice);
        vm.prank(bob);
        vault.deposit(1_000e6, bob);

        // Push 200 in fees → +100 per LP
        vm.prank(collector);
        vault.depositFees(200e6);

        uint256 aliceAssets = vault.previewRedeem(vault.balanceOf(alice));
        uint256 bobAssets   = vault.previewRedeem(vault.balanceOf(bob));

        assertEq(aliceAssets, bobAssets);
        assertApproxEqAbs(aliceAssets, 1_100e6, 1); // 1 wei ERC-4626 rounding tolerance
    }
}

// ── Fuzz tests ────────────────────────────────────────────────────────────────

contract FeeVaultFuzzTest is FeeVaultBase {

    /// EIP-4626 §: previewDeposit MUST NOT return more shares than deposit.
    function testFuzz_previewDepositLeqActual(uint64 assets) public {
        vm.assume(assets > 0);
        uint256 preview = vault.previewDeposit(assets);

        vm.prank(alice);
        uint256 actual = vault.deposit(assets, alice);

        assertLe(preview, actual + 1); // preview ≤ actual (rounding down)
    }

    /// EIP-4626 §: previewRedeem MUST NOT return more assets than redeem.
    function testFuzz_previewRedeemLeqActual(uint64 assets) public {
        vm.assume(assets > 0);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 preview = vault.previewRedeem(shares);
        vm.prank(alice);
        uint256 actual = vault.redeem(shares, alice, alice);

        assertLe(preview, actual + 1); // preview ≤ actual (rounding down)
    }

    /// EIP-4626 §: convertToShares then convertToAssets MUST return ≤ original.
    function testFuzz_convertRoundtrip(uint64 assets) public view {
        vm.assume(assets > 0);
        uint256 shares     = vault.convertToShares(assets);
        uint256 backAssets = vault.convertToAssets(shares);
        assertLe(backAssets, assets);
    }

    /// Total supply after deposit must equal shares minted.
    function testFuzz_totalSupplyTracksDeposits(uint64 a, uint64 b) public {
        vm.assume(a > 0 && b > 0);
        vm.prank(alice);
        uint256 sharesA = vault.deposit(a, alice);
        vm.prank(bob);
        uint256 sharesB = vault.deposit(b, bob);

        assertEq(vault.totalSupply(), sharesA + sharesB);
    }

    /// depositFees must never reduce totalAssets.
    function testFuzz_depositFeesNeverReducesAssets(uint64 seed, uint64 fees) public {
        vm.assume(seed > 0 && fees > 0);
        vm.prank(alice);
        vault.deposit(seed, alice);

        uint256 before = vault.totalAssets();
        vm.prank(collector);
        vault.depositFees(fees);

        assertGe(vault.totalAssets(), before);
    }

    /// maxWithdraw must never exceed totalAssets.
    function testFuzz_maxWithdrawLeqTotalAssets(uint64 assets) public {
        vm.assume(assets > 0);
        vm.prank(alice);
        vault.deposit(assets, alice);

        assertLe(vault.maxWithdraw(alice), vault.totalAssets());
    }
}

// ── Invariant handler ─────────────────────────────────────────────────────────

contract FeeVaultHandler is Test {
    FeeVault  internal vault;
    MockERC20 internal asset;

    address public actor    = makeAddr("actor");
    address internal colAddr  = makeAddr("colAddr");

    constructor(FeeVault vault_, MockERC20 asset_) {
        vault = vault_;
        asset = asset_;

        asset.mint(actor,   type(uint128).max);
        asset.mint(colAddr, type(uint128).max);
        vm.prank(actor);   asset.approve(address(vault), type(uint256).max);
        vm.prank(colAddr); asset.approve(address(vault), type(uint256).max);

        // Make colAddr the fee collector
        address vaultOwner = vault.owner();
        vm.prank(vaultOwner);
        vault.setFeeCollector(colAddr);
    }

    function deposit(uint256 assets) public {
        assets = bound(assets, 1, 1e12); // 1 µUSDC – 1M USDC
        vm.prank(actor);
        vault.deposit(assets, actor);
    }

    function redeem(uint256 sharePct) public {
        uint256 bal = vault.balanceOf(actor);
        if (bal == 0) return;
        uint256 shares = bound(sharePct, 1, bal);
        vm.prank(actor);
        vault.redeem(shares, actor, actor);
    }

    function pushFees(uint256 fees) public {
        if (vault.totalSupply() == 0) return; // no LPs to accrue to
        fees = bound(fees, 1, 1e10);
        vm.prank(colAddr);
        vault.depositFees(fees);
    }
}

contract FeeVaultInvariantTest is FeeVaultBase {
    FeeVaultHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new FeeVaultHandler(vault, asset);
        targetContract(address(handler));
    }

    /// INV-1: vault token balance == totalAssets() at all times.
    function invariant_totalAssetsMatchesBalance() public view {
        assertEq(
            asset.balanceOf(address(vault)),
            vault.totalAssets()
        );
    }

    /// INV-2: convertToAssets(convertToShares(x)) ≤ x  (no free assets from rounding).
    function invariant_convertRoundtripNoInflation() public view {
        uint256 probe = 1e6; // 1 USDC
        if (vault.totalSupply() == 0) return;
        uint256 shares = vault.convertToShares(probe);
        uint256 back   = vault.convertToAssets(shares);
        assertLe(back, probe);
    }

    /// INV-4: previewRedeem(shares) ≤ maxRedeem assets (consistent limits).
    function invariant_previewRedeemLeqMaxRedeem() public view {
        uint256 shares = vault.balanceOf(handler.actor());
        if (shares == 0) return;
        assertLe(
            vault.previewRedeem(shares),
            vault.maxWithdraw(handler.actor())
        );
    }
}
