# On-Chain Prediction Market

A binary-outcome prediction market built with Foundry, featuring:

- **CPMM AMM** (constant-product, x·y=k) with 0.3 % fee, slippage protection, and LP tokens
- **ERC-1155** outcome share tokens (YES / NO per market)
- **ERC-4626** fee vault for LPs
- **UUPS upgradeable** market contract (V1 → V2 documented upgrade path)
- **Factory** (CREATE + CREATE2) for deterministic market deployment
- **Chainlink oracle** resolution with staleness check and dispute window
- **DAO governance** — OpenZeppelin Governor + TimelockController (2-day delay) + ERC20Votes token
- **L2 deployment** — Arbitrum / Optimism / Base Sepolia with L1 vs L2 gas comparison
- **The Graph** subgraph with 4 entities and 5 GraphQL queries

## Quick Start

```shell
# Install Foundry: https://book.getfoundry.sh/getting-started/installation
forge build
forge test
forge snapshot          # gas benchmarks (Yul vs Solidity)
```

## Project Structure

```
src/
  tokens/   GovernanceToken (ERC20Votes+Permit), OutcomeShareToken (ERC-1155)
  vault/    FeeVault (ERC-4626)
  market/   PredictionMarketV1 (UUPS+CPMM), PredictionMarketV2, MarketFactory
  oracle/   OracleResolver (Chainlink + staleness)
  assembly/ YulMath (Yul vs Solidity benchmark)
  governance/ PredictionGovernor, Treasury
  mocks/    MockV3Aggregator, MockERC20
test/       Forge tests — unit, fuzz, invariant
script/     Deployment scripts (L1 + L2)
subgraph/   The Graph schema + mappings
```

## Dependencies

| Library | Version |
|---------|---------|
| forge-std | latest |
| openzeppelin-contracts | v5.x |
| openzeppelin-contracts-upgradeable | v5.x |
| chainlink-brownie-contracts | latest |

## Networks

Deployed on **Arbitrum Sepolia** (primary L2). See `script/` for deployment addresses and the L1 vs L2 gas comparison table.

---

# Frontend dApp (Section 3.4)

The project includes a fully functional React + Wagmi frontend integrated with the deployed smart contracts.

Implemented features:

### Wallet Integration

- MetaMask wallet connection
- Network detection
- Wrong-network warning with switch prompt
- Local Anvil support for development/testing

### Governance UI

- Read governance token balance
- Read voting power (`ERC20Votes`)
- Read delegate address
- Delegate voting power from UI
- Create governance proposals
- Read proposal state:
  - Pending
  - Active
  - Succeeded
  - Defeated
  - Queued
  - Executed
- Cast votes directly from the frontend

### Vault UI

- Read ERC-4626 vault shares
- Read total vault assets
- Approve collateral token
- Deposit assets into the vault
- Redeem vault shares

### Market UI

- Read MarketFactory state
- Read total markets
- Read implementation / collateral / vault addresses

### Error Handling

Frontend displays readable user-friendly messages for:

- rejected transactions
- wrong network
- unavailable subgraph endpoint
- failed transactions
- insufficient balances

No raw RPC errors or silent failures are shown to the user.

---

# Subgraph & Indexing

A full The Graph subgraph implementation is included.

Implemented files:

```text
subgraph/
  schema.graphql
  subgraph.yaml
  src/mapping.ts
```

Indexed entities:

- `Market`
- `Create2Market`
- `Proposal`
- `Vote`
- `VaultFee`

Subgraph supports indexing of:

- market deployments
- governance proposals
- governance votes
- vault fee events

## GraphQL Queries

### Markets

```graphql
{
  markets(first: 10) {
    id
    marketAddress
    index
    createdAtTimestamp
  }
}
```

### CREATE2 Markets

```graphql
{
  create2Markets(first: 10) {
    id
    marketAddress
    salt
    index
  }
}
```

### Proposals

```graphql
{
  proposals(first: 10) {
    id
    proposer
    description
    createdAtTimestamp
  }
}
```

### Votes

```graphql
{
  votes(first: 10) {
    id
    proposalId
    voter
    support
    weight
  }
}
```

### Vault Fees

```graphql
{
  vaultFees(first: 10) {
    id
    from
    assets
    createdAtTimestamp
  }
}
```

---

# CI / DevOps (Section 3.5)

The repository includes a GitHub Actions CI pipeline:

```text
.github/workflows/ci.yml
```

Pipeline checks include:

- `forge build`
- `forge test`
- `forge coverage`
- `forge fmt --check`
- `slither`
- frontend build verification
- subgraph codegen/build verification

---

# Local Demo Flow

1. Start local Anvil blockchain
2. Deploy contracts using Foundry scripts
3. Connect MetaMask
4. Delegate voting power
5. Create proposal
6. Vote on proposal
7. Deposit into ERC-4626 vault
8. Redeem vault shares
9. Read indexed subgraph data
10. Interact with MarketFactory state

---

# Frontend Stack

- React
- Vite
- Wagmi
- Viem
- MetaMask

# Backend / Indexing Stack

- The Graph
- GraphQL
- Docker
- IPFS
- graph-node