# Smart Contracts

  ## Overview

  ArcLend's on-chain logic lives in three contracts:

  | Contract | Purpose |
  |---|---|
  | `LendingPool.sol` | Core protocol — supply, borrow, repay, withdraw, liquidation, fee collection |
  | `MockERC20.sol` | Mintable ERC20 with a public `faucet()` function for testnet use |
  | `MockPriceOracle.sol` | USD price feed (8 decimals, Chainlink-style), owner-settable |

  ---

  ## LendingPool.sol

  ### Key Concepts

  **Scaled Balances (like Aave's aTokens)**
  Interest accrues continuously using index math (ray = 1e27):
  ```
  scaledSupply = amount / liquidityIndex
  currentSupply = scaledSupply × liquidityIndex
  ```
  This means stored balances automatically grow over time as the index increases — no per-user updates needed.

  **Reserve Factor**
  A percentage of interest paid by borrowers goes to `protocolReserves` rather than lenders:
  ```
  toLenders = interestAccrued × (1 − reserveFactor)
  toProtocol = interestAccrued × reserveFactor
  ```

  **Protocol Fee**
  On every supply, borrow, and withdraw, a flat fee (`protocolFeeBps`, default 30 = 0.3%) is deducted and added to `protocolReserves`. This is separate from the reserve factor (which is interest-based).

  ---

  ### Functions

  #### User-Facing

  | Function | Description |
  |---|---|
  | `supply(address asset, uint256 amount)` | Deposit tokens. Fee deducted from net credited amount. |
  | `withdraw(address asset, uint256 amount)` | Withdraw tokens. Fee deducted from amount received. Pass `type(uint256).max` to withdraw all. |
  | `borrow(address asset, uint256 amount)` | Borrow against collateral. Fee deducted from amount received. Health factor checked. |
  | `repay(address asset, uint256 amount)` | Repay outstanding debt. Pass `type(uint256).max` to repay all. No fee on repay. |
  | `liquidate(address borrower, address debtAsset, address collateralAsset, uint256 debtAmount)` | Liquidate undercollateralised position. Max 50% of debt per call. |

  #### View

  | Function | Returns |
  |---|---|
  | `getMarketData(address asset)` | isActive, totalSupply, totalBorrow, supplyRate, borrowRate, utilizationRate, ltv, liquidationThreshold, liquidityIndex, borrowIndex, availableLiquidity |
  | `getUserAccountData(address user)` | totalCollateralUSD, totalDebtUSD, availableBorrowsUSD, healthFactor, netAPY |
  | `getUserReserveData(address user, address asset)` | currentSupply, currentBorrow, supplyRate, borrowRate |
  | `getHealthFactor(address user)` | Health factor (1e18 = 1.0; below 1e18 = liquidatable) |
  | `getProtocolReserves(address asset)` | Accumulated protocol reserves for an asset |
  | `getProtocolFeeConfig()` | feeBps, maxFeeBps, collector |

  #### Admin (onlyOwner)

  | Function | Description |
  |---|---|
  | `addMarket(...)` | Register a new asset market |
  | `setProtocolFee(uint256 newFeeBps)` | Update fee (max 200 bps = 2%) |
  | `setFeeCollector(address)` | Change the revenue recipient address |
  | `withdrawProtocolReserves(address asset)` | Send all reserves for an asset to the fee collector |
  | `setOracle(address)` | Update the price oracle |

  ---

  ### Events

  ```solidity
  event Supply(address indexed user, address indexed asset, uint256 amount);
  event Withdraw(address indexed user, address indexed asset, uint256 amount);
  event Borrow(address indexed user, address indexed asset, uint256 amount);
  event Repay(address indexed user, address indexed asset, uint256 amount);
  event Liquidate(address indexed liquidator, address indexed borrower, address indexed debtAsset, address collateralAsset, uint256 debtAmount, uint256 collateralReceived);
  event ProtocolFeeCollected(address indexed asset, uint256 fee);
  event ProtocolFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
  event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
  event ProtocolReservesWithdrawn(address indexed asset, address indexed to, uint256 amount);
  event MarketAdded(address indexed asset, uint256 ltv, uint256 liquidationThreshold);
  ```

  ---

  ## MockERC20.sol

  A simple ERC20 with:
  - `mint(address to, uint256 amount)` — unrestricted minting (testnet only)
  - `faucet()` — mints 1,000 tokens to the caller (used by the Faucet page)
  - Configurable decimals set at deployment

  ## MockPriceOracle.sol

  - `getAssetPrice(address asset)` — returns USD price with 8 decimals
  - `setAssetPrices(address[] assets, uint256[] prices)` — owner-only batch price update

  Default prices at deployment:
  | Asset | Price |
  |---|---|
  | USDC | $1.00 |
  | EURC | $1.09 |
  | mARC | $5.50 |
  

    ---

    ## Composable Integration Layer

    Two contracts deploy **on top of** the already-live `LendingPool` — no core
    redeploy. They make ArcLend yield composable and enable zero-gas supply.

    ### ArcLendVault.sol — ERC-4626 vault

    A standards-compliant ERC-4626 wrapper around a *single* supply market.

    - **Deposits forward into the live `LendingPool`.** The vault becomes a normal
      pool depositor under its own address.
    - **Transferable shares.** Issues `alvUSDC` / `alvEURC` so a position can be
      moved or used in any ERC-4626-aware protocol.
    - **Fee-aware previews.** `previewDeposit` / `previewMint` / `previewWithdraw` /
      `previewRedeem` account for the pool's 30 bps fee so it never silently
      dilutes share holders.
    - **Auto-accruing share value.** `totalAssets()` reads
      `getUserReserveData(vault, asset)`, so share price tracks pool interest
      (subject to the poke-to-materialize caveat that applies to all reads).

    | Function | Description |
    |---|---|
    | `deposit(uint256 assets, address receiver)` | Pull assets, deposit into the pool, mint shares. |
    | `mint(uint256 shares, address receiver)` | Mint an exact share amount; pulls the required assets. |
    | `withdraw(uint256 assets, address receiver, address owner)` | Withdraw an exact asset amount, burning shares. |
    | `redeem(uint256 shares, address receiver, address owner)` | Burn shares, withdraw the corresponding assets. |
    | `totalAssets()` | Underlying value of the vault's pool position. |

    ### ArcLendGaslessRouter.sol — gasless supply (EIP-3009)

    Lets a user supply **without paying gas** by composing an EIP-3009
    `ReceiveWithAuthorization` with a vault deposit.

    1. The user signs a `ReceiveWithAuthorization` message off-chain (no gas).
    2. A relayer submits the signed authorization to the router.
    3. The router pulls USDC/EURC via EIP-3009 and deposits into an `ArcLendVault`,
       minting shares to the user.

    The user pays **zero gas** — especially valuable on Arc, where USDC *is* the
    native gas token. Backed by minimal interfaces `interfaces/ILendingPool.sol`
    and `interfaces/IEIP3009.sol`.

    > **Build note:** these contracts pull OpenZeppelin's `EIP712` / `ECDSA` utils,
    > which emit the `mcopy` opcode. The Hardhat `evmVersion` must be `cancun` (Arc
    > supports it) for them to compile under solc 0.8.24.

    ### ChainlinkAdapter.sol — oracle wrapper (idle)

    Production-ready wrapper for Chainlink `AggregatorV3` feeds with staleness +
    decimals normalisation. Inactive until Chainlink supports Arc Testnet — wire it
    in with `LendingPool.setOracle(adapter)` when feeds land, no redeploy required.
  