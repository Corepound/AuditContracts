// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ICoreHelper} from "../interfaces/ICoreHelper.sol";

contract CoreHelper {
    receive() external payable {
    }

    function withdrawCore(address _addr, address _to, uint256 _amount) public {
        ICoreHelper(_addr).withdraw(_amount);
        (bool success,) = _to.call{value: _amount}(new bytes(0));
        require(success, 'Withdraw CORE FAILED!!');
    }
}

