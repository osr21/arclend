// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingPool} from "../src/LendingPool.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";

contract MockToken {
    uint8 public immutable decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "balance");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockOracle is IPriceOracle {
    mapping(address => uint256) public prices;

    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }
}

contract LendingPoolTest {
    uint256 private constant UNIT = 1e6;
    uint256 private constant USD = 1e8;

    LendingPool private pool;
    MockOracle private oracle;
    MockToken private usdc;
    MockToken private eurc;
    address private constant BORROWER = address(0xB0B);
    address private constant LENDER = address(0x1EAD);
    address private constant LIQUIDATOR = address(0x11A);

    function setUp() public {
        oracle = new MockOracle();
        usdc = new MockToken(6);
        eurc = new MockToken(6);
        pool = new LendingPool(address(this), IPriceOracle(address(oracle)));
        pool.configureMarket(address(usdc), 6, 7500, 8500, 10500, true);
        pool.configureMarket(address(eurc), 6, 7000, 8000, 10500, true);
        oracle.setPrice(address(usdc), USD);
        oracle.setPrice(address(eurc), USD);

        usdc.mint(LENDER, 10_000 * UNIT);
        usdc.mint(LIQUIDATOR, 1_000 * UNIT);
        eurc.mint(BORROWER, 2_000 * UNIT);
        _approve(usdc, LENDER);
        _approve(usdc, LIQUIDATOR);
        _approve(usdc, BORROWER);
        _approve(eurc, BORROWER);
    }

    function testBorrowAndRepayRestoresLiquidity() public {
        vmPrank(LENDER);
        pool.addLiquidity(address(usdc), 2_000 * UNIT);

        vmPrank(BORROWER);
        pool.supplyCollateral(address(eurc), 1_000 * UNIT);
        (, uint256 borrowLimit,) = pool.accountValues(BORROWER);
        require(borrowLimit == 700 * UNIT * USD / UNIT, "collateral limit calculation");
        vmPrank(BORROWER);
        pool.borrow(address(usdc), 700 * UNIT);

        require(usdc.balanceOf(BORROWER) == 700 * UNIT, "borrow transfer");
        require(pool.availableLiquidity(address(usdc)) == 1_300 * UNIT, "liquidity decrease");

        vmPrank(BORROWER);
        pool.repay(BORROWER, address(usdc), 700 * UNIT);
        require(pool.availableLiquidity(address(usdc)) == 2_000 * UNIT, "liquidity restore");
    }

    function testBorrowAboveLtvReverts() public {
        vmPrank(LENDER);
        pool.addLiquidity(address(usdc), 2_000 * UNIT);
        vmPrank(BORROWER);
        pool.supplyCollateral(address(eurc), 1_000 * UNIT);

        vmPrank(BORROWER);
        (bool ok,) = address(pool).call(
            abi.encodeCall(pool.borrow, (address(usdc), 751 * UNIT))
        );
        require(!ok, "borrow above ltv must revert");
    }

    function testLiquidationAfterOraclePriceDrop() public {
        vmPrank(LENDER);
        pool.addLiquidity(address(usdc), 2_000 * UNIT);
        vmPrank(BORROWER);
        pool.supplyCollateral(address(eurc), 1_000 * UNIT);
        vmPrank(BORROWER);
        pool.borrow(address(usdc), 700 * UNIT);

        oracle.setPrice(address(eurc), 8e7);
        vmPrank(LIQUIDATOR);
        uint256 seized = pool.liquidate(BORROWER, address(usdc), address(eurc), 100 * UNIT);

        require(seized == 131_250_000, "bonus-adjusted collateral amount");
        require(pool.debt(BORROWER, address(usdc)) == 600 * UNIT, "debt reduced");
        require(eurc.balanceOf(LIQUIDATOR) == seized, "collateral transferred");
    }

    function testLenderCannotWithdrawOtherProvidersLiquidity() public {
        vmPrank(LENDER);
        pool.addLiquidity(address(usdc), 2_000 * UNIT);

        (bool ok,) = address(pool).call(
            abi.encodeCall(pool.removeLiquidity, (address(usdc), 1))
        );
        require(!ok, "non-provider must not withdraw");
    }

    function testPausedPoolBlocksRiskIncreasingActionsButAllowsRepayment() public {
        vmPrank(LENDER);
        pool.addLiquidity(address(usdc), 2_000 * UNIT);
        vmPrank(BORROWER);
        pool.supplyCollateral(address(eurc), 1_000 * UNIT);
        vmPrank(BORROWER);
        pool.borrow(address(usdc), 700 * UNIT);

        pool.setPaused(true);
        (bool borrowOk,) =
            address(pool).call(abi.encodeCall(pool.borrow, (address(usdc), 1)));
        require(!borrowOk, "paused borrow");

        vmPrank(BORROWER);
        pool.repay(BORROWER, address(usdc), 1);
        require(pool.debt(BORROWER, address(usdc)) == 700 * UNIT - 1, "repay remains enabled");
    }

    function _approve(MockToken token, address account) private {
        vmPrank(account);
        token.approve(address(pool), type(uint256).max);
    }

    function vmPrank(address account) private {
        (bool ok,) = address(vm).call(abi.encodeWithSignature("prank(address)", account));
        require(ok, "cheatcode unavailable");
    }

    address private constant vm =
        address(uint160(uint256(keccak256("hevm cheat code"))));
}

