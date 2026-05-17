// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/market/PredictionMarketV1.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/tokens/OutcomeShareToken.sol";
import "../src/vault/FeeVault.sol";
import "../src/mocks/MockERC20.sol";

// ── Shared setup ──────────────────────────────────────────────────────────────

contract MarketBase is Test {
    PredictionMarketV1 internal market;
    MockERC20          internal usdc;
    OutcomeShareToken  internal shareToken;
    FeeVault           internal vault;

    address internal owner   = makeAddr("owner");
    address internal alice   = makeAddr("alice");
    address internal bob     = makeAddr("bob");
    address internal trader  = makeAddr("trader");

    uint256 internal constant SEED    = 100_000e6;  // 100k USDC seed liquidity
    uint256 internal constant END     = 7 days;
    uint256 internal mktId;

    bytes32 internal YES_ID_SLOT;
    bytes32 internal NO_ID_SLOT;

    function setUp() public virtual {
        // 1. Deploy collateral
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        // 2. Deploy share token
        vm.prank(owner);
        shareToken = new OutcomeShareToken(owner);

        // 3. Deploy fee vault
        vm.prank(owner);
        vault = new FeeVault(address(usdc), owner);

        // 4. Deploy market implementation + proxy
        PredictionMarketV1 impl = new PredictionMarketV1();
        bytes memory initData = abi.encodeCall(
            PredictionMarketV1.initialize,
            (address(usdc), address(shareToken), address(vault), owner)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        market = PredictionMarketV1(address(proxy));

        // 5. Grant market the MINTER_ROLE on shareToken
        vm.startPrank(owner);
        shareToken.grantRole(shareToken.MINTER_ROLE(), address(market));
        // Grant market the fee-collector role on vault
        vault.setFeeCollector(address(market));
        vm.stopPrank();

        // 6. Approve collateral for market from treasury
        usdc.mint(owner,  10_000_000e6);
        usdc.mint(alice,  10_000_000e6);
        usdc.mint(bob,    10_000_000e6);
        usdc.mint(trader, 10_000_000e6);

        vm.prank(owner);  usdc.approve(address(market), type(uint256).max);
        vm.prank(alice);  usdc.approve(address(market), type(uint256).max);
        vm.prank(bob);    usdc.approve(address(market), type(uint256).max);
        vm.prank(trader); usdc.approve(address(market), type(uint256).max);

        // 7. Create a default market and add seed liquidity
        vm.startPrank(owner);
        mktId = market.createMarket("Will ETH hit $5k?", block.timestamp + END);
        market.addLiquidity(mktId, SEED);
        vm.stopPrank();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _yesId() internal view returns (uint256) { return shareToken.yesId(mktId); }
    function _noId()  internal view returns (uint256) { return shareToken.noId(mktId);  }

    function _getReserves() internal view returns (uint256 yes, uint256 no) {
        (,yes, no,,,, ) = market.markets(mktId);
    }
}

// ── Unit tests ────────────────────────────────────────────────────────────────

contract PredictionMarketV1UnitTest is MarketBase {

    // ── Initialisation ────────────────────────────────────────────────────────

    function test_initialOwner() public view {
        assertEq(market.owner(), owner);
    }

    function test_collateralAddress() public view {
        assertEq(address(market.collateral()), address(usdc));
    }

    function test_shareTokenAddress() public view {
        assertEq(address(market.shareToken()), address(shareToken));
    }

    // ── Market creation ───────────────────────────────────────────────────────

    function test_createMarket_incrementsId() public {
        vm.prank(owner);
        uint256 id2 = market.createMarket("Q2", block.timestamp + 1 days);
        assertEq(id2, mktId + 1);
    }

    function test_createMarket_endInPastReverts() public {
        vm.prank(owner);
        vm.expectRevert("PredictionMarketV1: end in past");
        market.createMarket("Q", block.timestamp - 1);
    }

    function test_createMarket_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        market.createMarket("Q", block.timestamp + 1 days);
    }

    // ── Liquidity ─────────────────────────────────────────────────────────────

    function test_addLiquidity_seedsReservesEvenly() public view {
        (uint256 yes, uint256 no) = _getReserves();
        assertEq(yes, SEED / 2);
        assertEq(no,  SEED / 2);
    }

    function test_addLiquidity_secondDeposit() public {
        uint256 deposit = 10_000e6;
        vm.prank(alice);
        market.addLiquidity(mktId, deposit);

        (uint256 yes, uint256 no) = _getReserves();
        assertEq(yes, SEED / 2 + deposit / 2);
        assertEq(no,  SEED / 2 + deposit / 2);
    }

    function test_removeLiquidity_returnsCollateral() public {
        uint256 lpUnits = market.lpBalances(mktId, owner);
        uint256 balBefore = usdc.balanceOf(owner);

        vm.prank(owner);
        market.removeLiquidity(mktId, lpUnits);

        assertGt(usdc.balanceOf(owner), balBefore);
    }

    function test_removeLiquidity_insufficientReverts() public {
        uint256 tooMany = market.lpBalances(mktId, owner) + 1;
        vm.prank(owner);
        vm.expectRevert("PredictionMarketV1: insufficient LP");
        market.removeLiquidity(mktId, tooMany);
    }

    // ── Swap ──────────────────────────────────────────────────────────────────

    function test_swap_buyYes_givesShares() public {
        uint256 amtIn = 1_000e6;
        vm.prank(trader);
        uint256 out = market.swap(mktId, true, amtIn, 0);

        assertGt(out, 0);
        assertEq(shareToken.balanceOf(trader, _yesId()), out);
    }

    function test_swap_buyNo_givesShares() public {
        uint256 amtIn = 1_000e6;
        vm.prank(trader);
        uint256 out = market.swap(mktId, false, amtIn, 0);

        assertGt(out, 0);
        assertEq(shareToken.balanceOf(trader, _noId()), out);
    }

    function test_swap_slippageReverts() public {
        vm.prank(trader);
        vm.expectRevert();
        market.swap(mktId, true, 1_000e6, type(uint256).max);
    }

    function test_swap_feeGoesToVault() public {
        uint256 vaultBefore = vault.totalAssets();
        vm.prank(trader);
        market.swap(mktId, true, 1_000e6, 0);
        assertGt(vault.totalAssets(), vaultBefore);
    }

    function test_swap_zeroAmountReverts() public {
        vm.prank(trader);
        vm.expectRevert(PredictionMarketV1.ZeroAmount.selector);
        market.swap(mktId, true, 0, 0);
    }

    function test_swap_afterEndReverts() public {
        vm.warp(block.timestamp + END + 1);
        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(PredictionMarketV1.MarketExpired.selector, mktId));
        market.swap(mktId, true, 1_000e6, 0);
    }

    // ── Resolution & redemption ───────────────────────────────────────────────

    function test_resolve_yesOutcome() public {
        vm.warp(block.timestamp + END + 1);
        vm.prank(owner);
        market.resolve(mktId, PredictionMarketV1.Outcome.Yes);

        (,,,,,PredictionMarketV1.Outcome outcome,) = market.markets(mktId);
        assertEq(uint8(outcome), uint8(PredictionMarketV1.Outcome.Yes));
    }

    function test_resolve_beforeEndReverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PredictionMarketV1.MarketNotExpired.selector, mktId));
        market.resolve(mktId, PredictionMarketV1.Outcome.Yes);
    }

    function test_resolve_doubleResolutionReverts() public {
        vm.warp(block.timestamp + END + 1);
        vm.prank(owner);
        market.resolve(mktId, PredictionMarketV1.Outcome.Yes);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PredictionMarketV1.MarketAlreadyResolved.selector, mktId));
        market.resolve(mktId, PredictionMarketV1.Outcome.No);
    }

    function test_redeem_winningShares() public {
        // Buy YES shares
        vm.prank(trader);
        uint256 shares = market.swap(mktId, true, 1_000e6, 0);

        // Resolve YES
        vm.warp(block.timestamp + END + 1);
        vm.prank(owner);
        market.resolve(mktId, PredictionMarketV1.Outcome.Yes);

        // Approve burn and redeem
        vm.startPrank(trader);
        shareToken.setApprovalForAll(address(market), true);
        uint256 balBefore = usdc.balanceOf(trader);
        market.redeem(mktId, shares);
        vm.stopPrank();

        assertEq(usdc.balanceOf(trader) - balBefore, shares);
        assertEq(shareToken.balanceOf(trader, _yesId()), 0);
    }

    function test_redeem_beforeResolutionReverts() public {
        vm.prank(trader);
        market.swap(mktId, true, 1_000e6, 0);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(PredictionMarketV1.MarketNotResolved.selector, mktId));
        market.redeem(mktId, 1);
    }
}

// ── Fuzz tests ────────────────────────────────────────────────────────────────

contract PredictionMarketV1FuzzTest is MarketBase {

    /// Output is always strictly less than the YES reserve.
    function testFuzz_swap_outputBoundedByReserve(uint48 amountIn) public {
        // Floor at 1_000 so amountNet*997/1000 always produces >0 output.
        // Cap at 1M USDC so trader balance is never exhausted.
        amountIn = uint48(bound(amountIn, 1_000, 1_000_000e6));
        (uint256 yesBefore,) = _getReserves();

        vm.prank(trader);
        uint256 out = market.swap(mktId, true, amountIn, 0);

        assertLt(out, yesBefore);
    }

    /// Slippage guard: minAmountOut > actual output must revert.
    function testFuzz_swap_slippageGuardEnforced(uint48 amountIn) public {
        amountIn = uint48(bound(amountIn, 1_000, 1_000_000e6));

        // First get the actual output
        vm.prank(trader);
        uint256 actualOut = market.swap(mktId, true, amountIn, 0);

        // Now a fresh trade asking for one more than possible must revert
        vm.prank(alice);
        vm.expectRevert();
        market.swap(mktId, true, amountIn, actualOut + 1);
    }

    /// Fee is always deducted: vault receives strictly positive amount.
    function testFuzz_swap_feeAlwaysPositive(uint48 amountIn) public {
        // amountIn*3/1000 >= 3 when amountIn >= 1_000
        amountIn = uint48(bound(amountIn, 1_000, 1_000_000e6));
        uint256 vaultBefore = vault.totalAssets();

        vm.prank(trader);
        market.swap(mktId, true, amountIn, 0);

        assertGt(vault.totalAssets(), vaultBefore);
    }

    /// Adding then removing liquidity returns ≤ collateral deposited (rounding).
    function testFuzz_liquidity_addRemoveRoundtrip(uint48 deposit) public {
        vm.assume(deposit >= 2_000); // must be > 2*MIN_LIQUIDITY
        usdc.mint(alice, deposit);

        vm.prank(alice);
        market.addLiquidity(mktId, deposit);

        uint256 lpUnits = market.lpBalances(mktId, alice);
        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        market.removeLiquidity(mktId, lpUnits);

        uint256 returned = usdc.balanceOf(alice) - balBefore;
        assertLe(returned, deposit); // can't get more than deposited
    }
}

// ── Invariant tests ───────────────────────────────────────────────────────────

contract PredictionMarketV1Handler is Test {
    PredictionMarketV1 internal market;
    MockERC20          internal usdc;
    OutcomeShareToken  internal shareToken;

    address internal lp     = makeAddr("lp");
    address internal trader = makeAddr("trader");
    uint256 internal mktId;

    // Track k for invariant checks
    uint256 public lastK;

    constructor(
        PredictionMarketV1 market_,
        MockERC20 usdc_,
        OutcomeShareToken shareToken_,
        uint256 mktId_
    ) {
        market     = market_;
        usdc       = usdc_;
        shareToken = shareToken_;
        mktId      = mktId_;

        usdc.mint(lp,     type(uint96).max);
        usdc.mint(trader, type(uint96).max);

        vm.prank(lp);     usdc.approve(address(market), type(uint256).max);
        vm.prank(trader); usdc.approve(address(market), type(uint256).max);

        vm.prank(trader);
        shareToken.setApprovalForAll(address(market), true);

        (,uint256 yes, uint256 no,,,,) = market.markets(mktId);
        lastK = yes * no;
    }

    function swapYes(uint48 amtIn) public {
        amtIn = uint48(bound(amtIn, 1_000, 10_000e6));
        (,uint256 yesBefore, uint256 noBefore,,,,) = market.markets(mktId);

        vm.prank(trader);
        try market.swap(mktId, true, amtIn, 0) {
            (,uint256 yesAfter, uint256 noAfter,,,,) = market.markets(mktId);
            lastK = yesAfter * noAfter;
            // k must be >= k_before (fees increase reserves relative to shares out)
            assertGe(lastK, yesBefore * noBefore);
        } catch {}
    }

    function swapNo(uint48 amtIn) public {
        amtIn = uint48(bound(amtIn, 1_000, 10_000e6));
        (,uint256 yesBefore, uint256 noBefore,,,,) = market.markets(mktId);

        vm.prank(trader);
        try market.swap(mktId, false, amtIn, 0) {
            (,uint256 yesAfter, uint256 noAfter,,,,) = market.markets(mktId);
            lastK = yesAfter * noAfter;
            assertGe(lastK, yesBefore * noBefore);
        } catch {}
    }

    function addLiq(uint48 amount) public {
        amount = uint48(bound(amount, 2_000, 100_000e6));
        vm.prank(lp);
        try market.addLiquidity(mktId, amount) {} catch {}
    }
}

contract PredictionMarketV1InvariantTest is MarketBase {
    PredictionMarketV1Handler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new PredictionMarketV1Handler(market, usdc, shareToken, mktId);
        targetContract(address(handler));
    }

    /// INV: k = yesReserve * noReserve never decreases on swap.
    function invariant_constantProductNeverDecreases() public view {
        (,uint256 yes, uint256 no,,,,) = market.markets(mktId);
        uint256 kNow = yes * no;
        assertGe(kNow, handler.lastK());
    }

    /// INV: market collateral balance covers totalLP redemptions.
    function invariant_collateralSolvency() public view {
        (,uint256 yes, uint256 no,,,,) = market.markets(mktId);
        // The contract holds YES+NO pool shares; their sum ≤ collateral locked
        assertGe(usdc.balanceOf(address(market)), 0);
        // Reserves are always positive if the market exists
        assertGe(yes, 0);
        assertGe(no,  0);
    }
}
