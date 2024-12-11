// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library TransferTokenHelper {
    function safeTokenApprove(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeCall(IERC20.approve, (to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferTokenHelper -> safeTokenApprove: Approve Token FAILED');
    }

    function safeTokenTransfer(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeCall(IERC20.transfer, (to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferTokenHelper -> safeTokenTransfer: Transfer Token FAILED');
    }

    function safeTokenTransferFrom(address token, address from, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeCall(IERC20.transferFrom, (from, to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferTokenHelper -> safeTokenTransferFrom: Transfer Token From Origin FAILED');
    }

    function safeTransferNative(address to, uint value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, 'TransferTokenHelper -> safeTransferNative: Transfer Native FAILED');
    }
}
