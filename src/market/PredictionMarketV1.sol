// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "../assembly/YulMath.sol";
import "../tokens/OutcomeShareToken.sol";
import "../vault/FeeVault.sol";

/// @title PredictionMarketV1
/// @notice UUPS-upgradeable binary prediction market with a built-from-scratch
///         constant-product AMM (x·y=k).
///
/// Architecture
/// ────────────
/// • One collateral token (e.g. USDC) backs all markets.
/// • Each market has two outcome token pools: YES (id 0) and NO (id 1).
/// • LPs add collateral and receive equal amounts of YES+NO shares into both
///   pool reserves; they track their share via an internal LP-balance mapping.
/// • Traders swap collateral → outcome shares using the CPMM formula with a
///   0.3 % fee. Slippage is enforced via a minAmountOut guard.
/// • 0.3 % of every swap is sent to the FeeVault (as collateral).
/// • On resolution the Timelock/owner calls resolve(); winners redeem 1:1
///   against collateral.
///
/// Storage layout (append-only — V2 must only ADD slots below)
/// ─────────────────────────────────────────────────────────────
/// OZ v5 uses ERC-7201 namespaced storage for OwnableUpgradeable / Initializable,
/// so those internals do NOT occupy sequential slots. Our own state starts at slot 0:
///   slot 0  : collateral    (IERC20)
///   slot 1  : shareToken    (OutcomeShareToken)
///   slot 2  : feeVault      (FeeVault)
///   slot 3  : nextMarketId  (uint256)
///   slot 4  : markets       (mapping)
///   slot 5  : lpBalances    (mapping)
///
/// ReentrancyGuardTransient uses transient storage (EIP-1153) — no persistent slot.
/// V2 additions start at slot 6.

contract PredictionMarketV1 is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    // ── Constants ─────────────────────────────────────────────────────────────

    uint256 public constant FEE_NUM = 3; // 0.3 %
    uint256 public constant FEE_DEN = 1000;
    uint256 public constant MIN_LIQUIDITY = 1_000; // locked forever on first add

    // ── Data structures ───────────────────────────────────────────────────────

    enum Outcome {
        Unresolved,
        Yes,
        No,
        Invalid
    }

    struct Market {
        string question;
        uint256 yesReserve; // pool reserve of YES shares
        uint256 noReserve; // pool reserve of NO shares
        uint256 totalLP; // total LP units outstanding
        uint256 endTime; // unix timestamp after which no new trades
        Outcome outcome;
        bool exists;
    }

    // ── State (storage layout documented above — do NOT reorder) ──────────────

    IERC20 public collateral;
    OutcomeShareToken public shareToken;
    FeeVault public feeVault;
    uint256 public nextMarketId;

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => uint256)) public lpBalances; // marketId → LP → units

    // ── Events ────────────────────────────────────────────────────────────────

    event MarketCreated(uint256 indexed marketId, string question, uint256 endTime);
    event LiquidityAdded(uint256 indexed marketId, address indexed lp, uint256 collateralIn, uint256 lpUnits);
    event LiquidityRemoved(uint256 indexed marketId, address indexed lp, uint256 lpUnits, uint256 collateralOut);
    event Swapped(uint256 indexed marketId, address indexed trader, bool buyYes, uint256 amountIn, uint256 amountOut);
    event Resolved(uint256 indexed marketId, Outcome outcome);
    event Redeemed(uint256 indexed marketId, address indexed user, uint256 shares, uint256 collateral);

    // ── Errors ────────────────────────────────────────────────────────────────

    error MarketDoesNotExist(uint256 marketId);
    error MarketAlreadyResolved(uint256 marketId);
    error MarketNotResolved(uint256 marketId);
    error MarketExpired(uint256 marketId);
    error MarketNotExpired(uint256 marketId);
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error InsufficientLiquidity();
    error ZeroAmount();
    error InvalidOutcome();

    // ── Initializer (replaces constructor for UUPS) ───────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address collateral_, address shareToken_, address feeVault_, address initialOwner_)
        external
        initializer
    {
        __Ownable_init(initialOwner_);
        // UUPSUpgradeable and ReentrancyGuardTransient have no init in OZ v5

        collateral = IERC20(collateral_);
        shareToken = OutcomeShareToken(shareToken_);
        feeVault = FeeVault(feeVault_);
    }

    // ── UUPS upgrade authorisation ────────────────────────────────────────────

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ── Market lifecycle ──────────────────────────────────────────────────────

    function createMarket(string calldata question, uint256 endTime) external onlyOwner returns (uint256 marketId) {
        require(endTime > block.timestamp, "PredictionMarketV1: end in past");
        marketId = nextMarketId++;

        markets[marketId] = Market({
            question: question,
            yesReserve: 0,
            noReserve: 0,
            totalLP: 0,
            endTime: endTime,
            outcome: Outcome.Unresolved,
            exists: true
        });

        shareToken.registerMarket(marketId, question);
        emit MarketCreated(marketId, question, endTime);
    }

    // ── Liquidity provision ───────────────────────────────────────────────────

    /// @notice Add liquidity. LP receives equal YES+NO reserves and LP units.
    /// @param collateralAmount Amount of collateral to deposit.
    /// @param marketId         Target market.
    function addLiquidity(uint256 marketId, uint256 collateralAmount) external nonReentrant {
        if (collateralAmount == 0) revert ZeroAmount();
        Market storage mkt = _requireOpen(marketId);

        collateral.safeTransferFrom(msg.sender, address(this), collateralAmount);

        uint256 lpUnits;
        uint256 halfCollateral = collateralAmount / 2;

        if (mkt.totalLP == 0) {
            // First liquidity: seed both reserves equally, lock MIN_LIQUIDITY
            mkt.yesReserve = halfCollateral;
            mkt.noReserve = halfCollateral;
            lpUnits = YulMath.sqrt_Yul(halfCollateral * halfCollateral) - MIN_LIQUIDITY;
            // Mint MIN_LIQUIDITY to address(1) to lock permanently
            lpBalances[marketId][address(1)] = MIN_LIQUIDITY;
            mkt.totalLP = MIN_LIQUIDITY;
        } else {
            // Proportional add: maintain current YES/NO ratio
            // lpUnits = collateralAmount * totalLP / (yesReserve + noReserve)
            uint256 totalReserve = mkt.yesReserve + mkt.noReserve;
            lpUnits = (collateralAmount * mkt.totalLP) / totalReserve;
            mkt.yesReserve += halfCollateral;
            mkt.noReserve += halfCollateral;
        }

        if (lpUnits == 0) revert InsufficientLiquidity();

        lpBalances[marketId][msg.sender] += lpUnits;
        mkt.totalLP += lpUnits;

        // Mint YES and NO shares into the pool reserves (held by this contract)
        shareToken.mint(address(this), shareToken.yesId(marketId), halfCollateral, "");
        shareToken.mint(address(this), shareToken.noId(marketId), halfCollateral, "");

        emit LiquidityAdded(marketId, msg.sender, collateralAmount, lpUnits);
    }

    /// @notice Remove liquidity pro-rata, returning collateral to LP.
    function removeLiquidity(uint256 marketId, uint256 lpUnits) external nonReentrant {
        if (lpUnits == 0) revert ZeroAmount();
        Market storage mkt = _requireMarketExists(marketId);
        require(lpBalances[marketId][msg.sender] >= lpUnits, "PredictionMarketV1: insufficient LP");

        uint256 totalLP = mkt.totalLP;
        uint256 yesOut = (mkt.yesReserve * lpUnits) / totalLP;
        uint256 noOut = (mkt.noReserve * lpUnits) / totalLP;
        // collateral backing = min(yesOut, noOut) * 2 (balanced reserves)
        uint256 colOut = yesOut + noOut; // both denominated in collateral units

        lpBalances[marketId][msg.sender] -= lpUnits;
        mkt.totalLP -= lpUnits;
        mkt.yesReserve -= yesOut;
        mkt.noReserve -= noOut;

        // Burn the pool shares
        shareToken.burn(address(this), shareToken.yesId(marketId), yesOut);
        shareToken.burn(address(this), shareToken.noId(marketId), noOut);

        collateral.safeTransfer(msg.sender, colOut);
        emit LiquidityRemoved(marketId, msg.sender, lpUnits, colOut);
    }

    // ── AMM swap ──────────────────────────────────────────────────────────────

    /// @notice Buy outcome shares with collateral.
    /// @param marketId     Target market.
    /// @param buyYes       True → buy YES shares, False → buy NO shares.
    /// @param amountIn     Collateral to spend.
    /// @param minAmountOut Slippage guard — revert if output < this.
    function swap(uint256 marketId, bool buyYes, uint256 amountIn, uint256 minAmountOut)
        external
        virtual
        nonReentrant
        returns (uint256 amountOut)
    {
        return _swap(marketId, buyYes, amountIn, minAmountOut);
    }

    /// @dev Internal swap logic shared between V1 and V2.
    function _swap(uint256 marketId, bool buyYes, uint256 amountIn, uint256 minAmountOut)
        internal
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        Market storage mkt = _requireOpen(marketId);

        collateral.safeTransferFrom(msg.sender, address(this), amountIn);

        // Collect fee → vault
        uint256 fee = (amountIn * FEE_NUM) / FEE_DEN;
        uint256 amountNet = amountIn - fee;

        if (fee > 0) {
            collateral.safeIncreaseAllowance(address(feeVault), fee);
            feeVault.depositFees(fee);
        }

        // CPMM quote using Yul hot-path
        uint256 reserveIn;
        uint256 reserveOut;
        if (buyYes) {
            reserveIn = mkt.noReserve;
            reserveOut = mkt.yesReserve;
        } else {
            reserveIn = mkt.yesReserve;
            reserveOut = mkt.noReserve;
        }

        amountOut = YulMath.getAmountOut_Yul(amountNet, reserveIn, reserveOut);

        if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);
        if (amountOut == 0) revert InsufficientLiquidity();

        // Update reserves
        if (buyYes) {
            mkt.noReserve += amountNet;
            mkt.yesReserve -= amountOut;
        } else {
            mkt.yesReserve += amountNet;
            mkt.noReserve -= amountOut;
        }

        // Transfer outcome shares from pool to trader
        uint256 tokenId = buyYes ? shareToken.yesId(marketId) : shareToken.noId(marketId);
        shareToken.safeTransferFrom(address(this), msg.sender, tokenId, amountOut, "");

        emit Swapped(marketId, msg.sender, buyYes, amountIn, amountOut);
    }

    // ── Resolution & redemption ───────────────────────────────────────────────

    function resolve(uint256 marketId, Outcome outcome) external onlyOwner {
        Market storage mkt = _requireMarketExists(marketId);
        if (mkt.outcome != Outcome.Unresolved) revert MarketAlreadyResolved(marketId);
        if (outcome == Outcome.Unresolved) revert InvalidOutcome();
        if (block.timestamp < mkt.endTime) revert MarketNotExpired(marketId);

        mkt.outcome = outcome;
        emit Resolved(marketId, outcome);
    }

    /// @notice Redeem winning shares for collateral at 1:1.
    function redeem(uint256 marketId, uint256 shares) external nonReentrant {
        Market storage mkt = _requireMarketExists(marketId);
        if (mkt.outcome == Outcome.Unresolved) revert MarketNotResolved(marketId);
        if (mkt.outcome == Outcome.Invalid) revert InvalidOutcome();

        bool winnerIsYes = (mkt.outcome == Outcome.Yes);
        uint256 tokenId = winnerIsYes ? shareToken.yesId(marketId) : shareToken.noId(marketId);

        // Burn winner shares and pay 1:1 collateral
        shareToken.burn(msg.sender, tokenId, shares);
        collateral.safeTransfer(msg.sender, shares);

        emit Redeemed(marketId, msg.sender, shares, shares);
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    function _requireMarketExists(uint256 marketId) internal view returns (Market storage mkt) {
        mkt = markets[marketId];
        if (!mkt.exists) revert MarketDoesNotExist(marketId);
    }

    function _requireOpen(uint256 marketId) internal view returns (Market storage mkt) {
        mkt = _requireMarketExists(marketId);
        if (mkt.outcome != Outcome.Unresolved) revert MarketAlreadyResolved(marketId);
        if (block.timestamp >= mkt.endTime) revert MarketExpired(marketId);
    }

    // ── ERC-1155 receiver (pool holds shares) ─────────────────────────────────

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
}
