# Deployment Guide

  ## Prerequisites

  1. **Node.js 20+** and **pnpm** installed
  2. **MetaMask** with an account funded with USDC on Arc Testnet (for gas)
  3. Export your deployer wallet private key as `PRIVATE_KEY`
  4. Get testnet USDC from [faucet.circle.com](https://faucet.circle.com)

  ---

  ## Step 1 — Compile Contracts

  ```bash
  cd contracts
  npm install
  npm run compile
  ```

  You should see: `Compiled 3 Solidity files successfully`

  ---

  ## Step 2 — Deploy to Arc Testnet

  ```bash
  export PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE
  npm run deploy:testnet
  ```

  This will:
  1. Deploy `MockPriceOracle`
  2. Deploy `MockERC20` for USDC, EURC, and mARC
  3. Set initial USD prices
  4. Deploy `LendingPool` with 0.30% protocol fee (30 bps)
  5. Add all three markets
  6. Seed initial liquidity (1M USDC, 800K EURC, 100K mARC)

  The deployer wallet becomes the **protocol owner** with exclusive access to:
  - Update protocol fee (capped at 2%)
  - Change the fee collector address
  - Withdraw accumulated protocol reserves

  The output will look like:
  ```json
  {
    "network": "Arc Testnet",
    "chainId": 5042002,
    "deployer": "0x...",
    "feeCollector": "0x...",
    "protocolFeeBps": 30,
    "contracts": {
      "LendingPool": "0x...",
      "MockPriceOracle": "0x...",
      "tokens": {
        "USDC": "0x...",
        "EURC": "0x...",
        "mARC": "0x..."
      }
    }
  }
  ```

  ---

  ## Step 3 — Configure Frontend

  Set the deployed addresses as environment variables:

  ```bash
  VITE_LENDING_POOL_ADDRESS=0x...
  VITE_ORACLE_ADDRESS=0x...
  VITE_USDC_ADDRESS=0x...
  VITE_EURC_ADDRESS=0x...
  VITE_MARC_ADDRESS=0x...
  ```

  In Replit: add these in **Secrets** (padlock icon in the sidebar).
  Locally: create an `.env` file in `artifacts/arc-lend/`.

  ---

  ## Step 4 — Run the Frontend

  ```bash
  pnpm --filter @workspace/arc-lend run dev
  ```

  ---

  ## Verifying the Deployment

  1. Open the dApp and connect MetaMask with the deployer wallet
  2. Navigate to `/admin` — you should see the green "Verified Owner" badge
  3. Check that markets show live data (non-zero TVL)
  4. Try claiming tokens from the Faucet
  5. Test a supply transaction

  ---

  ## Local Development (Hardhat Node)

  ```bash
  # Terminal 1 — local blockchain
  cd contracts && npx hardhat node

  # Terminal 2 — deploy to local node
  cd contracts && npm run deploy:local

  # Configure MetaMask: add network localhost:8545, chain ID 31337
  # Copy the printed addresses to VITE_ env vars

  # Terminal 3 — start frontend
  pnpm --filter @workspace/arc-lend run dev
  ```

  ---

  ## Upgrading the Contract

  The current LendingPool is not upgradeable (no proxy pattern). To deploy a new version:

  1. Make changes to `contracts/src/LendingPool.sol`
  2. Run `npm run deploy:testnet` — this deploys a fresh contract
  3. Update all 5 `VITE_` environment variables with the new addresses
  4. Note: existing user positions on the old contract will not migrate

  ---

  ## Security Checklist

  Before deploying to a public testnet or mainnet:

  - [ ] Review all `onlyOwner` functions — consider a multi-sig wallet as owner
  - [ ] Audit the price oracle — replace MockPriceOracle with Chainlink or similar
  - [ ] Review reserve factor and protocol fee settings per market
  - [ ] Test liquidation flows end-to-end
  - [ ] Check for integer overflow/underflow edge cases at extreme utilization
  