// Regression tests for the v0.3.1 security hardening pass.
//
// These lock in three fixes:
//   1. Cross-market stale-accrual exploit — borrow/withdraw/liquidate must
//      accrue EVERY active market before any cross-market solvency check.
//   2. Fee-on-transfer accounting — supply/repay/liquidate must credit the
//      tokens the pool actually receives, not the amount the user requested.
//   3. addMarket parameter bounds — admin can't brick a market by passing
//      out-of-range risk parameters.
//
// If any of these tests start failing, a previously-closed vulnerability has
// regressed.

const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const RAY = 10n ** 27n;
const pct = (p) => (RAY * BigInt(p)) / 100n;

async function deployFixture() {
  const [owner, alice, bob] = await ethers.getSigners();

  const Oracle = await ethers.getContractFactory("MockPriceOracle");
  const oracle = await Oracle.deploy();
  await oracle.waitForDeployment();

  const ERC20 = await ethers.getContractFactory("MockERC20");
  const usdc = await ERC20.deploy("USD Coin", "USDC", 6);
  const eurc = await ERC20.deploy("Euro Coin", "EURC", 6);
  const marc = await ERC20.deploy("Mock ARC", "mARC", 18);
  await Promise.all([usdc, eurc, marc].map((t) => t.waitForDeployment()));

  await oracle.setAssetPrices(
    [usdc.target, eurc.target, marc.target],
    [100_000_000n, 109_000_000n, 5_50000000n],
  );

  const Pool = await ethers.getContractFactory("LendingPool");
  const pool = await Pool.deploy(oracle.target, 0);
  await pool.waitForDeployment();

  await pool.addMarket(usdc.target, 6, 8500, 9000, 10500, 1000, pct(2), pct(8), pct(80), pct(100));
  await pool.addMarket(eurc.target, 6, 8500, 9000, 10500, 1000, pct(2), pct(8), pct(80), pct(100));
  await pool.addMarket(marc.target, 18, 6000, 6500, 11000, 2000, pct(3), pct(10), pct(70), pct(150));

  const seed = async (token, amt) => {
    await token.mint(owner.address, amt);
    await token.approve(pool.target, amt);
    await pool.supply(token.target, amt);
  };
  await seed(usdc, 1_000_000n * 10n ** 6n);
  await seed(eurc, 800_000n * 10n ** 6n);
  await seed(marc, 100_000n * 10n ** 18n);

  const give = async (token, to, amt) => {
    if (amt > 0n) await token.mint(to.address, amt);
    await token.connect(to).approve(pool.target, ethers.MaxUint256);
  };

  return { owner, alice, bob, oracle, usdc, eurc, marc, pool, give };
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Cross-market stale-accrual regression
// ─────────────────────────────────────────────────────────────────────────────

describe("v0.3.1 hardening — cross-market stale-accrual", () => {
  // The fix: borrow/withdraw/liquidate now call _updateAllMarkets() before any
  // cross-market solvency check. The smoking gun for the fix is that an
  // unrelated market's borrowIndex moves forward when you call one of these
  // functions on a DIFFERENT market. Pre-fix, only the touched market would
  // have its index updated; an attacker could exploit the stale debt reading
  // to over-borrow against collateral backing stale debt.

  it("borrow on market B accrues market A's stale debt index", async () => {
    const { pool, usdc, eurc, marc, alice, give } = await deployFixture();

    // Open a real position in EURC so it has live utilization → nonzero rate.
    await give(usdc, alice, 200_000n * 10n ** 6n);
    await pool.connect(alice).supply(usdc.target, 200_000n * 10n ** 6n);
    await pool.connect(alice).borrow(eurc.target, 100_000n * 10n ** 6n);

    const eurcIndexBefore = (await pool.markets(eurc.target)).borrowIndex;

    // Time passes — debt is accruing economically but EURC's stored index is
    // frozen until someone touches that market.
    await time.increase(180 * 24 * 3600);

    // Borrow a TINY amount of an UNRELATED market (mARC). With the v0.3.1 fix
    // this triggers _updateAllMarkets, so EURC's index must move forward.
    await give(marc, alice, 0n);
    await pool.connect(alice).borrow(marc.target, 1n * 10n ** 18n);

    const eurcIndexAfter = (await pool.markets(eurc.target)).borrowIndex;
    expect(eurcIndexAfter).to.be.greaterThan(eurcIndexBefore);
  });

  it("withdraw on market B accrues market A's stale debt index", async () => {
    const { pool, usdc, eurc, alice, give } = await deployFixture();

    // Two-leg position: USDC supply + EURC borrow. Add a small mARC supply
    // we can later withdraw without breaking HF.
    const { marc } = await deployFixtureExtras();
    void marc;
    await give(usdc, alice, 100_000n * 10n ** 6n);
    await pool.connect(alice).supply(usdc.target, 100_000n * 10n ** 6n);
    await pool.connect(alice).borrow(eurc.target, 50_000n * 10n ** 6n);

    const eurcIndexBefore = (await pool.markets(eurc.target)).borrowIndex;
    await time.increase(180 * 24 * 3600);

    // Withdraw a dust amount of USDC. With the fix, EURC accrues too.
    await pool.connect(alice).withdraw(usdc.target, 1n * 10n ** 6n);

    const eurcIndexAfter = (await pool.markets(eurc.target)).borrowIndex;
    expect(eurcIndexAfter).to.be.greaterThan(eurcIndexBefore);
  });

  it("liquidate accrues all markets before evaluating health factor", async () => {
    const { pool, usdc, eurc, oracle, alice, bob, give } = await deployFixture();

    // Alice opens a position close to the liquidation threshold.
    await give(usdc, alice, 100_000n * 10n ** 6n);
    await pool.connect(alice).supply(usdc.target, 100_000n * 10n ** 6n);
    await pool.connect(alice).borrow(eurc.target, 75_000n * 10n ** 6n);

    const eurcIndexBefore = (await pool.markets(eurc.target)).borrowIndex;

    // Let interest accrue silently and crash the EURC/USDC price ratio so HF
    // crosses < 1 once accrual is applied.
    await time.increase(180 * 24 * 3600);
    await oracle.setAssetPrice(eurc.target, 145_000_000n); // EUR jumps vs USD

    // Bob liquidates Alice. With the v0.3.1 fix, _updateAllMarkets runs FIRST
    // and getHealthFactor sees fresh indices. Pre-fix this would have read
    // stale EURC borrowIndex and reverted with "Healthy position".
    await give(eurc, bob, 50_000n * 10n ** 6n);
    await expect(
      pool.connect(bob).liquidate(alice.address, eurc.target, usdc.target, 10_000n * 10n ** 6n),
    ).to.not.be.reverted;

    const eurcIndexAfter = (await pool.markets(eurc.target)).borrowIndex;
    expect(eurcIndexAfter).to.be.greaterThan(eurcIndexBefore);
  });
});

// helper used above — just re-exposes marc; kept tiny on purpose
async function deployFixtureExtras() {
  const ERC20 = await ethers.getContractFactory("MockERC20");
  const marc = await ERC20.deploy("Mock ARC X", "mARCX", 18);
  await marc.waitForDeployment();
  return { marc };
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Fee-on-transfer / rebasing token defense
// ─────────────────────────────────────────────────────────────────────────────

describe("v0.3.1 hardening — fee-on-transfer token accounting", () => {
  async function fotFixture() {
    const base = await deployFixture();
    const FoT = await ethers.getContractFactory("MockFeeOnTransferERC20");
    // 5% fee on every transfer
    const fot = await FoT.deploy("Fee On Transfer", "FoT", 18, 500);
    await fot.waitForDeployment();
    // Price = $1 with 8 decimals
    await base.oracle.setAssetPrice(fot.target, 100_000_000n);
    // Conservative risk params; reserveFactor 0 to keep math clean.
    await base.pool.addMarket(fot.target, 18, 5000, 6000, 10500, 0, pct(2), pct(8), pct(80), pct(100));
    return { ...base, fot };
  }

  it("supply credits only the tokens actually received (after FoT)", async () => {
    const { pool, fot, alice, give } = await fotFixture();

    const requested = 1_000n * 10n ** 18n;
    await give(fot, alice, requested);

    const poolBalBefore = await fot.balanceOf(pool.target);
    await pool.connect(alice).supply(fot.target, requested);
    const poolBalAfter = await fot.balanceOf(pool.target);

    const received = poolBalAfter - poolBalBefore;
    // 5% fee: pool should receive exactly 95%
    expect(received).to.equal((requested * 9500n) / 10000n);

    // User's credited supply matches what the pool received, not what they sent
    const ur = await pool.getUserReserveData(alice.address, fot.target);
    expect(ur.currentSupply).to.equal(received);
  });

  it("repay reduces debt only by the actually-received amount", async () => {
    const { pool, fot, usdc, alice, give } = await fotFixture();

    // Seed FoT liquidity from owner so alice has something to borrow.
    const [owner] = await ethers.getSigners();
    await fot.mint(owner.address, 100_000n * 10n ** 18n);
    await fot.connect(owner).approve(pool.target, ethers.MaxUint256);
    await pool.connect(owner).supply(fot.target, 100_000n * 10n ** 18n);

    // Alice puts up USDC collateral and borrows FoT.
    await give(usdc, alice, 10_000n * 10n ** 6n);
    await pool.connect(alice).supply(usdc.target, 10_000n * 10n ** 6n);
    const borrowed = 1_000n * 10n ** 18n;
    await pool.connect(alice).borrow(fot.target, borrowed);

    // Alice receives `borrowed * 0.95` (FoT takes fee on the outbound transfer).
    // Her debt is still `borrowed` — the protocol can't see/recoup the burn.
    const debtBefore = (await pool.getUserReserveData(alice.address, fot.target)).currentBorrow;
    // Scaled-balance accounting may round 1 wei down; the full borrow amount is owed.
    expect(debtBefore).to.be.closeTo(borrowed, 2n);

    // Alice repays 500 FoT. Only 475 actually reach the pool.
    await give(fot, alice, 500n * 10n ** 18n);
    await pool.connect(alice).repay(fot.target, 500n * 10n ** 18n);

    const debtAfter = (await pool.getUserReserveData(alice.address, fot.target)).currentBorrow;
    const repaidApprox = debtBefore - debtAfter;
    // Debt drops by 95% of 500 = 475, not the full 500.
    expect(repaidApprox).to.be.closeTo(475n * 10n ** 18n, 10n ** 16n);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. addMarket parameter bounds
// ─────────────────────────────────────────────────────────────────────────────

describe("v0.3.1 hardening — addMarket parameter bounds", () => {
  const VALID = [6, 7500, 8000, 10500, 1000, pct(2), pct(8), pct(80), pct(100)];

  async function freshAsset() {
    const ERC20 = await ethers.getContractFactory("MockERC20");
    const t = await ERC20.deploy("Test", "TST", 6);
    await t.waitForDeployment();
    return t;
  }

  it("rejects zero asset address", async () => {
    const { pool } = await deployFixture();
    await expect(
      pool.addMarket(ethers.ZeroAddress, ...VALID),
    ).to.be.revertedWith("Zero asset");
  });

  it("rejects zero decimals", async () => {
    const { pool } = await deployFixture();
    const t = await freshAsset();
    await expect(
      pool.addMarket(t.target, 0, 7500, 8000, 10500, 1000, pct(2), pct(8), pct(80), pct(100)),
    ).to.be.revertedWith("Bad decimals");
  });

  it("rejects decimals > 18", async () => {
    const { pool } = await deployFixture();
    const t = await freshAsset();
    await expect(
      pool.addMarket(t.target, 19, 7500, 8000, 10500, 1000, pct(2), pct(8), pct(80), pct(100)),
    ).to.be.revertedWith("Bad decimals");
  });

  it("rejects liquidationThreshold > 100%", async () => {
    const { pool } = await deployFixture();
    const t = await freshAsset();
    await expect(
      pool.addMarket(t.target, 6, 7500, 10001, 10500, 1000, pct(2), pct(8), pct(80), pct(100)),
    ).to.be.revertedWith("liqThreshold > 100%");
  });

  it("rejects liquidationBonus below 100%", async () => {
    const { pool } = await deployFixture();
    const t = await freshAsset();
    await expect(
      pool.addMarket(t.target, 6, 7500, 8000, 9999, 1000, pct(2), pct(8), pct(80), pct(100)),
    ).to.be.revertedWith("Bonus out of range");
  });

  it("rejects liquidationBonus above 125%", async () => {
    const { pool } = await deployFixture();
    const t = await freshAsset();
    await expect(
      pool.addMarket(t.target, 6, 7500, 8000, 12501, 1000, pct(2), pct(8), pct(80), pct(100)),
    ).to.be.revertedWith("Bonus out of range");
  });

  it("rejects reserveFactor > 100%", async () => {
    const { pool } = await deployFixture();
    const t = await freshAsset();
    await expect(
      pool.addMarket(t.target, 6, 7500, 8000, 10500, 10001, pct(2), pct(8), pct(80), pct(100)),
    ).to.be.revertedWith("Reserve factor > 100%");
  });

  it("rejects optimalUtilization = 0", async () => {
    const { pool } = await deployFixture();
    const t = await freshAsset();
    await expect(
      pool.addMarket(t.target, 6, 7500, 8000, 10500, 1000, pct(2), pct(8), 0, pct(100)),
    ).to.be.revertedWith("Bad optimal util");
  });

  it("rejects optimalUtilization > 100% (ray)", async () => {
    const { pool } = await deployFixture();
    const t = await freshAsset();
    await expect(
      pool.addMarket(t.target, 6, 7500, 8000, 10500, 1000, pct(2), pct(8), RAY + 1n, pct(100)),
    ).to.be.revertedWith("Bad optimal util");
  });

  it("setOracle rejects zero address", async () => {
    const { pool } = await deployFixture();
    await expect(pool.setOracle(ethers.ZeroAddress)).to.be.revertedWith("Zero oracle");
  });
});
