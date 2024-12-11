// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TransferTokenHelper} from "../comm/TransferTokenHelper.sol";
import {ICorepoundFarm} from "../interfaces/ICorepoundFarm.sol";
import {ICorepoundVault} from "../interfaces/ICorepoundVault.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract CorepoundFarm is ICorepoundFarm, Initializable, OwnableUpgradeable,
ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Farm start timestamp
    uint256 public startTime;

    // CORE token address
    address public coreAddress;

    // Total allocation points
    uint256 public totalAllocPoint;

    // Total user revenue
    mapping(IERC20 => uint256) public totalUserRevenue;

    // Reward tokens
    EnumerableSet.AddressSet private rewardTokenSet;

    // Pool info
    PoolInfoModel[] public poolInfoList;

    // Each user stake token
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // User list
    EnumerableSet.AddressSet private userAddrList;
    mapping(uint256 => EnumerableSet.AddressSet) private poolUserList;

    /// @notice Emitted when user deposit assets
    event EventDepositAsset(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when user withdraw assets
    event EventWithdrawAsset(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when set the pool new token per block
    event EventSetPoolTokenRate(uint256 indexed pid, uint256 _rewardIndex,
        uint256 _newTokenRate);

    /// @notice Emitted when set the start timestamp
    event EventSetStartTime(uint256 indexed _startTime);

    /// @notice Emitted when set the Core address
    event EventSetCoreAddress(address indexed _coreAddr);

    receive() external payable {}

    /// @notice Initialize the farm
    /// @param _coreAddress The CORE token address
    function initialize(
        address _coreAddress
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        coreAddress = _coreAddress;
        totalAllocPoint = 0;
    }

    /// @notice Set the token per block
    /// @param _pid The pool id
    /// @param _rewardIndex The reward token index
    /// @param _newTokenRate Token rate per block
    function setPoolTokenRate(uint256 _pid, uint256 _rewardIndex,
        uint256 _newTokenRate) public onlyOwner {

        require(_pid >= 0, "Farm: invalid new pool pid");

        // update the pool
        updateMassPools();

        PoolInfoModel storage pool = poolInfoList[_pid];
        pool.rewards[_rewardIndex].tokenRate = _newTokenRate;

        emit EventSetPoolTokenRate(_pid, _rewardIndex, _newTokenRate);
    }

    /// @notice Set the farm start timestamp
    /// @param _startTime The farm start timestamp(seconds)
    function setStartTime(uint256 _startTime) public onlyOwner {
        require(startTime == 0, "Farm: already started");
        require(_startTime > block.timestamp, "Farm: start timestamp must be in the future");
        require(_startTime <= block.timestamp + 30 days, "Farm: start timestamp too far in the future");

        startTime = _startTime;
        emit EventSetStartTime(_startTime);
    }

    /// @notice Set CORE token address
    /// @param _core The wrapped CORE
    function setCoreAddress(address _core) public onlyOwner {
        coreAddress = _core;
        emit EventSetCoreAddress(_core);
    }

    /// @notice Get total user revenue
    function getTotalUserRevenue() public view returns (UserRevenueInfoModel[] memory) {

        address[] memory rewardTokenList = rewardTokenSet.values();

        UserRevenueInfoModel[] memory totalUserRevenueList = new UserRevenueInfoModel[](rewardTokenList.length);

        // get rewards
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            IERC20 token = IERC20(rewardTokenList[i]);

            totalUserRevenueList[i] = UserRevenueInfoModel({
                token: token,
                totalUserRevenue: totalUserRevenue[token]
            });
        }

        return totalUserRevenueList;
    }

    /// @notice Get user information
    /// @param _pid The pool id
    /// @param _user The user address
    /// @return The amount of user staked and user reward debt
    function getUserInfo(uint256 _pid, address _user) public view returns (uint256, UserRewardInfoModel[] memory){
        UserInfo storage user = userInfo[_pid][_user];
        PoolInfoModel storage pool = poolInfoList[_pid];

        uint256 amount = user.amount;

        UserRewardInfoModel[] memory userRewardInfo = new UserRewardInfoModel[](pool.rewards.length);

        for (uint i = 0; i < pool.rewards.length; i++) {
            userRewardInfo[i] = UserRewardInfoModel({
                token: pool.rewards[i].token,
                debt: user.rewardDebt[pool.rewards[i].token]
            });
        }

        return (amount, userRewardInfo);
    }

    /// @notice Get user information for all deposited pools
    /// @param _user The user address
    /// @return The pool user info
    function getUserDepositedPools(address _user) public view returns (DepositedPoolUserInfoModel[] memory){
        DepositedPoolUserInfoModel[] memory poolUserInfoList = new DepositedPoolUserInfoModel[](poolInfoList.length);

        for (uint i = 0; i < poolInfoList.length; i++) {
            (uint256 _amount, UserRewardInfoModel[] memory _userRewardInfo) = getUserInfo(i, _user);
            poolUserInfoList[i] = DepositedPoolUserInfoModel({
                pid: i,
                amount: _amount,
                rewards: _userRewardInfo
            });
        }

        return poolUserInfoList;
    }

    /// @notice Get pool information
    /// @param _pid The pool id
    /// @return The pool presentation info
    function getPoolInfo(uint256 _pid) public view returns (PoolInfoUIModel memory){
        PoolInfoModel storage pool = poolInfoList[_pid];

        PoolInfoUIModel memory poolModel;

        poolModel.assets = pool.assets;
        poolModel.allocPoint = pool.allocPoint;
        poolModel.amount = pool.amount;
        poolModel.lastRewardTime = pool.lastRewardTime;
        poolModel.vault = pool.vault;
        poolModel.rewards = new RewardInfoModel[](pool.rewards.length);
        poolModel.acctPerShare = new AcctPerShareInfo[](pool.rewards.length);

        for (uint i = 0; i < pool.rewards.length; i++) {
            poolModel.rewards[i] = RewardInfoModel({
                token: pool.rewards[i].token,
                tokenRate: pool.rewards[i].tokenRate
            });

            poolModel.acctPerShare[i] = AcctPerShareInfo({
                token: pool.rewards[i].token,
                acctPerShare: pool.acctPerShare[pool.rewards[i].token]
            });
        }

        return poolModel;
    }

    /// @notice Get the pool count
    function getPoolCount() public view returns (uint256){
        return poolInfoList.length;
    }

    /// @notice Get pool users
    /// @param _pid The pool id
    function getActionUserList(uint256 _pid) external onlyOwner view returns (address[] memory){
        address[] memory userList = poolUserList[_pid].values();
        return userList;
    }

    /// @notice Get single pool TVL
    /// @param _pid The pool id
    function getSinglePoolTvl(uint256 _pid) public view returns (uint256){
        PoolInfoModel storage pool = poolInfoList[_pid];
        return pool.vault.balance();
    }

    /// @notice Get total TVL
    function getTotalTvl() public view returns (PoolTVLModel[] memory){
        uint256 _len = poolInfoList.length;
        PoolTVLModel[] memory _totalPoolTvl = new PoolTVLModel[](_len);

        for (uint256 pid = 0; pid < _len; pid++) {
            uint256 _tvl = getSinglePoolTvl(pid);

            PoolTVLModel memory _pt = PoolTVLModel({
                pid: pid,
                assets: poolInfoList[pid].assets,
                tvl: _tvl
            });

            _totalPoolTvl[pid] = _pt;
        }
        return _totalPoolTvl;
    }

    /// @notice Start to farm
    function startMining() public onlyOwner {
        require(startTime == 0, "Farm: mining already started");

        startTime = block.timestamp;
    }

    /// @notice Add new pool
    /// @param _allocPoints The allocation points
    /// @param _token The pool asset
    /// @param _withUpdate The updated pool flag
    /// @param _vault The vault address
    /// @param _isNative Pool asset native token identifier
    /// @param _rewards The reward tokens
    function addPool(
        uint256 _allocPoints,
        address _token,
        bool _withUpdate,
        address _vault,
        bool _isNative,
        RewardInfoModel[] memory _rewards
    ) external onlyOwner {

        checkDuplicatePool(_token);

        if (_withUpdate) {
            updateMassPools();
        }

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;

        // increase total alloc point
        totalAllocPoint += _allocPoints;

        if (_isNative == false) {
            IERC20(_token).approve(address(_vault), 0);
            IERC20(_token).approve(address(_vault), type(uint256).max);
        }

        PoolInfoModel storage newPool = poolInfoList.push();
        newPool.assets = _token;
        newPool.allocPoint = _allocPoints;
        newPool.amount = 0;
        newPool.lastRewardTime = lastRewardTime;
        newPool.vault = ICorepoundVault(_vault);


        for (uint i = 0; i < _rewards.length; i++) {
            newPool.rewards.push(_rewards[i]);
            newPool.acctPerShare[_rewards[i].token] = 0;
            rewardTokenSet.add(address(_rewards[i].token));
        }
    }

    /// @notice Add new reward token to pool
    /// @param _pid The pool id
    /// @param _rewardToken The new reward token
    /// @param _tokenPerBlock Token yield per block
    function addRewardTokenToPool(uint256 _pid, address _rewardToken, uint256 _tokenPerBlock) public onlyOwner {
        require(_rewardToken != address(0), "Invalid rewardToken");
        require(_tokenPerBlock > 0, "Invalid token per block");

        PoolInfoModel storage pool = poolInfoList[_pid];
        pool.rewards.push(RewardInfoModel({
            token: IERC20(_rewardToken),
            tokenRate: _tokenPerBlock
        }));
        rewardTokenSet.add(_rewardToken);
    }

    /// @notice Remove the reward token from pool
    /// @param _pid The pool id
    /// @param _rewardToken The reward token to remove
    function removeRewardTokenFromPool(uint256 _pid, address _rewardToken) public onlyOwner {
        require(_rewardToken != address(0), "Invalid rewardToken");

        PoolInfoModel storage pool = poolInfoList[_pid];

        IERC20 _removingToken = IERC20(_rewardToken);

        // calculate the removing token rewards and transfer to user
        address[] memory userList = poolUserList[_pid].values();
        for (uint256 i = 0; i < userList.length; i++) {
            address userAddr = userList[i];

            UserInfo storage user = userInfo[_pid][userAddr];

            uint256 _pendingRemovingRewards = getUserPendingRewardToken(_pid, userAddr, _removingToken);
            if (_pendingRemovingRewards > 0) {

                user.rewardDebt[_removingToken] = user.rewardDebt[_removingToken] + _pendingRemovingRewards;
                totalUserRevenue[_removingToken] = totalUserRevenue[_removingToken] + _pendingRemovingRewards;

                safeTokenTransfer(_removingToken, userAddr, _pendingRemovingRewards);
            }
        }

        // find the reward token and remove it
        uint256 rewardLength = pool.rewards.length;

        for (uint256 i = 0; i < rewardLength; i++) {
            if (pool.rewards[i].token == _removingToken) {
                pool.rewards[i] = pool.rewards[rewardLength - 1];
                pool.rewards.pop();

                rewardTokenSet.remove(_rewardToken);
                break;
            }
        }

        // update the pool
        updatePool(_pid);
    }

    /// @notice Update the pool info
    /// @param _pid The pool id
    /// @param _allocPoints The allocation points
    /// @param _withUpdate The updated pool flag
    function setPool(
        uint256 _pid,
        uint256 _allocPoints,
        bool _withUpdate
    ) external onlyOwner {

        if (_withUpdate) {
            updateMassPools();
        }

        totalAllocPoint = totalAllocPoint - poolInfoList[_pid].allocPoint + _allocPoints;

        poolInfoList[_pid].allocPoint = _allocPoints;
    }

    /// @notice Update the pools
    function updateMassPools() public {
        for (uint256 i = 0; i < poolInfoList.length; i++) {
            updatePool(i);
        }
    }

    /// @notice Update the pool
    /// @param _pid The pool id
    function updatePool(uint256 _pid) public {
        PoolInfoModel storage pool = poolInfoList[_pid];

        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        uint256 totalAmount = pool.amount;
        if (totalAmount <= 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 multiplier = getDuration(pool.lastRewardTime, block.timestamp);

        for (uint i = 0; i < pool.rewards.length; i++) {
            RewardInfoModel memory reward = pool.rewards[i];

            uint256 tokenReward = multiplier * (reward.tokenRate) * (pool.allocPoint) / (totalAllocPoint);
            pool.acctPerShare[reward.token] = pool.acctPerShare[reward.token] + (tokenReward * 1e18 / totalAmount);
        }

        pool.lastRewardTime = block.timestamp;
    }

    /// @notice Return the user pending rewards
    /// @param _pid The pool id
    /// @param _user The user address
    /// @param _rewardToken The reward token
    function getUserPendingRewardToken(uint256 _pid, address _user, IERC20 _rewardToken) public view returns (uint256) {
        PoolInfoModel storage pool = poolInfoList[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 acctPerShare = pool.acctPerShare[_rewardToken];
        uint256 totalAmount = pool.amount;

        if (block.timestamp > pool.lastRewardTime && totalAmount > 0) {
            uint256 multiplier = getDuration(pool.lastRewardTime, block.timestamp);

            uint256 tokenReward;
            for (uint i = 0; i < pool.rewards.length; i++) {
                if (pool.rewards[i].token == _rewardToken) {
                    RewardInfoModel memory rewardInfo = pool.rewards[i];
                    tokenReward = multiplier * (rewardInfo.tokenRate) * (pool.allocPoint) / (totalAllocPoint);
                    acctPerShare = acctPerShare + (tokenReward * 1e18 / totalAmount);
                    break;
                }
            }
        }

        uint256 reward = user.amount * acctPerShare / 1e18;
        uint256 _pendingRewards = reward > user.rewardDebt[_rewardToken] ? reward - (user.rewardDebt[_rewardToken]) : 0;
        return _pendingRewards;
    }

    /// @notice Return the user all pending rewards
    /// @param _pid The pool id
    /// @param _user The user address
    function getUserAllPendingRewardTokens(uint256 _pid, address _user) public view returns (UserRewardInfoModel[] memory) {
        require(_user != address(0), "Invalid address");

        PoolInfoModel storage pool = poolInfoList[_pid];

        UserRewardInfoModel[] memory userPendingRewards = new UserRewardInfoModel[](pool.rewards.length);

        for (uint i = 0; i < pool.rewards.length; i++) {
            IERC20 rewardToken = pool.rewards[i].token;

            uint256 pendingRewards = getUserPendingRewardToken(_pid, _user, rewardToken);

            userPendingRewards[i] = UserRewardInfoModel({
                token: rewardToken,
                debt: pendingRewards
            });
        }

        return userPendingRewards;
    }

    /// @notice Calculate the rewards and transfer to user
    /// @param _pid The pool id
    /// @param _user The user address
    function harvestRewards(uint256 _pid, address _user) public {
        require(startTime > 0, "Farm: mining not start!!");
        require(_user != address(0), "Farm: invalid user address");

        UserInfo storage user = userInfo[_pid][_user];
        PoolInfoModel storage pool = poolInfoList[_pid];

        for (uint i = 0; i < pool.rewards.length; i++) {
            IERC20 rewardToken = pool.rewards[i].token;

            uint256 pendingRewards = getUserPendingRewardToken(_pid, _user, rewardToken);

            if (pendingRewards > 0) {
                user.rewardDebt[rewardToken] = user.rewardDebt[rewardToken] + pendingRewards;
                totalUserRevenue[rewardToken] = totalUserRevenue[rewardToken] + pendingRewards;
                safeTokenTransfer(rewardToken, _user, pendingRewards);
            }
        }
    }

    /// @notice Deposit assets to the farm
    /// @param _pid The pool id
    /// @param _amount The amount of assets to deposit
    function depositAssets(uint256 _pid, uint256 _amount) external payable nonReentrant returns (uint){
        require(startTime > 0, "Farm: mining not start!!");

        PoolInfoModel storage pool = poolInfoList[_pid];

        for (uint i = 0; i < pool.rewards.length; i++) {
            require(address(pool.rewards[i].token) != address(0), "invalid pool reward token");
        }

        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        // process rewards
        if (user.amount > 0) {
            harvestRewards(_pid, msg.sender);
        }

        // process Native
        if (address(pool.assets) == coreAddress) {
            if (msg.value > 0) {
                _amount = _amount + msg.value;
            }
        } else {
            require(msg.value == 0, "Deposit invalid token");

            if (_amount > 0) {
                TransferTokenHelper.safeTokenTransferFrom(address(pool.assets), address(msg.sender), address(this), _amount);
            }
        }

        if (_amount > 0) {
            pool.amount = pool.amount + _amount;
            user.amount = user.amount + _amount;
        }

        if (user.amount > 0) {
            for (uint i = 0; i < pool.rewards.length; i++) {
                IERC20 rewardToken = pool.rewards[i].token;
                user.rewardDebt[rewardToken] = user.amount * (pool.acctPerShare[rewardToken]) / (1e18);
            }
        }


        if (address(pool.assets) == coreAddress) {
            _amount = pool.vault.depositTokenToVault{value: _amount}(msg.sender, 0);
        } else {
            _amount = pool.vault.depositTokenToVault(msg.sender, _amount);
        }

        poolUserList[_pid].add(msg.sender);

        emit EventDepositAsset(msg.sender, _pid, _amount);
        return 0;
    }

    /// @notice Withdraw assets from the farm
    /// @param _pid The pool id
    /// @param _amount The amount of assets to withdraw
    function withdrawAssets(uint256 _pid, uint256 _amount) external nonReentrant returns (uint){
        require(startTime > 0, "Farm: mining not start!!");

        PoolInfoModel storage pool = poolInfoList[_pid];

        for (uint i = 0; i < pool.rewards.length; i++) {
            require(address(pool.rewards[i].token) != address(0), "invalid pool reward token");
        }

        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Farm: withdraw amount exceeds balance");

        updatePool(_pid);

        // process rewards
        harvestRewards(_pid, msg.sender);

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.amount = pool.amount - _amount;
        }

        for (uint i = 0; i < pool.rewards.length; i++) {
            IERC20 rewardToken = pool.rewards[i].token;
            user.rewardDebt[rewardToken] = user.amount * (pool.acctPerShare[rewardToken]) / (1e18);
        }

        pool.vault.withdrawTokenFromVault(msg.sender, _amount);

        emit EventWithdrawAsset(msg.sender, _pid, _amount);
        return 0;
    }

    /// @dev Get the duration
    function getDuration(uint256 _from, uint256 _to) public pure returns (uint256){
        return _to - _from;
    }

    /// @notice Set the pool vault
    /// @param _pid The pool id
    /// @param _vault The vault address
    function setPoolVault(
        uint256 _pid,
        ICorepoundVault _vault
    ) external onlyOwner {

        poolInfoList[_pid].vault = _vault;
        IERC20(poolInfoList[_pid].assets).approve(address(poolInfoList[_pid].vault), 0);
        IERC20(poolInfoList[_pid].assets).approve(address(poolInfoList[_pid].vault), type(uint256).max);
    }

    /// @notice Check the pool created or not
    function checkDuplicatePool(address _token) internal view {
        uint _existed = 0;

        for (uint256 i = 0; i < poolInfoList.length; i++) {
            if (address(poolInfoList[i].assets) == _token) {
                _existed = 1;
                break;
            }
        }

        require(_existed == 0, "Farm: pool already existed");
    }

    /// @dev Transfer the reward to user
    /// @param token The assets
    /// @param _user The user address
    /// @param _amount The amount of assets to transfer
    function safeTokenTransfer(IERC20 token, address _user, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        if (_amount > tokenBal) {
            token.safeTransfer(_user, tokenBal);
        } else {
            token.safeTransfer(_user, _amount);
        }
    }
}
