// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library SafeTransfer {
    error TransferFailed();

    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory result) =
            token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!ok || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TransferFailed();
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory result) =
            token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        if (!ok || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TransferFailed();
        }
    }
}

