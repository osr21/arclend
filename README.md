# ArcLend

  > Aave-inspired DeFi lending & borrowing protocol on [Arc Testnet](https://arc.network) — the stablecoin-native EVM L1 by Circle.

  ![Arc Testnet](https://img.shields.io/badge/Arc%20Testnet-Chain%205042002-00BFFF?style=flat-square)
  ![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?style=flat-square&logo=solidity)
  ![React](https://img.shields.io/badge/React-19-61DAFB?style=flat-square&logo=react)
  ![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

  ---

  ## Overview

  ArcLend lets users:

  - **Supply** USDC, EURC, or mARC to earn yield from borrowers
  - **Borrow** against supplied collateral (up to the asset's LTV ratio)
  - **Repay** debt and **withdraw** collateral at any time
  - **Liquidate** undercollateralised positions (health factor < 1.0)
  - **Claim** free testnet tokens from the built-in faucet
  - **Collect protocol fees** (owner only) via the Admin dashboard

  ---

  ## Live Contracts — Arc Testnet (Chain ID 5042002)

  | Contract | Address |
  |---|---|
  | LendingPool | `0x7e6Ab8b26223e3f622E25f44c1840e6BD85e3de2` |
  | MockPriceOracle | `0xc0Fe330c98Da23f5180d8Ee8B84b89422493B0Ac` |
  | Mock USDC | `0xd36a5F89D1b67B6a925cbb06225eF5b17e17b855` |
  | Mock EURC | `0xC38B3acb381E9B8Dd90266022Cca0AB9afc935c5` |
  | Mock mARC | `0x844F39119e5f6CB8b727E538634a05F098cF842B` |

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

  Add this network to MetaMask manually or click **Switch Network** in the dApp — it will prompt MetaMask to add it automatically.

  ---

  ## Supported Assets

  | Asset | Symbol | Decimals | LTV | Liq. Threshold | Reserve Factor |
  |---|---|---|---|---|---|
  | USD Coin | USDC | 6 | 85% | 90% | 10% |
  | Euro Coin | EURC | 6 | 85% | 90% | 10% |
  | Mock ARC | mARC | 18 | 60% | 65% | 20% |

  ---

  ## Protocol Economics

  ### Interest Rate Model (Jump Rate)
  Each market uses a two-slope interest rate model with a kink at optimal utilization:

  ```
  Utilization ≤ Optimal:  BorrowRate = BaseRate + Slope × Utilization
  Utilization > Optimal:  BorrowRate = BaseRate + Slope × Optimal + ExcessSlope × (Util - Optimal)
  ```

  | Parameter | USDC / EURC | mARC |
  |---|---|---|
  | Base Rate | 2% | 3% |
  | Slope | 8% | 10% |
  | Optimal Utilization | 80% | 70% |
  | Excess Slope | 100% | 150% |

  Supply APY = BorrowRate × Utilization × (1 − ReserveFactor)

  ### Protocol Fees
  A configurable protocol fee (default **0.30%**, capped at **2%**) is deducted from every supply, borrow, and withdraw. Fees accumulate in `protocolReserves` per market and can be collected by the contract owner at any time via the Admin page.

  ### Health Factor & Liquidation
  ```
  HealthFactor = Σ(CollateralUSD × LiquidationThreshold) / TotalDebtUSD
  ```
  - HealthFactor < 1.0 → position is liquidatable
  - Liquidators may repay up to 50% of debt per call and receive collateral + bonus

  ---

  ## Getting Started

  ### Prerequisites
  - [Node.js 20+](https://nodejs.org)
  - [pnpm](https://pnpm.io) (`npm install -g pnpm`)
  - [MetaMask](https://metamask.io) browser extension
  - Testnet USDC for gas from [faucet.circle.com](https://faucet.circle.com)

  ### Run Locally

  ```bash
  # Clone
  git clone https://github.com/osr21/arclend.git
  cd arclend

  # Install all workspace dependencies
  pnpm install

  # Start the frontend dApp (http://localhost:24455)
  pnpm --filter @workspace/arc-lend run dev

  # (Optional) Start the API server
  pnpm --filter @workspace/api-server run dev
  ```

  Open your browser, connect MetaMask to Arc Testnet, and use the Faucet page to claim testnet tokens.

  ---

  ## Smart Contracts

  ### Compile

  ```bash
  cd contracts
  npm install
  npm run compile
  ```

  ### Deploy to Arc Testnet

  ```bash
  # Set your deployer private key
  export PRIVATE_KEY=0x...

  cd contracts
  npm run deploy:testnet
  ```

  After deployment, copy the printed addresses and set them as environment variables in the frontend:

  ```bash
  VITE_LENDING_POOL_ADDRESS=0x...
  VITE_ORACLE_ADDRESS=0x...
  VITE_USDC_ADDRESS=0x...
  VITE_EURC_ADDRESS=0x...
  VITE_MARC_ADDRESS=0x...
  ```

  ### Deploy to Local Hardhat Node

  ```bash
  # Terminal 1 — start local node
  cd contracts && npx hardhat node

  # Terminal 2 — deploy
  cd contracts && npm run deploy:local
  ```

  ---

  ## Project Structure

  ```
  arclend/
  ├── artifacts/
  │   ├── arc-lend/              # React + Vite frontend dApp
  │   │   ├── src/
  │   │   │   ├── abi/           # Contract ABIs (LendingPool, MockERC20, MockPriceOracle)
  │   │   │   ├── components/    # UI components (Header, ActionModal, WalletMenu…)
  │   │   │   ├── hooks/         # useWallet, useMarkets, useUserData
  │   │   │   ├── lib/           # web3.ts, contracts.ts, constants.ts
  │   │   │   └── pages/         # Dashboard, Markets, Portfolio, Faucet, Admin
  │   └── api-server/            # Express 5 API server (future backend features)
  ├── contracts/
  │   ├── src/
  │   │   ├── LendingPool.sol    # Core protocol
  │   │   ├── MockERC20.sol      # Mintable test token with faucet
  │   │   └── MockPriceOracle.sol
  │   ├── scripts/deploy.js      # Hardhat deployment script
  │   └── hardhat.config.js
  └── lib/                       # Shared TypeScript libraries
  ```

  ---

  ## Tech Stack

  | Layer | Technology |
  |---|---|
  | Frontend | React 19, Vite, Tailwind CSS v4, shadcn/ui, Framer Motion |
  | Web3 | ethers.js v6 (no wagmi — direct ethers) |
  | Routing | wouter |
  | Contracts | Solidity 0.8.24, Hardhat, OpenZeppelin |
  | Monorepo | pnpm workspaces, TypeScript 5.9 |
  | API | Express 5, PostgreSQL, Drizzle ORM |

  ---

  ## Pages

  | Page | Path | Description |
  |---|---|---|
  | Dashboard | `/` | Protocol TVL, total supplied/borrowed, user portfolio summary |
  | Markets | `/markets` | Per-asset supply APY, borrow APY, utilization, LTV — supply/borrow actions |
  | Portfolio | `/portfolio` | User positions, health factor, earned interest, wallet balances |
  | Faucet | `/faucet` | One-click testnet token minting for USDC, EURC, mARC |
  | Admin | `/admin` | Owner-only: fee configuration, fee collector address, reserve collection |

  ---

  ## Admin & Fee Management

  The Admin page at `/admin` is only visible to the contract owner (the wallet that deployed the contracts). It allows:

  - Viewing the current protocol fee (default 0.30%)
  - Updating the fee (0–200 bps, enforced on-chain)
  - Changing the fee collector address
  - Viewing and collecting accumulated protocol reserves per market

  Owner verification is done on-chain — the page reads `owner()` directly from the LendingPool contract and compares it to the connected wallet.

  ---

  ## Security Notes

  - All state-changing functions use OpenZeppelin `ReentrancyGuard`
  - Token transfers use OpenZeppelin `SafeERC20`
  - Owner functions protected by OpenZeppelin `Ownable`
  - Protocol fee is hard-capped at 2% in the contract (`MAX_PROTOCOL_FEE = 200`)
  - Health factor is checked before every borrow and withdrawal
  - Oracle is a mock (centralised) — suitable for testnet only

  ---

  ## License

  MIT — see [LICENSE](LICENSE)
  