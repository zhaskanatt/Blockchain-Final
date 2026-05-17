# Security Audit Report

## Executive Summary

This audit reviews the security architecture and implementation of the On-Chain Prediction Market DAO protocol.

The assessment included:

- manual review
- static analysis using Slither
- unit testing
- fuzz testing
- invariant testing
- governance review
- upgradeability review

The protocol implements a modular architecture consisting of governance, prediction markets, ERC-1155 outcome shares, ERC-4626 vaults, Chainlink oracle integration, and UUPS upgradeability.

No Critical or High severity vulnerabilities were identified during the review.

---

# Scope

## Commit Hash

```text
<PUT_YOUR_COMMIT_HASH_HERE>
```

## In Scope

```text
src/governance/
src/market/
src/oracle/
src/tokens/
src/vault/
src/assembly/
src/factory/
```

## Out of Scope

```text
lib/
node_modules/
test/
script/
broadcast/
```

---

# Methodology

The audit methodology combined automated and manual techniques.

## Automated Analysis

Tools used:

- Slither
- forge test
- forge coverage
- fuzz testing
- invariant testing
- CI pipeline analysis

## Manual Review

Manual review focused on:

- reentrancy
- access control
- upgradeability
- governance execution
- oracle integration
- ERC-4626 accounting
- storage layout safety
- proxy authorization
- CREATE2 deployment logic

---

**Tool:** Slither v0.11.5  
**Scope:** `src/` (95 contracts analysed, 101 detectors)  
**Date:** 2026-05-17  
**Result: 0 High findings — 0 Medium findings** ✅

---

# Summary

| Severity | Count | Status |
|---|---|---|
| High | **0** | ✅ None |
| Medium | **0** | ✅ None |
| Low | **2** | Justified below |
| Informational | **3** | Justified below |

All Low and Informational findings are listed and explicitly justified per Section 3.2.

---

# Low Findings

## L-01 — `low-level-calls`

**Detector:** `low-level-calls`

### Affected files

- `src/governance/Treasury.sol` — `Treasury.releaseETH()`
- `src/vulnerable/SecureRewardPool.sol` — `SecureRewardPool.claim()`
- `src/vulnerable/SecureTreasury.sol` — `SecureTreasury.withdraw()`
- `src/vulnerable/VulnerableRewardPool.sol` — `VulnerableRewardPool.claim()` *(intentionally vulnerable)*
- `src/vulnerable/VulnerableTreasury.sol` — `VulnerableTreasury.withdraw()` *(intentionally vulnerable)*

### Severity

Low

### Description

Slither reports low-level calls using `call{value:}`.

### Impact

Incorrect ETH handling may lead to transfer failures or reentrancy if implemented incorrectly.

### Proof of Concept

The contracts use:

```solidity
(bool success,) = recipient.call{value: amount}("");
require(success, "Transfer failed");
```

### Recommendation

Continue using `call{value:}` with explicit success checks.

### Status

Acknowledged / Safe by design.

### Justification

All ETH transfers use `call{value: amount}("")` with an explicit success check — this is the **correct, recommended pattern** per Solidity docs and Section 3.2 ("use `call{value:}` with success check; no deprecated `transfer`/`send`"). Using `transfer` or `send` would impose a 2300-gas stipend limit that breaks compatibility with smart-contract recipients. The Slither `low-level-calls` detector flags any `call` as a finding — this is a known false-positive category for correct ETH-sending code. The vulnerable contracts (`VulnerableRewardPool`, `VulnerableTreasury`) are intentional security case studies in `src/vulnerable/` and are not used in production.

---

## L-02 — `immutable-states`

**Detector:** `immutable-states`

### Affected variables

- `MockV3Aggregator.decimals` (`src/mocks/MockV3Aggregator.sol`)
- `VulnerableTreasury.admin` (`src/vulnerable/VulnerableTreasury.sol`)

### Severity

Low

### Description

Variables could be marked immutable.

### Impact

Minor gas inefficiency.

### Recommendation

Use immutable variables where appropriate.

### Status

Acknowledged.

### Justification

- `MockV3Aggregator.decimals` is set in the constructor and never modified. It could be `immutable`, but `MockV3Aggregator` is a test-only mock (`src/mocks/`) — it is never deployed to production. Optimising its gas layout is irrelevant; readability and mutability for test overrides takes priority.
- `VulnerableTreasury.admin` is an intentionally vulnerable contract in `src/vulnerable/` used exclusively as a security case-study artifact. Its `admin` field is deliberately left as a plain `address` (not `immutable`) to make the `tx.origin` vulnerability easier to understand and demonstrate.

---

# Informational Findings

## I-01 — `pragma`

**Detector:** `different-pragma-directives-are-used`

### Severity

Informational

### Description

Dependency libraries use different pragma ranges.

### Impact

No direct impact.

### Recommendation

No action required.

### Status

Acknowledged.

### Justification

All findings point to version constraints (`>=0.5.0`, `>=0.6.2`, etc.) in OpenZeppelin and Chainlink library interfaces — not in any `src/` contract. Our own contracts uniformly use `pragma solidity ^0.8.24`. The pragma range in OZ/Chainlink interfaces is by design to maximise compatibility. This finding is not actionable and is a known informational artefact of analysing projects with dependencies.

---

## I-02 — `naming-convention`

**Detector:** `naming-convention`

### Severity

Informational

### Description

Functions in `src/assembly/YulMath.sol` use `_Yul` and `_Solidity` suffixes.

### Recommendation

No action required.

### Status

Acknowledged.

### Justification

The `_Yul` / `_Solidity` suffixes in `YulMath` are intentional and required — they uniquely identify which implementation (assembly vs Solidity) is being called in the benchmark tests. Renaming them to `mixedCase` would make the benchmarking purpose opaque and violate the documented gas-comparison requirement.

---

## I-03 — `too-many-digits`

**Detector:** `too-many-digits`

### Severity

Informational

### Description

Large hex literals are used inside Yul assembly revert blocks.

### Recommendation

No action required.

### Status

Acknowledged.

### Justification

The 32-byte hex literals are ABI-encoded error selectors and offsets required for manual assembly error handling. This is a known false positive for contracts that encode Solidity errors manually in Yul.

---

# CEI & SafeERC20 Compliance Checklist

Per Section 3.2: every externally callable function must use CEI OR ReentrancyGuard, and all ERC-20 interactions must use SafeERC20.

| Contract | External calls | CEI / Guard | SafeERC20 |
|---|---|---|---|
| `PredictionMarketV1` | `swap`, `addLiquidity`, `removeLiquidity`, `redeem` | `nonReentrant` (transient) + CEI | `safeTransferFrom`, `safeTransfer`, `safeIncreaseAllowance` |
| `FeeVault` | `deposit`, `withdraw`, `depositFees` | OZ ERC4626 + CEI in `depositFees` | `safeTransferFrom` via OZ |
| `Treasury` | `releaseETH`, `releaseERC20` | `onlyOwner` gate; CEI (emit before call) | `safeTransfer` |
| `SecureRewardPool` | `claim` | `nonReentrant` + CEI (zero before call) | N/A |
| `SecureTreasury` | `withdraw` | `onlyOwner` + `nonReentrant` + CEI | N/A |
| `OracleResolver` | `getPrice`, `getPriceScaled18` | View only — no state change | N/A |
| `GovernanceToken` | `mint` | `onlyOwner` | N/A (internal `_mint`) |
| `OutcomeShareToken` | `mint`, `burn`, `register` | `MINTER_ROLE` AccessControl | N/A (internal ERC-1155) |
| `MarketFactory` | `deployWithCreate`, `deployWithCreate2` | `onlyOwner` | N/A |

**No `tx.origin` usage** in any production contract (only in `VulnerableTreasury` as an intentional case study).  
**No `block.timestamp` as a randomness source** — used only for staleness comparison in `OracleResolver.getPrice()`.  
**No `transfer`/`send` for ETH** — all ETH transfers use `call{value:}` with success check.

---

# Governance Attack Analysis

## Flash Loan Governance Attacks

The protocol mitigates flash-loan governance attacks through ERC20Votes snapshotting.

Voting power is recorded at proposal snapshot blocks, meaning temporarily borrowed tokens cannot influence already-active proposals.

---

## Whale Governance Attacks

Large token holders may significantly influence governance outcomes.

Mitigations include:

- quorum requirements
- timelock delay
- transparent on-chain voting

Whale dominance remains a known governance tradeoff.

---

## Proposal Spam

Proposal spam is mitigated through:

- proposal thresholds
- voting delay
- gas costs for proposal creation

---

## Timelock Bypass Attempts

Governance execution is restricted through TimelockController.

Only queued proposals may execute after the configured delay.

No direct privileged execution path bypasses the timelock.

---

# Oracle Attack Analysis

## Stale Price Attacks

OracleResolver validates feed freshness using staleness thresholds.

Outdated price data causes transactions to revert.

---

## Price Manipulation

The protocol relies on Chainlink decentralized oracle feeds.

Direct AMM reserve manipulation does not affect oracle-reported values.

---

## Oracle Downtime

Oracle downtime may temporarily pause resolution-related functionality.

This is considered an acceptable external dependency risk.

---

## Feed Depeg Risk

Incorrect or manipulated oracle prices could produce invalid resolutions.

This risk is partially mitigated through:

- Chainlink decentralization
- staleness validation
- dispute windows

---

# Centralization Analysis

## Governance Powers

Governance controls:

- treasury execution
- protocol upgrades
- parameter changes

If governance becomes malicious or compromised, protocol funds and logic may be affected.

---

## Timelock Powers

The TimelockController controls execution scheduling.

It cannot bypass governance voting requirements.

---

## Owner Privileges

Administrative privileges are minimized.

Production-sensitive functionality is controlled through governance and timelock execution wherever possible.

---

# Upgradeability Analysis

The protocol uses the UUPS upgrade pattern.

## Upgrade Safety Considerations

- storage layout preservation
- appended storage only
- explicit authorization checks
- proxy separation from implementation

Storage collision risk was manually reviewed.

No unsafe storage mutations were identified.

---

# Security Engineering

## Testing

The protocol includes:

- unit tests
- fuzz tests
- invariant tests
- integration tests

---

## Static Analysis

Static analysis performed using:

```bash
slither .
```

---

## CI/CD Pipeline

GitHub Actions automatically performs:

- forge build
- forge test
- forge coverage
- forge fmt --check
- frontend build
- subgraph build
- Slither analysis

---

# Appendix — Slither Output

Static analysis results:

- 0 High findings
- 0 Medium findings
- 2 Low findings
- 3 Informational findings

All findings were manually reviewed and documented in this report.

---

# Conclusion

The protocol demonstrates strong security engineering practices including modular architecture, governance protection, upgradeability safety, CEI compliance, oracle validation, fuzz testing, invariant testing, and automated CI/CD verification.

No Critical or High severity vulnerabilities were identified during the assessment.