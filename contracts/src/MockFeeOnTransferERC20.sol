// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockFeeOnTransferERC20
/// @notice Test-only ERC20 that deducts a configurable fee on every transfer.
/// Used to verify the LendingPool's fee-on-transfer hardening (v0.3.1):
/// supply/repay/liquidate must credit the actually-received amount, not the
/// requested amount.
contract MockFeeOnTransferERC20 is ERC20 {
    uint8 private immutable _decimals;
    uint256 public feeBps; // e.g. 500 = 5% fee burned on every transfer

    constructor(string memory name_, string memory symbol_, uint8 dec, uint256 feeBps_)
        ERC20(name_, symbol_)
    {
        _decimals = dec;
        feeBps = feeBps_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Take `feeBps` off every transfer (including transferFrom). The fee
    /// is burned, so the recipient receives `amount * (1 - feeBps/10000)`.
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(0) || to == address(0) || feeBps == 0) {
            super._update(from, to, value);
            return;
        }
        uint256 fee = (value * feeBps) / 10000;
        uint256 net = value - fee;
        super._update(from, to, net);
        if (fee > 0) {
            super._update(from, address(0), fee); // burn the fee
        }
    }
}
