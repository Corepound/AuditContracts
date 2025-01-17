// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CorepoundToken is ERC20 {

    uint256 public constant TOTAL_SUPPLY = 10_000_000 * 1e18;

    constructor(string memory name, string memory symbol)
    ERC20(name, symbol){
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
