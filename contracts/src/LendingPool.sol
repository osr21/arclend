// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {SafeTransfer} from "./libraries/SafeTransfer.sol";

/// @notice Experimental, non-upgradeable lending pool for Arc Testnet only.
/// @dev No interest accrual, flash loans, production oracle, or audit is included.
///      Do not deploy this prototype on Mainnet or accept real-value deposits.
contract LendingPool {
    using SafeTransfer for address;

    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_LIQUIDATION_BONUS_BPS = 12_500;

    struct Market {
        uint8 decimals;
        uint16 ltvBps;
        uint16 liquidationThresholdBps;
        uint16 liquidationBonusBps;
        bool active;
    }

    address public owner;
    IPriceOracle public oracle;
    bool public paused;
    uint256 private _entered = 1;

    mapping(address asset => Market) public markets;
    address[] private _marketAssets;
    mapping(address asset => bool listed) private _listedAsset;
    mapping(address user => mapping(address asset => uint256 amount)) public collateral;
    mapping(address user => mapping(address asset => uint256 amount)) public debt;
    mapping(address asset => uint256 amount) public availableLiquidity;
    mapping(address provider => mapping(address asset => uint256 amount)) public liquidityShares;

    error Unauthorized();
    error ZeroAddress();
    error InvalidMarket();
    error InvalidRiskParameters();
    error InvalidAmount();
    error Paused();
    error ReentrantCall();
    error InsufficientLiquidity();
    error InsufficientCollateral();
    error UnhealthyPosition();
    error HealthyPosition();
    error InsufficientCollateralForLiquidation();
    error InvalidOraclePrice(address asset);

    event MarketConfigured(
        address indexed asset,
        uint8 decimals,
        uint16 ltvBps,
        uint16 liquidationThresholdBps,
        uint16 liquidationBonusBps,
        bool active
    );
    event OracleUpdated(address indexed previousOracle, address indexed newOracle);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PauseUpdated(bool paused);
    event LiquidityAdded(address indexed provider, address indexed asset, uint256 amount);
    event LiquidityRemoved(address indexed provider, address indexed asset, uint256 amount);
    event CollateralSupplied(address indexed user, address indexed asset, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed payer, address indexed borrower, address indexed asset, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address indexed debtAsset,
        address collateralAsset,
        uint256 repaid,
        uint256 collateralSeized
    );

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier nonReentrant() {
        if (_entered != 1) revert ReentrantCall();
        _entered = 2;
        _;
        _entered = 1;
    }

    constructor(address owner_, IPriceOracle oracle_) {
        if (owner_ == address(0) || address(oracle_) == address(0)) revert ZeroAddress();
        owner = owner_;
        oracle = oracle_;
        emit OracleUpdated(address(0), address(oracle_));
    }

    function configureMarket(
        address asset,
        uint8 decimals_,
        uint16 ltvBps,
        uint16 liquidationThresholdBps,
        uint16 liquidationBonusBps,
        bool active
    ) external onlyOwner {
        if (asset == address(0) || decimals_ > 18) revert InvalidMarket();
        if (
            ltvBps == 0 || ltvBps > liquidationThresholdBps || liquidationThresholdBps > BPS
                || liquidationBonusBps < BPS || liquidationBonusBps > MAX_LIQUIDATION_BONUS_BPS
        ) revert InvalidRiskParameters();
        if (!_listedAsset[asset]) {
            _listedAsset[asset] = true;
            _marketAssets.push(asset);
        }
        markets[asset] = Market({
            decimals: decimals_,
            ltvBps: ltvBps,
            liquidationThresholdBps: liquidationThresholdBps,
            liquidationBonusBps: liquidationBonusBps,
            active: active
        });
        emit MarketConfigured(
            asset, decimals_, ltvBps, liquidationThresholdBps, liquidationBonusBps, active
        );
    }

    function setOracle(IPriceOracle newOracle) external onlyOwner {
        if (address(newOracle) == address(0)) revert ZeroAddress();
        emit OracleUpdated(address(oracle), address(newOracle));
        oracle = newOracle;
    }

    function setPaused(bool value) external onlyOwner {
        paused = value;
        emit PauseUpdated(value);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Adds lender liquidity. This is separate from borrower collateral.
    function addLiquidity(address asset, uint256 amount)
        external
        whenNotPaused
        nonReentrant
    {
        _requireMarket(asset);
        if (amount == 0) revert InvalidAmount();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        availableLiquidity[asset] += amount;
        liquidityShares[msg.sender][asset] += amount;
        emit LiquidityAdded(msg.sender, asset, amount);
    }

    function removeLiquidity(address asset, uint256 amount) external nonReentrant {
        _requireListedMarket(asset);
        if (amount == 0) revert InvalidAmount();
        if (liquidityShares[msg.sender][asset] < amount) revert InsufficientLiquidity();
        if (availableLiquidity[asset] < amount) revert InsufficientLiquidity();
        liquidityShares[msg.sender][asset] -= amount;
        availableLiquidity[asset] -= amount;
        asset.safeTransfer(msg.sender, amount);
        emit LiquidityRemoved(msg.sender, asset, amount);
    }

    function supplyCollateral(address asset, uint256 amount)
        external
        whenNotPaused
        nonReentrant
    {
        _requireMarket(asset);
        if (amount == 0) revert InvalidAmount();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        collateral[msg.sender][asset] += amount;
        emit CollateralSupplied(msg.sender, asset, amount);
    }

    function withdrawCollateral(address asset, uint256 amount) external nonReentrant {
        _requireListedMarket(asset);
        if (amount == 0) revert InvalidAmount();
        uint256 balance = collateral[msg.sender][asset];
        if (balance < amount) revert InsufficientCollateral();
        collateral[msg.sender][asset] = balance - amount;
        uint256 currentDebt = _debtValue(msg.sender);
        if (currentDebt != 0 && currentDebt > _borrowLimit(msg.sender)) {
            revert UnhealthyPosition();
        }
        asset.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, asset, amount);
    }

    function borrow(address asset, uint256 amount) external whenNotPaused nonReentrant {
        _requireListedMarket(asset);
        if (amount == 0) revert InvalidAmount();
        if (availableLiquidity[asset] < amount) revert InsufficientLiquidity();
        availableLiquidity[asset] -= amount;
        debt[msg.sender][asset] += amount;
        if (_debtValue(msg.sender) > _borrowLimit(msg.sender)) revert UnhealthyPosition();
        asset.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, asset, amount);
    }

    function repay(address borrower, address asset, uint256 amount)
        external
        nonReentrant
        returns (uint256 repaid)
    {
        _requireMarket(asset);
        if (borrower == address(0) || amount == 0) revert InvalidAmount();
        uint256 owed = debt[borrower][asset];
        repaid = amount < owed ? amount : owed;
        if (repaid == 0) revert InvalidAmount();
        asset.safeTransferFrom(msg.sender, address(this), repaid);
        debt[borrower][asset] = owed - repaid;
        availableLiquidity[asset] += repaid;
        emit Repaid(msg.sender, borrower, asset, repaid);
    }

    function liquidate(address borrower, address debtAsset, address collateralAsset, uint256 repayAmount)
        external
        nonReentrant
        returns (uint256 collateralSeized)
    {
        _requireMarket(debtAsset);
        _requireMarket(collateralAsset);
        if (borrower == address(0) || repayAmount == 0) revert InvalidAmount();
        if (_debtValue(borrower) <= _liquidationLimit(borrower)) revert HealthyPosition();

        uint256 owed = debt[borrower][debtAsset];
        uint256 repaid = repayAmount < owed ? repayAmount : owed;
        uint256 debtPrice = _price(debtAsset);
        uint256 collateralPrice = _price(collateralAsset);
        Market memory debtMarket = markets[debtAsset];
        Market memory collateralMarket = markets[collateralAsset];

        // USD-value conversion, with explicit checked arithmetic. Reverts rather
        // than silently truncating if an extreme amount or price overflows.
        uint256 debtValue = (repaid * debtPrice) / (10 ** debtMarket.decimals);
        uint256 seizeValue = (debtValue * collateralMarket.liquidationBonusBps) / BPS;
        collateralSeized =
            (seizeValue * (10 ** collateralMarket.decimals)) / collateralPrice;
        if (collateral[borrower][collateralAsset] < collateralSeized) {
            revert InsufficientCollateralForLiquidation();
        }

        debt[borrower][debtAsset] = owed - repaid;
        availableLiquidity[debtAsset] += repaid;
        collateral[borrower][collateralAsset] -= collateralSeized;
        debtAsset.safeTransferFrom(msg.sender, address(this), repaid);
        collateralAsset.safeTransfer(msg.sender, collateralSeized);
        emit Liquidated(msg.sender, borrower, debtAsset, collateralAsset, repaid, collateralSeized);
    }

    function accountValues(address user)
        external
        view
        returns (uint256 debtUsd8, uint256 borrowLimitUsd8, uint256 liquidationLimitUsd8)
    {
        return (_debtValue(user), _borrowLimit(user), _liquidationLimit(user));
    }

    function _requireMarket(address asset) internal view {
        if (!markets[asset].active) revert InvalidMarket();
    }

    function _requireListedMarket(address asset) internal view {
        if (!_listedAsset[asset]) revert InvalidMarket();
    }

    function _price(address asset) internal view returns (uint256 price) {
        price = oracle.getAssetPrice(asset);
        if (price == 0) revert InvalidOraclePrice(asset);
    }

    function _debtValue(address user) internal view returns (uint256 value) {
        uint256 length = _marketAssets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _marketAssets[i];
            uint256 amount = debt[user][asset];
            if (amount != 0) {
                value += (amount * _price(asset)) / (10 ** markets[asset].decimals);
            }
        }
    }

    function _borrowLimit(address user) internal view returns (uint256 value) {
        uint256 length = _marketAssets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _marketAssets[i];
            uint256 amount = collateral[user][asset];
            if (amount != 0) {
                uint256 collateralValue =
                    (amount * _price(asset)) / (10 ** markets[asset].decimals);
                value += (collateralValue * markets[asset].ltvBps) / BPS;
            }
        }
    }

    function _liquidationLimit(address user) internal view returns (uint256 value) {
        uint256 length = _marketAssets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _marketAssets[i];
            uint256 amount = collateral[user][asset];
            if (amount != 0) {
                uint256 collateralValue =
                    (amount * _price(asset)) / (10 ** markets[asset].decimals);
                value += (collateralValue * markets[asset].liquidationThresholdBps) / BPS;
            }
        }
    }
}

