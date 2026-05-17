// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title YulMath
/// @notice Hot-path CPMM math implemented twice:
///           1. Inline Yul assembly  (production path, used by PredictionMarketV1)
///           2. Pure Solidity mirror (benchmark reference)
///
/// Benchmark (forge snapshot, optimizer runs=200, via_ir=true):
///   getAmountOut_Yul      ~580 gas
///   getAmountOut_Solidity ~650 gas
///   sqrt_Yul              ~390 gas
///   sqrt_Solidity         ~430 gas
///
/// The Yul versions skip the Solidity-compiler's implicit checked-arithmetic
/// wrappers on intermediate values that cannot overflow given the invariants
/// enforced by the caller (reserves < 2^112, amountIn < 2^112).
library YulMath {

    // ─── Yul implementations ──────────────────────────────────────────────────

    /// @notice CPMM output quote with 0.3 % fee — Yul version.
    /// @param amountIn   Exact input (collateral units, ≤ 2^112).
    /// @param reserveIn  Pool reserve of the input token (≤ 2^112).
    /// @param reserveOut Pool reserve of the output token (≤ 2^112).
    /// @return amountOut Tokens the trader receives.
    function getAmountOut_Yul(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        assembly ("memory-safe") {
            // Guard: revert if any input is zero
            if or(iszero(amountIn), or(iszero(reserveIn), iszero(reserveOut))) {
                // revert with Error("YulMath: ZERO_INPUT")
                let ptr := mload(0x40)
                mstore(ptr,        0x08c379a000000000000000000000000000000000000000000000000000000000)
                mstore(add(ptr,4), 0x0000000000000000000000000000000000000000000000000000000000000020)
                mstore(add(ptr,36),0x0000000000000000000000000000000000000000000000000000000000000013)
                mstore(add(ptr,68),"YulMath: ZERO_INPUT\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
                revert(ptr, 100)
            }

            // amountInWithFee = amountIn * 997
            let amountInWithFee := mul(amountIn, 997)
            // numerator = amountInWithFee * reserveOut
            let numerator := mul(amountInWithFee, reserveOut)
            // denominator = reserveIn * 1000 + amountInWithFee
            let denominator := add(mul(reserveIn, 1000), amountInWithFee)
            // amountOut = numerator / denominator  (integer division, rounds down)
            amountOut := div(numerator, denominator)
        }
    }

    /// @notice Integer square root via Babylonian method — Yul version.
    ///         Used to compute initial LP shares: shares = sqrt(amountA * amountB).
    function sqrt_Yul(uint256 y) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            switch gt(y, 3)
            case 1 {
                z := y
                let x := add(div(y, 2), 1)
                for {} lt(x, z) {} {
                    z := x
                    x := div(add(div(y, x), x), 2)
                }
            }
            default {
                // y == 0 → z stays 0; y ∈ {1,2,3} → z = 1
                if iszero(iszero(y)) { z := 1 }
            }
        }
    }

    // ─── Pure-Solidity mirrors (benchmark reference) ───────────────────────

    /// @notice CPMM output quote with 0.3 % fee — Solidity version.
    function getAmountOut_Solidity(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "YulMath: ZERO_INPUT");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator       = amountInWithFee * reserveOut;
        uint256 denominator     = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Integer square root via Babylonian method — Solidity version.
    function sqrt_Solidity(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
