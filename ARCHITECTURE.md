# Architecture Document
## On-Chain Prediction Market DAO

---

# 1. Introduction

## Project Overview

The project is a decentralized on-chain prediction market protocol built using Solidity, Foundry, React, and The Graph. The protocol allows users to create and trade binary prediction markets using a CPMM (Constant Product Market Maker) model while governance is controlled through an on-chain DAO.

The system integrates:

- ERC-20 governance tokens
- ERC-1155 outcome share tokens
- ERC-4626 vaults
- UUPS upgradeable smart contracts
- Chainlink oracle feeds
- OpenZeppelin Governor governance
- Timelock execution
- The Graph indexing
- Frontend dApp using React + Wagmi

The protocol was designed to demonstrate production-grade blockchain engineering practices including upgradeability, governance security, fuzz testing, invariant testing, CI/CD automation, and static analysis.

---

# 2. System Context Diagram (C4 Level 1)

```text
+------------------------------------------------------+
|                     End Users                         |
|------------------------------------------------------|
| - Traders                                            |
| - Liquidity Providers                                |
| - Governance Participants                            |
+--------------------------+---------------------------+
                           |
                           v
+------------------------------------------------------+
|                  Frontend dApp                        |
|------------------------------------------------------|
| React + Vite + Wagmi + Viem + MetaMask              |
+--------------------------+---------------------------+
                           |
                           v
+------------------------------------------------------+
|                 Smart Contract Layer                  |
|------------------------------------------------------|
| GovernanceToken                                      |
| PredictionGovernor                                   |
| TimelockController                                   |
| Treasury                                             |
| MarketFactory                                        |
| PredictionMarketV1 / V2                              |
| OutcomeShareToken                                    |
| FeeVault                                             |
| OracleResolver                                       |
+--------------------------+---------------------------+
                           |
          +----------------+----------------+
          |                                 |
          v                                 v
+----------------------+      +---------------------------+
|   Chainlink Oracle   |      |       The Graph           |
|----------------------|      |---------------------------|
| Price Feeds          |      | Indexed protocol events   |
| Staleness Validation |      | GraphQL query endpoint    |
+----------------------+      +---------------------------+
```

---

# 3. High-Level Architecture

The protocol consists of five major layers:

1. Governance Layer
2. Market Layer
3. Token Layer
4. Vault Layer
5. Indexing & Frontend Layer

The architecture was intentionally modular to isolate responsibilities and simplify upgrades and audits.

---

# 4. Container / Component Diagram

```text
Frontend dApp
    |
    +--> GovernanceToken
    |
    +--> PredictionGovernor
    |         |
    |         +--> TimelockController
    |                     |
    |                     +--> Treasury
    |
    +--> MarketFactory
              |
              +--> PredictionMarketV1 Proxy
              |          |
              |          +--> OutcomeShareToken
              |          +--> FeeVault
              |          +--> OracleResolver
              |
              +--> PredictionMarketV2
```

---

# 5. Governance Layer

## GovernanceToken

The governance token is implemented using OpenZeppelin ERC20Votes and ERC20Permit extensions.

### Features

- Delegated voting
- Vote checkpointing
- Snapshot-based voting
- Gasless approvals via EIP-2612
- Governor compatibility

### Responsibilities

- Voting power management
- Proposal threshold enforcement
- Governance participation

### Security Properties

- Voting power snapshots prevent flash-loan governance attacks
- Delegation prevents double counting
- ERC20Permit reduces approval transaction overhead

---

## PredictionGovernor

The governance system is implemented using OpenZeppelin Governor.

### Responsibilities

- Proposal creation
- Vote collection
- Quorum validation
- Proposal execution

### Governance Lifecycle

```text
Pending
  ↓
Active
  ↓
Succeeded / Defeated
  ↓
Queued
  ↓
Executed
```

### Voting Configuration

- Voting Delay
- Voting Period
- Proposal Threshold
- Quorum Fraction

---

## TimelockController

The protocol uses a governance timelock to delay proposal execution.

### Purpose

- Prevent instant malicious execution
- Give users time to react
- Reduce governance attack surface

### Timelock Delay

2 days.

### Roles

- Proposer Role
- Executor Role
- Admin Role

---

## Treasury

Treasury stores governance-controlled protocol assets.

### Functions

- ETH release
- ERC20 release
- Governance-controlled transfers

### Security

Only the TimelockController can execute treasury operations.

---

# 6. Market Layer

## PredictionMarketV1

PredictionMarketV1 is the core CPMM market implementation.

### Features

- Binary YES/NO markets
- Constant-product pricing
- Liquidity provision
- Fee collection
- Slippage protection
- ERC-1155 share minting

### Pricing Model

The AMM uses the constant product equation:

```text
x * y = k
```

Where:
- x = YES reserve
- y = NO reserve
- k = invariant

### Swap Flow

```text
User
 → deposit collateral
 → AMM pricing calculation
 → fee deduction
 → outcome share minting
```

---

## PredictionMarketV2

PredictionMarketV2 demonstrates protocol upgradeability.

### Upgrade Goals

- Preserve storage layout
- Add new features safely
- Demonstrate UUPS upgrade process

### Upgrade Safety

Storage collisions are avoided by:

- Never reordering variables
- Only appending new variables
- Preserving inheritance layout

---

## MarketFactory

Factory contract deploys markets.

### Deployment Methods

- CREATE
- CREATE2

### Benefits

CREATE2 allows deterministic deployment addresses.

### Responsibilities

- Market deployment
- Market registry
- Factory ownership control

---

# 7. Token Layer

## OutcomeShareToken

ERC-1155 token representing prediction outcomes.

### Token Types

- YES shares
- NO shares

### Token ID Encoding

```text
YES = marketId << 1
NO  = (marketId << 1) | 1
```

### Advantages of ERC-1155

- Lower gas usage
- Multi-token support
- Shared contract logic

---

# 8. Vault Layer

## FeeVault

The FeeVault implements ERC-4626 vault accounting.

### Responsibilities

- LP share accounting
- Fee accumulation
- Deposit handling
- Redemption handling

### Deposit Flow

```text
User
 → approve collateral
 → deposit into vault
 → shares minted
```

### Redemption Flow

```text
User
 → redeem shares
 → vault burns shares
 → collateral returned
```

---

# 9. Oracle Layer

## OracleResolver

The protocol uses Chainlink oracles through an abstraction layer.

### Responsibilities

- Price validation
- Feed freshness validation
- Oracle abstraction

### Security Checks

- Positive price validation
- Stale data protection
- Round completeness validation

### Oracle Risks

- Oracle downtime
- Feed depeg
- Delayed updates

---

# 10. Frontend Architecture

The frontend is implemented using:

- React
- Vite
- Wagmi
- Viem
- MetaMask

---

## Frontend Components

### Wallet Module

Handles:
- MetaMask connection
- Network detection
- Wrong-chain prompts

### Governance Panel

Handles:
- Proposal creation
- Voting
- Proposal state display

### Vault Panel

Handles:
- Approvals
- Deposits
- Redemptions

### Market Panel

Displays:
- Market count
- Factory state
- Market information

### Subgraph Panel

Queries indexed protocol data using GraphQL.

---

# 11. Subgraph Architecture

The Graph is used for event indexing.

## Indexed Entities

- Market
- Create2Market
- Proposal
- Vote
- VaultFee

---

## Subgraph Components

### schema.graphql

Defines indexed entities.

### mapping.ts

Processes protocol events.

### subgraph.yaml

Defines indexing sources and ABI mappings.

---

# 12. Sequence Diagrams

## Governance Flow

```text
User
 → Frontend
 → Governor.propose()
 → Voting starts
 → Users vote
 → Proposal succeeds
 → Timelock queue
 → Treasury execution
```

---

## Vault Flow

```text
User
 → approve()
 → FeeVault.deposit()
 → shares minted
 → redeem()
 → collateral returned
```

---

## Market Trading Flow

```text
User
 → swap()
 → CPMM calculation
 → reserves updated
 → outcome shares minted
```

---

# 13. Storage Layout Analysis

## PredictionMarketV1 Storage

```text
owner
collateralToken
outcomeToken
feeVault
yesReserve
noReserve
totalLiquidity
feeBps
```

---

## PredictionMarketV2 Storage

PredictionMarketV2 preserves V1 layout and only appends new variables.

### Collision Prevention Rules

- No variable reordering
- No variable deletion
- No inheritance modification
- New variables appended only

Therefore storage collisions are impossible under the current upgrade path.

---

# 14. Trust Assumptions

## Governance Assumptions

The DAO controls:
- Treasury transfers
- Protocol upgrades
- Governance parameters

If governance is compromised:
- Treasury assets may be stolen
- Malicious upgrades may be executed

---

## Timelock Assumptions

Timelock provides:
- Delayed execution
- User reaction time
- Governance transparency

---

## Oracle Assumptions

The system assumes:
- Chainlink remains operational
- Price feeds remain accurate
- Feed updates remain timely

---

## Frontend Assumptions

The frontend is untrusted.

Users may always interact directly with contracts using:
- Etherscan
- Cast
- Raw RPC calls

---

# 15. Design Patterns

## Factory Pattern

Used in MarketFactory.

Reason:
Centralized and deterministic market deployment.

---

## Proxy / UUPS

Used in PredictionMarketV1/V2.

Reason:
Safe upgradeability while preserving storage.

---

## Checks-Effects-Interactions

Used throughout treasury and market functions.

Reason:
Reduce reentrancy risk.

---

## Access Control

Used via Ownable and AccessControl.

Reason:
Restrict privileged operations.

---

## Timelock

Used in governance execution.

Reason:
Delay dangerous actions.

---

## Oracle Adapter

Used in OracleResolver.

Reason:
Abstract Chainlink dependency.

---

## Reentrancy Guard

Used in market and vault functions.

Reason:
Prevent recursive external call attacks.

---

## State Machine

Used in governance lifecycle.

Reason:
Enforce protocol flow correctness.

---

# 16. Architecture Decision Records

## ADR-001: UUPS Upgradeability

### Context

The protocol requires upgradeability.

### Options Considered

- Transparent Proxy
- Beacon Proxy
- UUPS

### Decision

UUPS selected.

### Consequences

Lower gas overhead but stricter authorization requirements.

---

## ADR-002: ERC-1155 Instead of ERC-20 Pairs

### Context

Markets require multiple share tokens.

### Decision

ERC-1155 selected.

### Consequences

Lower gas costs and simpler token management.

---

## ADR-003: OpenZeppelin Governor

### Context

Need for production-grade governance.

### Decision

Use OpenZeppelin Governor.

### Consequences

Battle-tested governance logic.

---

## ADR-004: Chainlink Oracle Usage

### Context

Need secure price resolution.

### Decision

Use Chainlink with staleness validation.

### Consequences

External dependency risk accepted.

---

# 17. Security Engineering

## Testing

Implemented:
- Unit tests
- Fuzz tests
- Invariant tests

---

## Static Analysis

CI pipeline includes:
- Slither
- forge fmt
- forge coverage

---

## CI/CD

GitHub Actions automatically performs:
- Contract builds
- Tests
- Coverage
- Frontend build
- Subgraph build

---

# 18. Conclusion

The protocol demonstrates a complete production-style decentralized application architecture with governance, upgradeability, indexing, frontend integration, oracle security, and CI/CD automation.

The design prioritizes:
- modularity
- upgrade safety
- governance security
- auditability
- testing coverage
- maintainability