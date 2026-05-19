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
  