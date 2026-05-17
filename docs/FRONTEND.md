# Frontend Documentation

## Overview

The frontend is a React-based decentralized application (dApp) that provides users with an interface for interacting with the On-Chain Prediction Market DAO protocol.

The frontend supports:

- wallet connection
- governance voting
- treasury proposals
- vault interactions
- prediction market interaction
- subgraph querying
- network detection
- transaction error handling

The frontend was designed to provide a production-style Web3 user experience using modern Ethereum tooling.

---

# Technology Stack

## Core Technologies

| Technology | Purpose |
|---|---|
| React | UI framework |
| Vite | Frontend bundler |
| Wagmi | Ethereum React hooks |
| Viem | Ethereum RPC interaction |
| MetaMask | Wallet provider |
| The Graph | Indexed data querying |

---

# Frontend Architecture

The frontend is divided into multiple isolated modules.

```text
App.jsx
 ├── Wallet Connection
 ├── TokenInfo
 ├── GovernancePanel
 ├── CreateProposalButton
 ├── VaultPanel
 ├── MarketPanel
 └── SubgraphPanel
```

---

# Wallet Integration

## MetaMask Connection

The frontend uses Wagmi connectors for wallet interaction.

### Features

- wallet connection
- automatic reconnection
- account detection
- chain detection

### Supported Wallets

- MetaMask

The architecture allows future WalletConnect integration.

---

# Network Detection

The frontend automatically detects incorrect chains.

## Wrong Network Handling

If the user connects to an unsupported chain:

- warning messages are displayed
- transactions are disabled
- the user is prompted to switch networks

### Supported Networks

- Local Anvil
- Arbitrum Sepolia
- Optimism Sepolia
- Base Sepolia

---

# Token Information Module

## TokenInfo Component

Displays:

- governance token balance
- voting power
- delegate address

### Features

- automatic wallet refresh
- formatted balances
- delegated voting status

---

# Governance Module

## GovernancePanel

The GovernancePanel provides DAO interaction functionality.

### Features

- proposal listing
- proposal state display
- voting
- proposal execution tracking

### Proposal States

Displayed states:

- Pending
- Active
- Succeeded
- Defeated
- Queued
- Executed

---

## CreateProposalButton

Allows users to create governance proposals.

### Example Proposal Flow

```text
User
 → Create Proposal
 → Governor.propose()
 → Proposal enters Pending state
```

---

# Vault Module

## VaultPanel

Provides ERC4626 vault interactions.

### Features

- token approval
- deposits
- withdrawals
- share balance display

### Deposit Flow

```text
User
 → approve()
 → deposit()
 → shares minted
```

### Redemption Flow

```text
User
 → redeem()
 → collateral returned
```

---

# Market Module

## MarketPanel

Displays protocol market information.

### Features

- deployed market count
- factory state
- market deployment information
- CREATE2 deployment tracking

---

# Subgraph Integration

## SubgraphPanel

The frontend integrates The Graph for indexed protocol data.

### Indexed Data

Queried entities include:

- Market
- Create2Market
- Proposal
- Vote
- VaultFee

### Benefits

Using indexed data improves:

- frontend performance
- historical query support
- governance analytics
- event filtering

---

# Transaction Handling

## State-Changing Transactions

The frontend supports multiple state-changing operations:

| Action | Contract |
|---|---|
| Vote | PredictionGovernor |
| Deposit | FeeVault |
| Redeem | FeeVault |
| Delegate | GovernanceToken |
| Propose | PredictionGovernor |

---

# Error Handling

The frontend implements explicit transaction error handling.

## Supported Error Cases

### User Rejection

If the user rejects a MetaMask transaction:

```text
Transaction rejected by user.
```

---

### Wrong Network

If the user connects to the wrong chain:

```text
Wrong network detected. Please switch chain.
```

---

### Insufficient Balance

If the user lacks sufficient funds:

```text
Insufficient token balance.
```

---

### Contract Reverts

Readable fallback errors are displayed instead of raw RPC messages whenever possible.

---

# Frontend State Management

Frontend state is managed using React hooks and Wagmi query caching.

### Advantages

- automatic RPC caching
- efficient rerendering
- wallet synchronization
- reactive updates

---

# Frontend Security Considerations

## Untrusted Frontend

The frontend is not trusted.

Users may always interact directly with contracts using:

- Etherscan
- cast
- raw RPC calls

---

## Client-Side Validation

The frontend validates:

- wallet connection
- chain ID
- required balances
- input formatting

before sending transactions.

---

# Contract Address Configuration

Contract addresses are stored inside:

```text
frontend/src/config/contracts.js
```

---

# Environment Variables

Frontend configuration uses:

```env
VITE_RPC_URL=
VITE_CHAIN_ID=
VITE_SUBGRAPH_URL=
```

---

# Development Setup

## Install Dependencies

```bash
cd frontend
npm install
```

---

## Start Development Server

```bash
npm run dev
```

Frontend URL:

```text
http://localhost:5173
```

---

# Production Build

## Build Frontend

```bash
npm run build
```

---

# CI/CD Integration

GitHub Actions automatically validates the frontend build.

## Automated Checks

- dependency installation
- frontend compilation
- Vite production build

---

# UX Design Goals

The frontend prioritizes:

- readability
- minimalism
- governance transparency
- transaction clarity
- Web3 usability

The UI intentionally avoids unnecessary complexity while exposing important protocol information.

---

# Future Improvements

Potential future enhancements:

- WalletConnect support
- mobile optimization
- analytics dashboard
- historical charts
- advanced governance filtering
- optimistic UI updates

---

# Conclusion

The frontend provides a complete production-style Web3 interface for interacting with the prediction market protocol.

The application successfully integrates:

- governance
- vault accounting
- prediction market infrastructure
- indexed GraphQL data
- MetaMask connectivity
- secure transaction handling

while maintaining a modular and maintainable React architecture.