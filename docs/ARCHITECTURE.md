# Architecture

  ## Overview

  ArcLend is a pure frontend dApp — all protocol data is read directly from the blockchain via ethers.js. There is no backend required for the core protocol.

  ```
  ┌────────────────────────────────────────────────┐
  │                  Browser                        │
  │                                                 │
  │  React 19 + Vite + Tailwind + shadcn/ui        │
  │  ┌──────────────────────────────────────────┐  │
  │  │  Pages: Dashboard / Markets / Portfolio  │  │
  │  │          Faucet / Admin                  │  │
  │  └────────────────┬─────────────────────────┘  │
  │                   │                             │
  │  ┌────────────────▼─────────────────────────┐  │
  │  │  Hooks: useWallet / useMarkets /         │  │
  │  │         useUserData                      │  │
  │  └────────────────┬─────────────────────────┘  │
  │                   │                             │
  │  ┌────────────────▼─────────────────────────┐  │
  │  │  lib/contracts.ts  (ethers.js calls)     │  │
  │  │  lib/web3.ts       (provider/signer)     │  │
  │  └────────────────┬─────────────────────────┘  │
  └───────────────────┼────────────────────────────┘
                      │ JSON-RPC
  ┌───────────────────▼────────────────────────────┐
  │         Arc Testnet (Chain ID 5042002)          │
  │                                                 │
  │  LendingPool ◄──► MockPriceOracle              │
  │  MockERC20 (USDC, EURC, mARC)                  │
  └────────────────────────────────────────────────┘
  ```

  ---

  ## Key Design Decisions

  ### ethers.js v6 (no wagmi)
  Direct ethers usage was chosen over wagmi to avoid the React hooks abstraction layer and keep the Web3 code simple and explicit. The provider is a singleton with `staticNetwork: true` to prevent background network polling that would cause unhandled promise rejections.

  ### Singleton Provider
  ```typescript
  // lib/web3.ts
  let _readProvider: ethers.JsonRpcProvider | null = null;

  export function getReadProvider(): ethers.JsonRpcProvider {
    if (!_readProvider) {
      _readProvider = new ethers.JsonRpcProvider(RPC_URL, network, {
        staticNetwork: true,
        polling: false,
      });
    }
    return _readProvider;
  }
  ```

  ### MaxUint256 Approval
  The ActionModal approves `MaxUint256` on first supply/repay, so users never need to approve again for the same token. This is a common DeFi UX pattern.

  ### Session-Based Disconnect
  MetaMask does not support programmatic disconnection. The dApp tracks disconnect intent in `sessionStorage` so the UI respects the user's choice within the tab session, while auto-reconnecting on the next visit.

  ### Graceful Degradation
  When contract addresses are not configured (`0x0000...`), the dApp shows mock data rather than erroring out. This is intentional to allow UI development without live contracts.

  ---

  ## Data Flow

  ### Market Data (every 30s)
  ```
  useMarkets hook
    └─ fetchAllMarkets()          — reads getMarketData() for each asset
         └─ getMarketData(asset)  — LendingPool view function
              └─ Returns: supply/borrow totals, APY rates, utilization, liquidity
  ```

  ### User Data (on wallet connect + 30s)
  ```
  useUserData hook
    ├─ fetchUserAccountData()     — getUserAccountData(address)
    │    └─ Returns: collateral, debt, available borrows, health factor
    └─ fetchUserReserves()        — getUserReserveData(address, asset) × 3 assets
         └─ Returns: per-asset supply/borrow balances and rates
  ```

  ### Transaction Flow (supply example)
  ```
  ActionModal
    1. fetchTokenBalance()     — check wallet has enough tokens
    2. fetchAllowance()        — check current approval
    3. approveToken(MaxUint256) — if not approved (one-time)
    4. supplyAsset(amount)     — calls LendingPool.supply()
    5. onSuccess() callback    — triggers useMarkets refetch
  ```

  ---

  ## Monorepo Structure

  The project uses pnpm workspaces:

  | Package | Role |
  |---|---|
  | `@workspace/arc-lend` | React + Vite frontend |
  | `@workspace/api-server` | Express 5 API (future backend features) |
  | `@workspace/mockup-sandbox` | Vite sandbox for UI component development |

  Shared TypeScript config extends `tsconfig.base.json` at the root.
  