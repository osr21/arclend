# Changelog

  All notable changes to ArcLend are documented here.
  Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

  ## [0.3.1] — 2026-05-21

  ### Security — hardening pass

  This is a security-focused patch release. Three findings from an audit pass
  were fixed in `LendingPool.sol`; all 50 contract tests pass.

  #### Fixed
  - **[HIGH] Cross-market stale-accrual exploit.** Solvency checks
    (`_requireWithinLTVAfterBorrow`, `_requireHealthyAfterAction`,
    `getHealthFactor`) iterate every active market and read each market's
    stored `liquidityIndex` / `borrowIndex`. Previously, `borrow` /
    `withdraw` only accrued interest on the *current* market, so debt in
    untouched markets was undercounted (stale `borrowIndex`). A user could
    open debt in market A, let interest accrue without poking A, then borrow
    more from market B against collateral that was actually backing more
    debt than recorded. `liquidate` had a symmetrical bug: `getHealthFactor`
    ran against stale indices and could refuse legitimate liquidations of
    unhealthy accounts, allowing bad debt to grow. **Fix:** new internal
    `_updateAllMarkets()` accrues every active market before any
    cross-market solvency check; `liquidate` now accrues *before* the HF
    check.

  - **[HIGH] Fee-on-transfer / rebasing token accounting.** `supply`,
    `repay`, and `liquidate` previously credited the user the *requested*
    amount even when the pool received less (e.g. a transfer-tax token).
    This could mint unbacked supply credits or over-reduce debt. **Fix:**
    the pool now measures `balanceOf(this)` pre/post `safeTransferFrom`
    and uses the actual received delta for accounting. `liquidate` also
    re-clamps the received amount to the original 50% close-factor cap so
    a reflection/mint-on-transfer token cannot over-seize collateral.

  - **[MEDIUM] `addMarket` could brick a market via misconfiguration.**
    Previously only `ltv < liquidationThreshold` was enforced. A
    `reserveFactor > 10000` could underflow `_getSupplyRate` on every
    subsequent accrual, freezing the market. **Fix:** `addMarket` now
    enforces:
    - non-zero `asset`,
    - `decimals` in [1, 18],
    - `liquidationThreshold` ≤ 100%,
    - `liquidationBonus` in [100%, 125%] (below 100% punishes liquidators,
      above 125% over-rewards them),
    - `reserveFactor` ≤ 100%,
    - `optimalUtilization` in (0, RAY].
    `setOracle` rejects zero address.

  #### Known accepted risks (documented, not patched)
  - Owner key is currently a single EOA — `setOracle`, `setProtocolFee`,
    `setMarketPaused`, `setPaused`, and `withdrawProtocolReserves` are
    all owner-gated with no timelock. Before mainnet this should move
    behind a multisig + timelock.
  - Oracle is currently `MockPriceOracle` with admin-set prices because
    Chainlink/Pyth do not yet support Arc Testnet. `ChainlinkAdapter.sol`
    is wired and ready to drop in via `LendingPool.setOracle(adapter)`
    the moment feeds are available — no protocol redeploy required.
  - `_updateAllMarkets()` is O(N) over `assetList` for every borrow /
    withdraw / liquidate. With 3 listed markets this is negligible;
    governance should keep the listed-market count bounded.

  #### Deployment
  Patched contracts must be redeployed for the fixes to take effect on
  Arc Testnet — the existing deployment at
  `0x4dc7A9BbcB1139cDeDf5274272F541461ef4d20E` is the pre-patch version.

  ## [0.3.0] — 2026-05-21

  ### Wave 3 — Transaction UX polish & on-chain safety surfacing

  #### Added
  - **Live transaction hash & Arcscan link** in the supply/borrow/withdraw/repay
    modal. Hash appears the moment the wallet signs (new `submitted` state),
    not just after on-chain confirmation, and remains visible if the tx reverts.
  - **"View tx" action** on the success toast — one click to open the explorer.
  - **Pause awareness** in the action modal. The modal reads the global pause
    flag and `getMarketSafety(asset)` on open and shows a banner if either is
    active. Pauses only block `supply` / `borrow`; `withdraw` / `repay` stay
    available, matching contract semantics so users can always exit positions.
  - **Supply & borrow cap headroom UI.** Reads on-chain caps + totals and
    surfaces remaining headroom under the amount input. Caps the **Max** button
    and disables the action button if the amount would exceed the cap.
    Headroom math correctly applies the protocol fee so the client check
    matches what the contract enforces (no false-blocks near the cap).
  - **USYC unsupported handling.** The on-chain USYC contract at
    `0xe918…b86C` is currently a 183-byte stub exposing only `owner()`
    (verified on Arc Testnet, May 2026). The modal detects this at runtime
    via an explicit known-stub address allow-list + bytecode-size check,
    shows an explanatory banner, and disables supply/borrow. **Auto-unblocks**
    the moment Circle ships real bytecode at the same address — no frontend
    release needed. RPC failures fail-open so a transient outage cannot
    disable a healthy market. USDC (precompile) and EURC are explicitly
    outside this check and always enabled.

  #### Fixed
  - Stale `setTimeout` race in the action modal: the success auto-close
    timer is now tracked in a ref and cleared on unmount, on reopen, and
    before each reuse, so a prior tx's timer can never close a freshly
    re-opened modal.
  - Load-effect race: a `cancelled` flag guards state writes so quickly
    switching between markets can't clobber the modal with stale data
    from the previous asset.

  #### Changed
  - Faucet page copy for USYC now reflects its placeholder state on Arc
    Testnet (no functional mint flow displayed).
  - `replit.md` gained a "Gotchas" entry for the USYC stub and one for
    oracle availability (Chainlink/Pyth do not yet support Arc Testnet —
    `ChainlinkAdapter.sol` is wired and ready for the moment they do).

  ## [0.2.x] — earlier May 2026

  - Switched from mock tokens to real Arc Testnet tokens
    (USDC `0x3600…0000`, EURC `0x89B5…D72a`, USYC `0xe918…b86C`).
  - Added protocol pause + per-market safety (caps, pause flags, protocol fee
    with admin gating) to `LendingPool`.
  - Added `ChainlinkAdapter.sol` — production-ready oracle wrapper with
    staleness + decimals normalisation; idle until Chainlink supports Arc.
  - Portfolio & Liquidations pages, on-chain event tracking, accurate
    borrow-power math, and "Add Arc Testnet to wallet" helper.
  - Smart contracts deployed and verified on Arc Testnet:
    - `LendingPool` — `0x4dc7A9BbcB1139cDeDf5274272F541461ef4d20E`
    - `MockPriceOracle` — `0x542e06e674424F8316FAAB31Be12f5D149A03d7a`

  ## [0.1.x] — initial release

  - Aave-style lending pool: supply, borrow, repay, withdraw, liquidate.
  - Scaled-balance accounting with ray math, jump-rate interest model
    (kink at 80% utilisation), health-factor-gated borrows/withdrawals,
    up to 50% close-factor liquidations.
  - Hardhat test suite (29 tests passing).
  - React 19 + Vite frontend, ethers.js v6, Tailwind + shadcn/ui.
  