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
