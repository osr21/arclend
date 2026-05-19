# Frontend Guide

  ## Stack

  - **React 19** with hooks
  - **Vite** for bundling (fast HMR, ESM-native)
  - **Tailwind CSS v4** for styling
  - **shadcn/ui** for base components (Button, Input, Dialog, Badge, Toast…)
  - **Framer Motion** for animations
  - **wouter** for client-side routing (lightweight React Router alternative)
  - **ethers.js v6** for all blockchain interactions
  - **@tanstack/react-query** for data fetching state management

  ---

  ## Key Files

  ### `src/lib/constants.ts`
  Defines contract addresses (from `VITE_` env vars) and the `ASSETS` array — the single source of truth for which tokens are supported, their decimals, colors, and addresses.

  ### `src/lib/web3.ts`
  Low-level Web3 utilities:
  - `getReadProvider()` — singleton JsonRpcProvider for read-only calls
  - `getWriteProvider()` — returns a BrowserProvider + signer from MetaMask
  - `switchToArcTestnet()` — prompts MetaMask to switch/add Arc Testnet
  - `formatAmount()`, `shortenAddress()` — display helpers

  ### `src/lib/contracts.ts`
  All contract interaction functions:
  - **Read:** `fetchAllMarkets`, `fetchUserAccountData`, `fetchUserReserves`, `fetchTokenBalance`, `fetchAllowance`
  - **Write:** `approveToken`, `supplyAsset`, `withdrawAsset`, `borrowAsset`, `repayAsset`, `claimFaucet`
  - **Admin:** `fetchProtocolFeeConfig`, `fetchAllMarketReserves`, `adminSetProtocolFee`, `adminSetFeeCollector`, `adminWithdrawReserves`

  ### `src/hooks/useWallet.ts`
  Manages MetaMask connection state:
  - Tracks address, chainId, connecting/switching states
  - Listens to MetaMask `accountsChanged` and `chainChanged` events
  - Implements session-based disconnect (sessionStorage flag) since MetaMask doesn't support programmatic disconnection

  ### `src/hooks/useMarkets.ts`
  Fetches and caches market data with 30-second auto-refresh. Only shows loading spinner on the first load (not on background refreshes) to avoid UI flicker.

  ### `src/hooks/useUserData.ts`
  Fetches user account data and per-asset reserve data when a wallet is connected.

  ---

  ## Pages

  ### Dashboard (`/`)
  Protocol overview cards (TVL, total supplied, total borrowed, active markets) plus a user portfolio summary when connected.

  ### Markets (`/markets`)
  Table of all supported assets with supply APY, borrow APY, utilization bar, LTV, and Supply/Borrow action buttons that open the ActionModal.

  ### Portfolio (`/portfolio`)
  User's active positions — what they've supplied, what they've borrowed, health factor gauge, wallet balances.

  ### Faucet (`/faucet`)
  Grid of token cards with a Claim button for each. Calls `MockERC20.faucet()` which mints 1,000 tokens to the caller.

  ### Admin (`/admin`)
  Owner-only page. The Admin nav link only appears in the header when the connected wallet matches the on-chain `owner()`. Shows protocol fee config, fee collector address, and per-market claimable reserves.

  ---

  ## ActionModal

  The `ActionModal` component handles all four transaction types (supply, borrow, withdraw, repay):

  1. On open — fetches token balance and allowance
  2. If supply/repay and no allowance — shows Approve button first
  3. Approval grants `MaxUint256` (unlimited) — user never approves again for that token
  4. If amount is changed after approval to exceed the granted allowance — resets back to Approve step
  5. Transaction confirmed — shows success state, calls `onSuccess` to refetch markets, closes after 1.5s
  6. User rejection (MetaMask code 4001) — silently clears state, no error shown
  7. Other errors — shown in a red banner inside the modal

  ---

  ## Environment Variables

  Set these in Replit Secrets or as `.env` for local dev:

  ```
  VITE_LENDING_POOL_ADDRESS=0x...
  VITE_ORACLE_ADDRESS=0x...
  VITE_USDC_ADDRESS=0x...
  VITE_EURC_ADDRESS=0x...
  VITE_MARC_ADDRESS=0x...
  ```

  When any address is the zero address (`0x0000...`), that market shows mock fallback data.
  