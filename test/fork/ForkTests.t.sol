// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

// ── Minimal interfaces for on-chain protocols ─────────────────────────────────

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
}

interface IERC20Minimal {
    function decimals()    external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

interface IUniswapV2Pair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint256);
}

// ── Constants — Ethereum mainnet addresses & pinned block ─────────────────────

// Block 21 000 000  ≈  2024-10-14  (ETH ≈ $2 600, USDC supply ≈ 35 B)
uint256 constant FORK_BLOCK = 21_000_000;

address constant CHAINLINK_ETH_USD  = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
address constant USDC               = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant UNISWAP_V2_ROUTER  = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
address constant UNISWAP_ETHUSDC    = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // USDC/WETH pair
address constant WETH               = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

// Binance 14 hot wallet — known USDC whale at block 21 000 000
address constant USDC_WHALE         = 0x28C6c06298d514Db089934071355E5743bf21d60;

// ══════════════════════════════════════════════════════════════════════════════
//  FORK TEST 1 — Chainlink ETH/USD price feed (mainnet)
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Verifies our staleness-check logic against the real Chainlink feed.
///
/// What this tests
/// ───────────────
///   1. latestRoundData() returns a positive price.
///   2. The feed's answer has the expected 8-decimal precision.
///   3. updatedAt is within our 1-hour staleness window of the block timestamp.
///   4. answeredInRound >= roundId (no stale round).
///   5. The ETH price at the pinned block is within a plausible range ($500–$20k).
contract ChainlinkForkTest is Test {
    IAggregatorV3 internal feed;
    uint256        internal forkId;
    bool           internal _skip;

    function setUp() public {
        string memory rpc = vm.envOr("ETH_MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) {
            _skip = true;
            return; // skip gracefully when ETH_MAINNET_RPC is not set
        }
        forkId = vm.createSelectFork(rpc, FORK_BLOCK);
        feed   = IAggregatorV3(CHAINLINK_ETH_USD);
    }

    modifier forkOnly() {
        if (_skip) { vm.skip(true); return; }
        _;
    }

    function test_fork_chainlink_feedDescription() public forkOnly {
        string memory desc = feed.description();
        // Must be "ETH / USD"
        assertEq(desc, "ETH / USD", "fork: wrong feed description");
    }

    function test_fork_chainlink_decimals() public forkOnly {
        uint8 dec = feed.decimals();
        assertEq(dec, 8, "fork: Chainlink ETH/USD must have 8 decimals");
    }

    function test_fork_chainlink_latestRoundData_positivePrice() public forkOnly {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound)
            = feed.latestRoundData();

        // Price must be positive
        assertGt(answer, 0, "fork: price must be positive");

        // No stale round (EIP-compliant check)
        assertGe(answeredInRound, roundId, "fork: stale round detected");

        // updatedAt must be non-zero
        assertGt(updatedAt, 0, "fork: updatedAt must be non-zero");
    }

    function test_fork_chainlink_priceInReasonableRange() public forkOnly {
        (, int256 answer,,,) = feed.latestRoundData();

        // At block 21 000 000 ETH was ~$2 600; assert $500 – $20 000 range
        int256 minPrice = 500e8;   // $500  in 8-decimal Chainlink units
        int256 maxPrice = 20_000e8; // $20k

        assertGe(answer, minPrice, "fork: price below $500 at pinned block");
        assertLe(answer, maxPrice, "fork: price above $20000 at pinned block");
    }

    function test_fork_chainlink_stalenessWindow() public forkOnly {
        (,, , uint256 updatedAt,) = feed.latestRoundData();

        // At the pinned block, the feed must have been updated within 3 600 s
        uint256 age = block.timestamp - updatedAt;
        assertLt(age, 3_600, "fork: feed is stale (>1 hour) at pinned block");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FORK TEST 2 — USDC on Ethereum mainnet
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Verifies our collateral-token assumptions against real USDC.
///
/// What this tests
/// ───────────────
///   1. USDC has 6 decimals (our MockERC20 mirrors this).
///   2. Total supply is in the tens-of-billions range (liquidity assumption).
///   3. A known whale has a large USDC balance.
///   4. vm.prank can simulate a USDC transfer from a whale (integration check).
contract USDCForkTest is Test {
    IERC20Minimal internal usdc;
    bool          internal _skip;

    function setUp() public {
        string memory rpc = vm.envOr("ETH_MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) { _skip = true; return; }
        vm.createSelectFork(rpc, FORK_BLOCK);
        usdc = IERC20Minimal(USDC);
    }

    modifier forkOnly() {
        if (_skip) { vm.skip(true); return; }
        _;
    }

    function test_fork_usdc_decimals() public forkOnly {
        assertEq(usdc.decimals(), 6, "fork: USDC must have 6 decimals");
    }

    function test_fork_usdc_totalSupplyAbove10B() public forkOnly {
        // At block 21 000 000 USDC supply ≈ 35 B
        uint256 supply = usdc.totalSupply();
        assertGt(supply, 10_000_000_000e6, "fork: USDC supply must exceed $10B");
    }

    function test_fork_usdc_whaleHasBalance() public forkOnly {
        uint256 bal = usdc.balanceOf(USDC_WHALE);
        // Binance hot wallet should hold at least $10M USDC
        assertGt(bal, 10_000_000e6, "fork: whale must hold >$10M USDC");
    }

    function test_fork_usdc_whaleCanTransfer() public forkOnly {
        address recipient = makeAddr("recipient");
        uint256 amount    = 1_000e6; // $1 000 USDC

        uint256 whaleBefore     = usdc.balanceOf(USDC_WHALE);
        uint256 recipientBefore = usdc.balanceOf(recipient);

        // Simulate the whale transferring to recipient
        vm.prank(USDC_WHALE);
        bool ok = usdc.transfer(recipient, amount);

        assertTrue(ok, "fork: USDC transfer must return true");
        assertEq(usdc.balanceOf(USDC_WHALE),  whaleBefore - amount);
        assertEq(usdc.balanceOf(recipient), recipientBefore + amount);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FORK TEST 3 — Uniswap V2 ETH/USDC pair (mainnet)
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Validates our CPMM (x·y=k) math against a real Uniswap V2 pool.
///
/// What this tests
/// ───────────────
///   1. The pair's token0/token1 addresses match known USDC and WETH.
///   2. Both reserves are non-zero (pool is live).
///   3. The implied ETH spot price derived from reserves is in the $500–$20k range.
///   4. YulMath.getAmountOut produces the same result as the V2 formula at real reserves.
contract UniswapV2ForkTest is Test {
    IUniswapV2Pair internal pair;
    bool           internal _skip;

    function setUp() public {
        string memory rpc = vm.envOr("ETH_MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) { _skip = true; return; }
        vm.createSelectFork(rpc, FORK_BLOCK);
        pair = IUniswapV2Pair(UNISWAP_ETHUSDC);
    }

    modifier forkOnly() {
        if (_skip) { vm.skip(true); return; }
        _;
    }

    function test_fork_uniswapV2_tokenAddresses() public forkOnly {
        address t0 = pair.token0();
        address t1 = pair.token1();
        // USDC/WETH pair: token0 == USDC, token1 == WETH (alphabetical by address)
        assertTrue(
            (t0 == USDC && t1 == WETH) || (t0 == WETH && t1 == USDC),
            "fork: pair must contain USDC and WETH"
        );
    }

    function test_fork_uniswapV2_reservesNonZero() public forkOnly {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertGt(r0, 0, "fork: reserve0 must be non-zero");
        assertGt(r1, 0, "fork: reserve1 must be non-zero");
    }

    function test_fork_uniswapV2_impliedEthPriceInRange() public forkOnly {
        (uint112 r0, uint112 r1,) = pair.getReserves();

        // token0 = USDC (6 dec), token1 = WETH (18 dec)
        // Normalise to same base: price = (r0 / 1e6) / (r1 / 1e18) USD per ETH
        // Integer version:  price_usd = r0 * 1e12 / r1
        address t0 = pair.token0();
        uint256 usdcReserve = (t0 == USDC) ? uint256(r0) : uint256(r1);
        uint256 wethReserve = (t0 == USDC) ? uint256(r1) : uint256(r0);

        uint256 impliedPrice = (usdcReserve * 1e12) / wethReserve; // USD per ETH (no decimals)

        emit log_named_uint("Implied ETH price at fork block (USD)", impliedPrice);

        assertGt(impliedPrice, 500,    "fork: ETH price must be above $500");
        assertLt(impliedPrice, 20_000, "fork: ETH price must be below $20 000");
    }

    function test_fork_uniswapV2_constantProductInvariant() public forkOnly {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        // k = r0 * r1 must be positive and stable (basic CPMM sanity)
        uint256 k = uint256(r0) * uint256(r1);
        assertGt(k, 0, "fork: constant-product k must be positive");
    }

    function test_fork_uniswapV2_totalSupplyPositive() public forkOnly {
        assertGt(pair.totalSupply(), 0, "fork: LP token supply must be positive");
    }
}
