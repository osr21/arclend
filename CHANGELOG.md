# Changelog

All notable changes to ArcLend are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.5.0] — 2026-06-22

### Wave 5 — Arc FX Swap, Bridge, and Circle Stablecoin Service integration

#### Added — Arc FX Swap page (`/swap`)

- **Full USDC ↔ EURC swap UI** powered by Circle's Stablecoin Kits API routed through the LiFi / Fly DEX on Arc Testnet.
- Real-time quote with estimated output, minimum amount, and fee breakdown before committing.
- Reverse button to flip token direction; live quote auto-refreshes on amount change.
- Two-step on-chain execution: `USDC.approve(adapterContract, amount)` then `adapterContract.execute(executionParams, tokenInputs, circleSignature)`.

#### Added — Circle Stablecoin Kits proxy (`api-server`)

- `GET /api/swap/quote` — proxies to `api.circle.com/v1/stablecoinKits/quote` with the `CIRCLE_KIT_KEY` secret kept server-side.
- `POST /api/swap/execute` — proxies to `api.circle.com/v1/stablecoinKits/swap`; returns `executionParams` (routing instructions + deadline + execId) and a Circle-signed authorization.
- `User-Agent: swap-kit/1.0 (node/24)` added to all outgoing Circle requests — required for Arc Testnet routing to be available.
- `toAddress` forwarded on the quote endpoint (required but previously missing).
- `slippageBps` and `stopLimit` forwarding support.

#### Fixed — Circle API "No route available" (root cause investigation)

- Identified via Circle SDK source (`@circle-fin/swap-kit` index.cjs) that Arc Testnet routes are gated on SDK identification via the `User-Agent` header. Without it, the API returns `{"code":331001,"message":"No route available"}` regardless of kit key, addresses, or parameters.
- `toAddress` is a required parameter on the GET quote endpoint (not optional as previously assumed); omitting it also caused the 404 route-not-found error.
- USDC on Arc does not support EIP-2612 permit — `PermitType.NONE` (pre-approval) is the correct strategy. The `buildTokenInputs` fallback in the Circle SDK confirms this path.

**Confirmed working swap transaction:** [`0x5f6ac0da...`](https://testnet.arcscan.app/tx/0x5f6ac0da044878b2461bfb6fa3ff8ff523dabfddd9c746a11f98c0b57a1633f2)

#### Fixed — Bridge page Sepolia USDC balance

- `getSepoliaUsdcBalanceStatic` now uses `JsonRpcProvider(sepoliaRpc)` directly instead of the connected wallet provider. This means the displayed Sepolia balance is always correct regardless of which network MetaMask is currently switched to.

#### Fixed — API server build (`api-server`)

- `ethers` added to esbuild `external` list in `build.mjs` to prevent bundling issues.
- Resolved stale pnpm symlinks that caused startup failures after dependency changes.

---

## [0.4.0] — 2026-05-31

### Wave 4 — Composable integration layer & gasless supply

A purely **additive** release. Two new contracts deploy *on top of* the
already-live `LendingPool` (no core redeploy), the dApp gains a Vaults page
and a gasless supply flow, and the api-server takes on its first real job: a
meta-transaction relayer.

#### Added — Smart contracts (composable layer)
- **`ArcLendVault.sol` — ERC-4626 wrapper around a single supply market.**
  Deposits forward into the live `LendingPool`; the vault issues transferable
  `alvUSDC` / `alvEURC` shares so ArcLend yield becomes composable in any
  ERC-4626-aware protocol. Previews are fee-aware so the pool's 30 bps fee
  never silently dilutes share holders. `totalAssets()` reads
  `getUserReserveData(vault, asset)` so share value auto-accrues with pool
  interest (subject to the usual poke-to-materialize caveat on reads).
- **`ArcLendGaslessRouter.sol` — gasless supply via EIP-3009.** The user signs
  a `ReceiveWithAuthorization` message off-chain; a relayer submits it, the
  router pulls USDC/EURC and deposits into an `ArcLendVault`, minting shares to
  the user. The user pays **zero gas** — ideal on Arc, where USDC *is* the gas
  token.
- Minimal interfaces backing the layer: `interfaces/ILendingPool.sol`,
  `interfaces/IEIP3009.sol`.

#### Added — Frontend
- **Vaults page (`/vaults`).** Lists the alvUSDC / alvEURC vaults with share
  price, your share balance, and underlying value. Deposit and withdraw via the
  new `VaultModal`.
- **Gasless deposit toggle.** When enabled, the modal builds and signs an
  EIP-3009 authorization (ERC-5267 domain resolution with a Circle-style
  fallback) and submits it to the relayer — no wallet gas prompt. Standard
  approve + deposit and redeem-based withdraw remain available.
- `useVaults` hook, an EIP-3009 signing helper, and vault read/write functions
  in `lib/contracts.ts`.

#### Added — Backend (api-server)
- **`POST /gasless/supply` relayer endpoint.** Validates the request against the
  generated Zod schema, runs a static-call preflight (so malformed or expired
  authorizations fail cleanly without spending gas), then submits the
  transaction with the relayer wallet and returns the tx hash + minted shares.
- **Rate limiting** — 10 requests/min per client (429 on exceed).
- Hardened input validation: malformed `validAfter` / `validBefore` bounds
  return a clean 400 (not a 500), plus bytes32 / uint8 shape checks.

#### Deployed — Arc Testnet integration layer
| Contract | Address |
|---|---|
| ArcLendGaslessRouter | `0xFE338289BA0f113933853759baD76B251932341a` |
| alvUSDC vault | `0x363C4eE3CfD814D3CC3bc72aCe4259453cF651EB` |
| alvEURC vault | `0xf9A7CD2c92CB6957ECeFffE2881c5Bd163a2CAeD` |

#### Notes
- Building the gasless integration pulls OpenZeppelin's `EIP712` / `ECDSA`
  utils, which emit the `mcopy` opcode — the Hardhat config's `evmVersion` must
  be `cancun` (Arc supports it) for those to compile under solc 0.8.24.

---

## [0.3.1] — 2026-05-21

### Security — hardening pass

#### Fixed
- **[HIGH] Cross-market stale-accrual exploit.** `borrow` / `withdraw` only
  accrued interest on the *current* market, leaving debt in untouched markets
  undercounted. Added `_updateAllMarkets()` — accrues every active market before
  any cross-market solvency check; `liquidate` also accrues before the HF check.
- **[HIGH] Fee-on-transfer / rebasing token accounting.** Pool now measures
  `balanceOf(this)` pre/post `safeTransferFrom` and uses the actual received
  delta for accounting.
- **[MEDIUM] `addMarket` misconfiguration guard.** Now enforces non-zero asset,
  valid decimals, `liquidationThreshold` ≤ 100%, `liquidationBonus` in [100%, 125%],
  `reserveFactor` ≤ 100%, `optimalUtilization` in (0, RAY]. `setOracle` rejects zero address.

---

## [0.3.0] — 2026-05-21

### Wave 3 — Transaction UX polish & on-chain safety surfacing

#### Added
- Live transaction hash & Arcscan link in the action modal.
- Pause awareness (global + per-market) in the action modal.
- Supply & borrow cap headroom UI with fee-correct Max button.
- USYC stub detection at runtime — disabled until Circle ships the production contract.

#### Fixed
- Stale `setTimeout` race in the action modal.
- Load-effect race when switching between markets quickly.

---

## [0.2.x] — earlier May 2026

- Switched from mock tokens to real Arc Testnet tokens
  (USDC `0x3600…0000`, EURC `0x89B5…D72a`, USYC `0xe918…b86C`).
- Added protocol pause + per-market safety (caps, pause flags, protocol fee
  with admin gating) to `LendingPool`.
- Added `ChainlinkAdapter.sol` — production-ready oracle wrapper; idle until
  Chainlink supports Arc Testnet.
- Portfolio & Liquidations pages, on-chain event tracking, accurate
  borrow-power math, and "Add Arc Testnet to wallet" helper.
- Smart contracts deployed and verified on Arc Testnet:
  - `LendingPool` — `0x4dc7A9BbcB1139cDeDf5274272F541461ef4d20E`
  - `MockPriceOracle` — `0x542e06e674424F8316FAAB31Be12f5D149A03d7a`

---

## [0.1.x] — initial release

- Aave-style lending pool: supply, borrow, repay, withdraw, liquidate.
- Scaled-balance accounting with ray math, jump-rate interest model
  (kink at 80% utilisation), health-factor-gated borrows/withdrawals,
  up to 50% close-factor liquidations.
- Hardhat test suite (29 tests passing).
- React 19 + Vite frontend, ethers.js v6, Tailwind + shadcn/ui.
