// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CorepoundToken is ERC20, Ownable {

    uint256 public constant TOTAL_SUPPLY = 10_000_000 * 1e18;

    constructor(string memory name, string memory symbol, address _owner)
    ERC20(name, symbol)
    Ownable(_owner){
        _mint(_owner, TOTAL_SUPPLY);
    }
}
