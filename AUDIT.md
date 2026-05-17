# Security Audit Report

**Tool:** Slither v0.11.5  
**Scope:** `src/` (95 contracts analysed, 101 detectors)  
**Date:** 2026-05-17  
**Result: 0 High findings — 0 Medium findings** ✅

---

## Summary

| Severity | Count | Status |
|---|---|---|
| High | **0** | ✅ None |
| Medium | **0** | ✅ None |
| Low | **2** | Justified below |
| Informational | **3** | Justified below |

All Low and Informational findings are listed and explicitly justified per Section 3.2.

---

## Low Findings

### L-01 — `low-level-calls`

**Detector:** `low-level-calls`  
**Affected files:**
- `src/governance/Treasury.sol` — `Treasury.releaseETH()`
- `src/vulnerable/SecureRewardPool.sol` — `SecureRewardPool.claim()`
- `src/vulnerable/SecureTreasury.sol` — `SecureTreasury.withdraw()`
- `src/vulnerable/VulnerableRewardPool.sol` — `VulnerableRewardPool.claim()` *(intentionally vulnerable)*
- `src/vulnerable/VulnerableTreasury.sol` — `VulnerableTreasury.withdraw()` *(intentionally vulnerable)*

**Justification:**  
All ETH transfers use `call{value: amount}("")` with an explicit success check — this is the **correct, recommended pattern** per [Solidity docs](https://docs.soliditylang.org/en/latest/common-patterns.html#withdrawal-from-contracts) and Section 3.2 ("use `call{value:}` with success check; no deprecated `transfer`/`send`"). Using `transfer` or `send` would impose a 2300-gas stipend limit that breaks compatibility with smart-contract recipients. The Slither `low-level-calls` detector flags any `call` as a finding — this is a known false-positive category for correct ETH-sending code. The vulnerable contracts (`VulnerableRewardPool`, `VulnerableTreasury`) are **intentional security case studies** in `src/vulnerable/` and are not used in production.

---

### L-02 — `immutable-states`

**Detector:** `immutable-states`  
**Affected variables:**
- `MockV3Aggregator.decimals` (`src/mocks/MockV3Aggregator.sol`)
- `VulnerableTreasury.admin` (`src/vulnerable/VulnerableTreasury.sol`)

**Justification:**  
- `MockV3Aggregator.decimals` is set in the constructor and never modified. It could be `immutable`, but `MockV3Aggregator` is a **test-only mock** (`src/mocks/`) — it is never deployed to production. Optimising its gas layout is irrelevant; readability and mutability for test overrides takes priority.  
- `VulnerableTreasury.admin` is an **intentionally vulnerable contract** in `src/vulnerable/` used exclusively as a security case-study artifact. Its `admin` field is deliberately left as a plain `address` (not `immutable`) to make the `tx.origin` vulnerability easier to understand and demonstrate.

---

## Informational Findings

### I-01 — `pragma` (version constraints in dependencies)

**Detector:** `different-pragma-directives-are-used`

**Justification:**  
All findings point to version constraints (`>=0.5.0`, `>=0.6.2`, etc.) in **OpenZeppelin and Chainlink library interfaces** — not in any `src/` contract. Our own contracts uniformly use `pragma solidity ^0.8.24`. The pragma range in OZ/Chainlink interfaces is by design to maximise compatibility. This finding is not actionable and is a known informational artefact of analysing projects with dependencies.

---

### I-02 — `naming-convention`

**Detector:** `naming-convention`  
**Affected functions in `src/assembly/YulMath.sol`:**
- `getAmountOut_Yul`, `sqrt_Yul` (Yul assembly implementations)
- `getAmountOut_Solidity`, `sqrt_Solidity` (pure-Solidity mirror functions)

**Also:** `MockV3Aggregator.getRoundData(uint80)._roundId` parameter name inherits Chainlink's own naming.

**Justification:**  
The `_Yul` / `_Solidity` suffixes in `YulMath` are **intentional and required** — they uniquely identify which implementation (assembly vs Solidity) is being called in the benchmark tests. Renaming them to `mixedCase` would make the benchmarking purpose opaque and violate the documented gas-comparison requirement. The `_roundId` parameter mirrors the exact naming used in Chainlink's `AggregatorV3Interface` to stay consistent with the interface contract we implement.

---

### I-03 — `too-many-digits`

**Detector:** `too-many-digits`  
**Affected:** `src/assembly/YulMath.sol` — hex literals in the Yul inline assembly revert block.

**Justification:**  
The 32-byte hex literals (`0x08c379a0...`, `0x0000...0020`, `0x0000...0013`) are the **ABI-encoded error selector and offset for a standard `Error(string)` revert** emitted from Yul assembly. These are not magic numbers — they are the well-known ABI encoding of `keccak256("Error(string)")[:4]` followed by the standard string offset and length. They cannot be expressed as named constants inside an assembly block. This is a known false positive for any contract that encodes Solidity errors manually in Yul.

---

## CEI & SafeERC20 Compliance Checklist

Per Section 3.2: every externally callable function must use CEI OR ReentrancyGuard, and all ERC-20 interactions must use SafeERC20.

| Contract | External calls | CEI / Guard | SafeERC20 |
|---|---|---|---|
| `PredictionMarketV1` | `swap`, `addLiquidity`, `removeLiquidity`, `redeem` | `nonReentrant` (transient) + CEI | `safeTransferFrom`, `safeTransfer`, `safeIncreaseAllowance` |
| `FeeVault` | `deposit`, `withdraw`, `depositFees` | OZ ERC4626 + CEI in `depositFees` | `safeTransferFrom` via OZ |
| `Treasury` | `releaseETH`, `releaseERC20` | `onlyOwner` gate; CEI (emit before call) | `safeTransfer` |
| `SecureRewardPool` | `claim` | `nonReentrant` + CEI (zero before call) | N/A (ETH only) |
| `SecureTreasury` | `withdraw` | `onlyOwner` + `nonReentrant` + CEI | N/A (ETH only) |
| `OracleResolver` | `getPrice`, `getPriceScaled18` | View only — no state change | N/A |
| `GovernanceToken` | `mint` | `onlyOwner` | N/A (internal `_mint`) |
| `OutcomeShareToken` | `mint`, `burn`, `register` | `MINTER_ROLE` AccessControl | N/A (internal ERC-1155) |
| `MarketFactory` | `deployWithCreate`, `deployWithCreate2` | `onlyOwner` | N/A |

**No `tx.origin` usage** in any production contract (only in `VulnerableTreasury` as an intentional case study).  
**No `block.timestamp` as a randomness source** — used only for staleness comparison in `OracleResolver.getPrice()`.  
**No `transfer`/`send` for ETH** — all ETH transfers use `call{value:}` with success check.
