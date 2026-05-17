# Gas Report

## Overview

This document summarizes gas optimization strategies, benchmarking results, and execution-cost analysis for the On-Chain Prediction Market DAO protocol.

Gas benchmarking was performed using:

```bash
forge snapshot
```

The protocol was designed with a strong focus on minimizing gas costs while preserving readability, modularity, and upgrade safety.

---

# Optimization Goals

The protocol optimizes for:

- reduced swap execution costs
- efficient liquidity operations
- low-cost governance interactions
- compact storage usage
- reduced deployment costs on L2 networks
- efficient event indexing
- optimized arithmetic operations

---

# Gas Optimization Techniques

## 1. ERC-1155 Instead of Multiple ERC-20 Tokens

The protocol uses ERC-1155 for outcome shares.

### Benefits

- shared storage layout
- lower deployment costs
- lower mint/burn costs
- batched operations support

### Result

Using a single ERC-1155 contract is significantly cheaper than deploying separate ERC-20 contracts per market.

---

# 2. UUPS Proxy Pattern

The protocol uses UUPS upgradeability.

### Benefits

- lower deployment overhead
- smaller proxy bytecode
- cheaper upgrades compared to Transparent Proxy

### Tradeoff

Upgrade authorization logic must be implemented carefully.

---

# 3. CREATE2 Market Deployment

The factory supports CREATE2 deterministic deployment.

### Benefits

- deterministic addresses
- off-chain address prediction
- reduced operational overhead

---

# 4. SafeERC20 Usage

All ERC20 interactions use OpenZeppelin SafeERC20.

### Benefits

- compatibility with non-standard tokens
- safer transfers
- reduced integration risk

Gas overhead is considered acceptable relative to the security benefits.

---

# 5. ReentrancyGuardTransient

The protocol uses `ReentrancyGuardTransient`.

### Benefits

- lower gas usage than traditional storage-based guards
- efficient protection against recursive calls

---

# 6. Yul Assembly Optimizations

The protocol includes `YulMath.sol` for benchmarking low-level assembly implementations against pure Solidity equivalents.

Compared functions:

- `getAmountOut_Yul`
- `getAmountOut_Solidity`
- `sqrt_Yul`
- `sqrt_Solidity`

---

# Yul vs Solidity Benchmarking

## getAmountOut()

| Implementation | Gas Usage |
|---|---|
| Solidity | Higher |
| Yul Assembly | Lower |

### Observation

The Yul implementation reduces arithmetic overhead and minimizes intermediate stack operations.

---

## sqrt()

| Implementation | Gas Usage |
|---|---|
| Solidity | Higher |
| Yul Assembly | Lower |

### Observation

Manual assembly loops provide measurable savings compared to higher-level Solidity arithmetic.

---

# Contract Deployment Costs

## Approximate Deployment Complexity

| Contract | Relative Cost |
|---|---|
| GovernanceToken | Medium |
| PredictionGovernor | High |
| TimelockController | High |
| FeeVault | Medium |
| PredictionMarketV1 | High |
| OutcomeShareToken | Medium |
| MarketFactory | Medium |
| OracleResolver | Low |

---

# Runtime Cost Analysis

## Swap Operations

Most expensive runtime components:

- reserve updates
- ERC1155 minting
- SafeERC20 transfers

Optimizations used:

- compact arithmetic
- minimized storage writes
- cached variables

---

## Governance Operations

Governance execution is relatively expensive due to:

- proposal storage
- vote checkpointing
- timelock scheduling

These costs are considered acceptable because governance actions are infrequent.

---

## Vault Operations

ERC4626 vault operations remain relatively efficient because:

- OpenZeppelin implementation is heavily optimized
- accounting logic is compact
- fee handling is isolated

---

# Storage Optimization

## Packed Storage

The protocol minimizes unnecessary storage expansion where possible.

Strategies include:

- compact state variables
- avoiding duplicate mappings
- reducing repeated writes

---

## Immutable Usage

Immutable variables are used where appropriate to reduce runtime SLOAD costs.

---

# Event Design Optimization

Events were designed to balance:

- indexing quality
- frontend usability
- gas efficiency

Indexed parameters are limited to high-value query fields.

---

# L1 vs L2 Cost Comparison

## Ethereum Mainnet

Advantages:

- highest decentralization
- strongest security guarantees

Disadvantages:

- very high deployment cost
- expensive governance operations
- expensive swaps

---

## Arbitrum / Optimism / Base

Advantages:

- significantly lower gas fees
- cheaper deployment
- lower frontend interaction costs
- more practical governance participation

Disadvantages:

- external bridge assumptions
- sequencer dependency

---

# CI/CD Gas Validation

Gas benchmarking is integrated into the CI pipeline using:

```bash
forge snapshot
```

The workflow ensures:

- no unexpected gas regressions
- stable benchmark tracking
- reproducible optimization analysis

---

# Tradeoffs

## Readability vs Optimization

The protocol intentionally avoids excessive assembly optimization in critical governance and accounting logic.

Assembly usage is isolated primarily to benchmarking utilities.

---

## Security vs Gas

Security measures such as:

- SafeERC20
- ReentrancyGuard
- TimelockController
- ERC20Votes snapshots

introduce additional gas overhead but significantly improve protocol safety.

---

# Future Optimization Opportunities

Potential future improvements:

- custom errors everywhere
- additional storage packing
- calldata optimization
- reduced event emissions
- more aggressive assembly usage

These optimizations were intentionally deferred to prioritize auditability and maintainability.

---

# Conclusion

The protocol demonstrates production-style gas optimization practices while maintaining strong readability, upgrade safety, modularity, and security guarantees.

The architecture balances:

- performance
- maintainability
- governance safety
- auditability
- deployment efficiency
- frontend usability

Gas costs are significantly reduced on L2 deployments while preserving full protocol functionality.