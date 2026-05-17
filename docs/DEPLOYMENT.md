# Deployment Guide

## Overview

The protocol supports deployment on:

- Local Anvil network
- Arbitrum Sepolia
- Optimism Sepolia
- Base Sepolia

The deployment pipeline uses Foundry scripts and environment variables.

---

# Requirements

## Required Tools

- Foundry
- Node.js
- Docker
- Git

---

## Environment Variables

Create a `.env` file:

```env
PRIVATE_KEY=YOUR_PRIVATE_KEY
RPC_URL=YOUR_RPC_URL
ETHERSCAN_API_KEY=YOUR_API_KEY
PRICE_FEED=YOUR_CHAINLINK_FEED
```

---

# Local Deployment

## Start Local Node

```bash
anvil
```

Default RPC URL:

```text
http://127.0.0.1:8545
```

---

## Deploy Contracts

```bash
forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

---

## Deploy Frontend

```bash
cd frontend
npm install
npm run dev
```

Frontend URL:

```text
http://localhost:5173
```

---

# L2 Deployment

## Arbitrum Sepolia

### Deploy

```bash
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

---

## Optimism Sepolia

### Deploy

```bash
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

---

## Base Sepolia

### Deploy

```bash
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

---

# Deployment Architecture

## Deployment Order

```text
GovernanceToken
    ↓
TimelockController
    ↓
PredictionGovernor
    ↓
Treasury
    ↓
OutcomeShareToken
    ↓
FeeVault
    ↓
PredictionMarketV1
    ↓
MarketFactory
    ↓
OracleResolver
```

---

# Proxy Deployment

Prediction markets use the UUPS proxy pattern.

## Upgrade Flow

```text
PredictionMarketV1
        ↓
ERC1967Proxy
        ↓
PredictionMarketV2
```

---

# Post-Deployment Setup

## Grant Roles

```text
MINTER_ROLE → MarketFactory
TREASURY_OWNER → TimelockController
```

---

## Delegate Governance Tokens

Users must delegate tokens before voting:

```solidity
delegate(address delegatee)
```

---

# Frontend Configuration

## Contract Addresses

Frontend addresses are configured inside:

```text
frontend/src/config/contracts.js
```

---

## Required Frontend Variables

```env
VITE_RPC_URL=
VITE_CHAIN_ID=
VITE_SUBGRAPH_URL=
```

---

# Subgraph Deployment

## Start Docker Services

```bash
docker compose up -d
```

---

## Generate Types

```bash
cd subgraph

npx graph codegen
npx graph build
```

---

## Create Subgraph

```bash
graph create prediction-market \
  --node http://127.0.0.1:8020
```

---

## Deploy Subgraph

```bash
graph deploy prediction-market \
  --ipfs http://127.0.0.1:5001 \
  --node http://127.0.0.1:8020
```

---

# GraphQL Endpoint

```text
http://127.0.0.1:8000/subgraphs/name/prediction-market
```

---

# Gas Comparison

## L1 vs L2 Deployment

| Network | Estimated Deployment Cost |
|---|---|
| Ethereum Mainnet | Highest |
| Arbitrum Sepolia | Low |
| Optimism Sepolia | Low |
| Base Sepolia | Low |

L2 deployment significantly reduces deployment and interaction costs compared to Ethereum mainnet.

---

# Verification

## Verify Contracts

```bash
forge verify-contract \
  CONTRACT_ADDRESS \
  CONTRACT_NAME \
  --chain arbitrum-sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

---

# CI/CD Deployment Pipeline

GitHub Actions automatically validates:

- forge build
- forge test
- forge coverage
- forge fmt
- frontend build
- subgraph build
- slither analysis

---

# Troubleshooting

## Common Issues

### Wrong Network

Switch MetaMask to the correct chain.

---

### Governance Voting Power = 0

Delegate governance tokens before voting.

---

### Subgraph Not Syncing

Restart Docker services:

```bash
docker compose down
docker compose up -d
```

---

### Missing ABI Errors

Run:

```bash
forge build
```

before subgraph generation.

---

# Conclusion

The deployment pipeline supports both local development and production-style L2 deployments using Foundry, Docker, and The Graph infrastructure.