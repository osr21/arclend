# Changelog

  All notable changes to ArcLend are documented here.
  Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
  