# ArcLend

> Aave-inspired DeFi lending & borrowing protocol on [Arc Testnet](https://arc.network) — the stablecoin-native EVM L1 by Circle.

![Arc Testnet](https://img.shields.io/badge/Arc%20Testnet-Chain%205042002-00BFFF?style=flat-square)
![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?style=flat-square&logo=solidity)
![React](https://img.shields.io/badge/React-19-61DAFB?style=flat-square&logo=react)
![Tests](https://img.shields.io/badge/Tests-86%20passing-brightgreen?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## Overview

ArcLend is a full-stack DeFi lending and borrowing protocol built natively for Arc Testnet — Circle's EVM-compatible L1 that uses USDC as the native gas token. It is modelled after Aave v2 with a jump-rate interest model, ray-math scaled balances, and a composable integration layer.

### What users can do

| Action | Description |
|---|---|
| **Supply** | Deposit USDC or EURC to earn yield from borrowers |
| **Borrow** | Take out loans against your supplied collateral (up to the asset LTV) |
| **Repay / Withdraw** | Reduce debt or reclaim collateral at any time |
| **Liquidate** | Repay debt of undercollateralised positions (health factor < 1.0) and earn a bonus |
| **Swap** | Swap USDC ↔ EURC instantly via Circle's Stablecoin Service (LiFi / Fly DEX) |
| **Bridge** | Bring USDC from Ethereum Sepolia to Arc Testnet via Circle's CCTP |
| **Vault** | Deposit into ERC-4626 vaults (`alvUSDC` / `alvEURC`) for transferable, composable yield shares |
| **Gasless supply** | Sign an EIP-3009 authorization off-chain and let the relayer pay the gas |
| **Faucet** | Mint free testnet tokens (one-click per asset) |
| **Admin** | Configure protocol fee, fee collector, and withdraw reserves (owner only) |

---

## Live Contracts — Arc Testnet (Chain ID 5042002)

### Core Protocol

| Contract | Address |
|---|---|
| LendingPool | `0x7e6Ab8b26223e3f622E25f44c1840e6BD85e3de2` |
| MockPriceOracle | `0xc0Fe330c98Da23f5180d8Ee8B84b89422493B0Ac` |

### Composable Integration Layer *(additive — no core redeploy)*

| Contract | Address |
|---|---|
| ArcLendGaslessRouter | `0xFE338289BA0f113933853759baD76B251932341a` |
| alvUSDC Vault (ERC-4626) | `0x363C4eE3CfD814D3CC3bc72aCe4259453cF651EB` |
| alvEURC Vault (ERC-4626) | `0xf9A7CD2c92CB6957ECeFffE2881c5Bd163a2CAeD` |

### Real Arc Testnet Tokens (by Circle)

| Token | Symbol | Address |
|---|---|---|
| USD Coin | USDC | `0x3600000000000000000000000000000000000000` |
| Euro Coin | EURC | `0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a` |
| US Yield Coin | USYC | `0xe918...b86C` *(stub — not yet deployed by Circle)* |

### Circle Stablecoin Service (Arc FX Swap)

| Contract | Address |
|---|---|
| Circle EVM Testnet Adapter | `0xBBD70b01a1CAbc96d5b7b129Ae1AAabdf50dd40b` |

Block explorer: [testnet.arcscan.app](https://testnet.arcscan.app)

---

## Arc Testnet Details

| Parameter | Value |
|---|---|
| Network Name | Arc Testnet |
| Chain ID | 5042002 |
| RPC URL | https://rpc.testnet.arc.network |
| Block Explorer | https://testnet.arcscan.app |
| Native Gas Token | USDC |
| Faucet | https://faucet.circle.com |

> Connect MetaMask manually or click **Switch Network** in the dApp — it prompts MetaMask to add the network automatically.

---

## Pages

| Page | Path | Description |
|---|---|---|
| Dashboard | `/` | Protocol TVL, total supplied/borrowed, user portfolio summary |
| Markets | `/markets` | Per-asset supply APY, borrow APY, utilization, LTV — supply/borrow actions |
| Portfolio | `/portfolio` | User positions, health factor, earned interest, wallet balances |
| Vaults | `/vaults` | ERC-4626 vaults — deposit/withdraw, share price, gasless deposit via EIP-3009 |
| Swap | `/swap` | USDC ↔ EURC instant swap via Circle's Stablecoin Service |
| Bridge | `/bridge` | USDC cross-chain bridge from Ethereum Sepolia → Arc Testnet via CCTP |
| Liquidations | `/liquidations` | Live liquidatable positions, one-click liquidate with bonus |
| Faucet | `/faucet` | One-click testnet token minting for USDC, EURC, mARC |
| Admin | `/admin` | Owner-only: fee config, fee collector address, reserve collection |

---

## Arc FX Swap — Circle Stablecoin Service Integration

The Swap page integrates Circle's Stablecoin Kits API to enable USDC ↔ EURC swaps on Arc Testnet through an on-chain DEX (LiFi / Fly).

### Architecture

```
User wallet (MetaMask)
      │
      ▼
React frontend  ──GET /api/swap/quote──►  Express proxy
                ──POST /api/swap/execute─►  (holds CIRCLE_KIT_KEY server-side)
                                                │
                                                ▼
                                   api.circle.com/v1/stablecoinKits
                                   (quote + signed swap instructions)
                                                │
                                                ▼
                              Circle EVM Adapter  0xBBD70b...
                              execute(params, tokenInputs, sig)
```

### On-chain execution flow

1. **GET `/api/swap/quote`** — returns estimated output and minimum amount
2. **POST `/api/swap/execute`** — Circle returns `executionParams` (routing instructions + deadline + execId) and a Circle-signed authorization
3. **`USDC.approve(adapterContract, amount)`** — grant spending allowance if insufficient
4. **`adapterContract.execute(executeParams, tokenInputs, signature)`** — atomic on-chain swap

### Key implementation notes

- The API server proxy adds `User-Agent: swap-kit/1.0 (node/24)` — Circle gates Arc Testnet routing on SDK identification; without it, the API returns "No route available" regardless of key or parameters
- Both `fromAddress` and `toAddress` are required query parameters on the quote endpoint
- USDC does not support EIP-2612 permit, so `PermitType.NONE` (pre-approval) is used — no on-chain permit signing required
- Kit key format must match `KIT_KEY:xxx:yyy` (validated against Circle SDK regex)
- The `CIRCLE_KIT_KEY` secret is stored server-side only and never sent to the browser

**Confirmed working transaction:** [0x5f6ac0da...](https://testnet.arcscan.app/tx/0x5f6ac0da044878b2461bfb6fa3ff8ff523dabfddd9c746a11f98c0b57a1633f2)

---

## Bridge — Circle CCTP

The Bridge page lets users transfer USDC from **Ethereum Sepolia → Arc Testnet** using Circle's Cross-Chain Transfer Protocol.

- Reads the user's Sepolia USDC balance via a static `JsonRpcProvider` call (independent of which network MetaMask is currently connected to)
- Initiates a burn on Sepolia and mints on Arc Testnet via Circle's attestation service
- Supported direction: Sepolia → Arc (testnet)

---

## Composable Integration Layer

Two additive contracts deploy on top of the live `LendingPool` — no core redeploy required.

### ArcLendVault (ERC-4626)

- Wraps a single supply market (`alvUSDC` or `alvEURC`)
- Deposits forward into the live `LendingPool` and issues transferable yield shares
- `totalAssets()` reads `getUserReserveData(vault, asset)` — share value auto-accrues with pool interest
- Fee-aware `preview*` functions ensure the pool's 30 bps fee never silently dilutes share holders
- Shares are composable in any ERC-4626-aware protocol

### ArcLendGaslessRouter (EIP-3009)

- Accepts an off-chain `ReceiveWithAuthorization` signature from the user
- A relayer submits it — user pays **zero gas** (ideal since USDC is the gas token on Arc)
- Router pulls USDC/EURC and deposits into an `ArcLendVault`, minting shares to the user
- Backend relayer validates + preflights the authorization before spending gas

---

## Subgraph

A [Graph Protocol](https://thegraph.com) subgraph indexes the `LendingPool` for fast historical queries, driving the Liquidations page and per-user activity feeds without scanning logs in the browser.

Schema: `Protocol` / `Market` / `User` / `UserPosition` + immutable event rows for Supply / Withdraw / Borrow / Repay / Liquidate.

See [`subgraph/README.md`](subgraph/README.md) for self-hosting instructions. Arc isn't on The Graph's hosted service yet — recommended path is [Goldsky](https://goldsky.com) or a self-hosted Graph Node.

---

## Protocol Economics

### Interest Rate Model (Jump Rate)

Each market uses a two-slope model with a kink at optimal utilization:

```
Utilization ≤ Optimal:  BorrowRate = BaseRate + Slope₁ × Utilization
Utilization > Optimal:  BorrowRate = BaseRate + Slope₁ × Optimal + Slope₂ × (Util − Optimal)
```

| Parameter | USDC / EURC | mARC |
|---|---|---|
| Base Rate | 2% | 3% |
| Slope₁ | 8% | 10% |
| Optimal Utilization | 80% | 70% |
| Slope₂ (excess) | 100% | 150% |

Supply APY = BorrowRate × Utilization × (1 − ReserveFactor)

### Supported Assets

| Asset | LTV | Liq. Threshold | Reserve Factor |
|---|---|---|---|
| USDC | 85% | 90% | 10% |
| EURC | 85% | 90% | 10% |
| mARC | 60% | 65% | 20% |

### Health Factor & Liquidation

```
HealthFactor = Σ(CollateralUSD × LiquidationThreshold) / TotalDebtUSD
```

- Health factor < 1.0 → position is liquidatable
- Liquidators may repay up to **50%** of debt per call and receive collateral + a liquidation bonus

### Protocol Fees

A configurable fee (default **0.30%**, capped at **2%**) is deducted on supply / borrow / withdraw. Fees accumulate in `protocolReserves` per market and are collectible by the contract owner via the Admin page.

---

## Getting Started

### Prerequisites

- [Node.js 20+](https://nodejs.org)
- [pnpm 9+](https://pnpm.io) — `npm install -g pnpm`
- [MetaMask](https://metamask.io) browser extension
- Testnet USDC for gas from [faucet.circle.com](https://faucet.circle.com)

### Run locally

```bash
git clone https://github.com/osr21/arclend.git
cd arclend
pnpm install

# Start the React dApp  (http://localhost:24455)
pnpm --filter @workspace/arc-lend run dev

# Start the API server  (http://localhost:5000)
pnpm --filter @workspace/api-server run dev
```

Connect MetaMask to Arc Testnet, then use the Faucet page to claim testnet tokens.

### Environment variables

```bash
# Override deployed contract addresses (optional — real Arc tokens used by default)
VITE_LENDING_POOL_ADDRESS=0x...
VITE_ORACLE_ADDRESS=0x...
VITE_USDC_ADDRESS=0x...
VITE_EURC_ADDRESS=0x...

# Circle Stablecoin Kits — required for the Arc FX Swap page
CIRCLE_KIT_KEY=KIT_KEY:xxx:yyy
```

---

## Smart Contracts

### Compile & test

```bash
cd contracts
npm install
npm run compile       # compile all contracts
npm run test          # run Hardhat test suite (86 tests, ~13 s)
```

### Deploy to Arc Testnet

```bash
export PRIVATE_KEY=0x...

cd contracts
npm run deploy:testnet

# Deploy the composable integration layer (additive — no core redeploy)
npx hardhat run scripts/deploy-integrations.js --network arcTestnet
```

Copy printed addresses into `artifacts/arc-lend/src/lib/constants.ts` or set as `VITE_` env vars.

### Verify on Arcscan

```bash
npm run verify:testnet
```

> **Note:** `evmVersion` must be `cancun` in `hardhat.config.js`. OpenZeppelin 5.1+ uses the `mcopy` opcode (pulled in by `EIP712`/`ECDSA`) which requires Cancun. Arc Testnet supports it.

---

## Project Structure

```
arclend/
├── artifacts/
│   ├── arc-lend/                   # React + Vite frontend dApp
│   │   └── src/
│   │       ├── abi/                # Contract ABIs
│   │       ├── components/         # UI components (ActionModal, WalletMenu…)
│   │       ├── hooks/              # useWallet, useMarkets, useUserData, useVaults
│   │       ├── lib/
│   │       │   ├── arcFxSwap.ts    # Circle Stablecoin Kits swap client
│   │       │   ├── constants.ts    # Contract addresses
│   │       │   └── contracts.ts    # ethers.js contract helpers
│   │       └── pages/
│   │           ├── Dashboard.tsx
│   │           ├── Markets.tsx
│   │           ├── Portfolio.tsx
│   │           ├── Vaults.tsx
│   │           ├── Swap.tsx        # Arc FX Swap (Circle Stablecoin Kits)
│   │           ├── Bridge.tsx      # CCTP bridge (Sepolia → Arc)
│   │           ├── Liquidations.tsx
│   │           ├── Faucet.tsx
│   │           └── Admin.tsx
│   └── api-server/                 # Express 5 API server
│       └── src/routes/
│           ├── swap.ts             # Circle Stablecoin Kits proxy
│           └── gasless.ts          # EIP-3009 gasless supply relayer
├── contracts/
│   └── src/
│       ├── LendingPool.sol             # Core protocol
│       ├── MockERC20.sol               # Mintable test token with faucet
│       ├── MockPriceOracle.sol         # Admin-set USD price feed
│       ├── ArcLendVault.sol            # ERC-4626 composable yield shares
│       ├── ArcLendGaslessRouter.sol    # EIP-3009 gasless supply relayer
│       ├── interfaces/                 # ILendingPool, IPriceOracle, IEIP3009
│       └── oracles/
│           └── ChainlinkAdapter.sol    # Ready to wire when Chainlink supports Arc
├── subgraph/                       # Graph Protocol subgraph (LendingPool indexer)
└── lib/                            # Shared TypeScript libraries
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | React 19, Vite, Tailwind CSS v4, shadcn/ui, Framer Motion |
| Web3 | ethers.js v6 (no wagmi — direct ethers) |
| Routing | wouter |
| Contracts | Solidity 0.8.24, Hardhat, OpenZeppelin 5.1 |
| Monorepo | pnpm workspaces, TypeScript 5.9 |
| API server | Express 5, PostgreSQL, Drizzle ORM |
| Swap | Circle Stablecoin Kits via server-side proxy |
| Bridge | Circle CCTP |
| Indexing | Graph Protocol subgraph |

---

## Security Notes

- All state-changing functions use OpenZeppelin `ReentrancyGuard`
- Token transfers use `SafeERC20`
- Owner functions protected by `Ownable`
- Protocol fee hard-capped at **2%** on-chain (`MAX_PROTOCOL_FEE = 200`)
- Health factor checked before every borrow and withdrawal
- Supply/borrow caps enforced per market
- Global and per-market pause flags
- USYC detected as stub at runtime — supply/borrow disabled until Circle ships the production contract at the same address
- Oracle: `MockPriceOracle` with admin-set prices (testnet only). `ChainlinkAdapter.sol` is ready — swap in with `LendingPool.setOracle(adapter)`, no protocol redeploy required
- `CIRCLE_KIT_KEY` stored as a server-side secret only, never exposed to the browser

**Known accepted risks (testnet):** Owner key is a single EOA with no timelock. `_updateAllMarkets()` is O(N) over listed markets — keep the list bounded.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

---

## License

MIT — see [LICENSE](LICENSE)
