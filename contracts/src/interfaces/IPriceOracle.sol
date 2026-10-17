// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Prices are denominated in USD with 8 decimals (e.g. $1 = 1e8).
interface IPriceOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

