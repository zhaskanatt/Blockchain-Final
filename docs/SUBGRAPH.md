# Subgraph Documentation

## Overview

The protocol integrates The Graph for event indexing and historical data querying.

The subgraph indexes governance activity, market deployment activity, and vault-related events to provide efficient frontend querying and analytics.

The Graph integration allows the frontend to avoid expensive on-chain historical queries while improving responsiveness and scalability.

---

# Subgraph Architecture

The subgraph consists of:

```text
subgraph/
 ├── schema.graphql
 ├── subgraph.yaml
 ├── src/
 │    └── mapping.ts
 ├── generated/
 └── package.json
```

---

# Indexed Contracts

The subgraph indexes events emitted from:

| Contract | Purpose |
|---|---|
| MarketFactory | Market deployment tracking |
| PredictionGovernor | Governance proposals and votes |
| FeeVault | Vault fee indexing |

---

# Indexed Entities

## Market

Tracks prediction markets deployed through CREATE.

### Fields

| Field | Description |
|---|---|
| id | Market address |
| creator | Market creator |
| timestamp | Deployment timestamp |
| txHash | Deployment transaction |

---

## Create2Market

Tracks deterministic CREATE2 market deployments.

### Fields

| Field | Description |
|---|---|
| id | CREATE2 market address |
| salt | CREATE2 deployment salt |
| creator | Market creator |
| timestamp | Deployment timestamp |

---

## Proposal

Tracks governance proposals.

### Fields

| Field | Description |
|---|---|
| id | Proposal ID |
| proposer | Proposal creator |
| description | Proposal description |
| startBlock | Voting start |
| endBlock | Voting end |

---

## Vote

Tracks governance votes.

### Fields

| Field | Description |
|---|---|
| id | Vote ID |
| voter | Voter address |
| proposalId | Proposal reference |
| support | Vote direction |
| weight | Voting power |

---

## VaultFee

Tracks vault fee deposits.

### Fields

| Field | Description |
|---|---|
| id | Fee event ID |
| amount | Fee amount |
| timestamp | Deposit timestamp |

---

# schema.graphql

The schema defines all indexed entities.

Example:

```graphql
type Proposal @entity {
  id: ID!
  proposer: Bytes!
  description: String!
  startBlock: BigInt!
  endBlock: BigInt!
}
```

---

# subgraph.yaml

The manifest defines:

- indexed contracts
- ABI files
- event handlers
- mapping files
- network configuration

Example structure:

```yaml
dataSources:
  - kind: ethereum
    name: MarketFactory
    mapping:
      eventHandlers:
        - event: MarketCreated(...)
```

---

# mapping.ts

The mapping layer transforms emitted events into indexed entities.

Responsibilities:

- event parsing
- entity creation
- entity updates
- relationship linking

---

# Event Handlers

## MarketFactory Events

### Indexed Events

- MarketCreated
- MarketCreatedWithSalt

### Actions

- create Market entity
- create Create2Market entity

---

## Governance Events

### Indexed Events

- ProposalCreated
- VoteCast

### Actions

- create Proposal entity
- create Vote entity

---

## FeeVault Events

### Indexed Events

- FeesDeposited

### Actions

- create VaultFee entity

---

# Subgraph Workflow

## Generate Types

```bash
npx graph codegen
```

This generates:

- TypeScript entity bindings
- contract bindings
- event types

---

## Build Subgraph

```bash
npx graph build
```

This validates:

- schema correctness
- mapping correctness
- ABI compatibility

---

# Local Graph Node Setup

The project supports local Graph Node deployment using Docker.

---

## Start Services

```bash
docker compose up -d
```

Services started:

- graph-node
- postgres
- ipfs

---

# Create Subgraph

```bash
graph create prediction-market \
  --node http://127.0.0.1:8020
```

---

# Deploy Subgraph

```bash
graph deploy prediction-market \
  --ipfs http://127.0.0.1:5001 \
  --node http://127.0.0.1:8020
```

---

# GraphQL Endpoint

Local endpoint:

```text
http://127.0.0.1:8000/subgraphs/name/prediction-market
```

---

# Example Queries

## Query Markets

```graphql
{
  markets(first: 5) {
    id
    creator
    timestamp
  }
}
```

---

## Query CREATE2 Markets

```graphql
{
  create2Markets(first: 5) {
    id
    salt
    creator
  }
}
```

---

## Query Proposals

```graphql
{
  proposals(first: 5) {
    id
    proposer
    description
  }
}
```

---

## Query Votes

```graphql
{
  votes(first: 5) {
    voter
    proposalId
    support
    weight
  }
}
```

---

## Query Vault Fees

```graphql
{
  vaultFees(first: 5) {
    amount
    timestamp
  }
}
```

---

# Frontend Integration

The frontend uses subgraph queries for:

- proposal history
- vote history
- market indexing
- vault analytics

Benefits compared to direct RPC queries:

- lower latency
- historical indexing
- pagination support
- filtering support

---

# Performance Considerations

The subgraph reduces frontend load by:

- avoiding historical RPC scans
- indexing events once
- caching indexed data

This improves scalability and frontend responsiveness.

---

# Error Handling

## Common Errors

### Missing ABI Artifacts

Fix:

```bash
forge build
```

before:

```bash
npx graph codegen
```

---

### Graph Node Connection Errors

Restart Docker services:

```bash
docker compose down
docker compose up -d
```

---

### Schema Validation Errors

Run:

```bash
npx graph build
```

to validate schema and mappings.

---

# CI/CD Integration

GitHub Actions automatically validates:

- graph codegen
- graph build
- ABI compatibility

This prevents broken indexing deployments.

---

# Security Considerations

The subgraph is read-only infrastructure.

Important considerations:

- indexed data is not consensus-critical
- frontend must not trust subgraph data blindly
- on-chain contract state remains the source of truth

---

# Future Improvements

Potential future extensions:

- advanced analytics
- historical charts
- liquidity tracking
- user portfolio indexing
- governance statistics
- market volume analytics

---

# Conclusion

The Graph integration provides scalable indexed infrastructure for the prediction market protocol.

The subgraph enables:

- efficient frontend querying
- historical analytics
- governance indexing
- market indexing
- improved user experience

while maintaining compatibility with production-style Web3 indexing infrastructure.