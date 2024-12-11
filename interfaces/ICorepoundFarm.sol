// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ICorepoundVault} from "./ICorepoundVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICorepoundFarm {
    // User info
    struct UserInfo {
        uint256 amount;
        mapping(IERC20 => uint256) rewardDebt;
    }

    // User's rewards
    struct UserRewardInfoModel {
        IERC20 token;
        uint256 debt;
    }

    // The user of pool info
    struct DepositedPoolUserInfoModel {
        uint256 pid;
        uint256 amount;
        UserRewardInfoModel[] rewards;
    }

    // Pool info
    struct PoolInfoModel {
        address assets;
        uint256 allocPoint;
        uint256 amount;
        uint256 lastRewardTime;
        mapping(IERC20 => uint256) acctPerShare;
        ICorepoundVault vault;
        RewardInfoModel[] rewards;
    }

    // Pool info for UI
    struct PoolInfoUIModel {
        address assets;
        uint256 allocPoint;
        uint256 amount;
        uint256 lastRewardTime;
        AcctPerShareInfo[] acctPerShare;
        ICorepoundVault vault;
        RewardInfoModel[] rewards;
    }

    // Account per share
    struct AcctPerShareInfo {
        IERC20 token;
        uint256 acctPerShare;
    }

    // Reward info
    struct RewardInfoModel {
        IERC20 token;
        uint256 tokenRate;
    }

    // Pool TVL
    struct PoolTVLModel {
        uint256 pid;
        address assets;
        uint256 tvl;
    }

    // User revenue info
    struct UserRevenueInfoModel {
        IERC20 token;
        uint256 totalUserRevenue;
    }
}
