// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TransferTokenHelper} from "../comm/TransferTokenHelper.sol";
import {ICorepoundStrategy} from "../interfaces/IStrategy.sol";
import {ICorepoundVault} from "../interfaces/ICorepoundVault.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CorepoundVault is ICorepoundVault, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // @dev Amount of underlying tokens provided by the user.
    struct VaultUserInfo {
        uint256 amount;
    }

    // Vault strategy
    ICorepoundStrategy public strategy;

    // Vault asset token
    IERC20 public assets;

    // Total assets in the vault
    uint256 public totalAssets;

    // MainChef address
    address public farmAddress;

    // CORE address
    address public coreAddress;

    // User map
    mapping(address => VaultUserInfo) public userInfoMap;

    // User list
    address[] public userList;

    /// @notice Emitted when user deposit assets
    /// @param user Address that deposited
    /// @param amount Deposit amount from user
    event EventDepositTokenToVault(address indexed user, uint256 amount);

    /// @notice Emitted when user withdraw assets
    /// @param user Address that withdraw
    /// @param amount Withdrawal amount by user
    event EventWithdrawTokenFromVault(address indexed user, uint256 amount);

    /// @notice Emitted when set the strategy
    event EventSetVaultStrategy(address indexed strategyAddr);

    /// @notice Emitted when set the mainChef
    event EventSetMainChef(address indexed mainChef);

    /// @notice Emitted when set the CORE address
    event EventSetCoreAddress(address indexed _ethAddr);

    /// @notice Emitted when set the assets address
    event EventSetAssets(address indexed _assetsAddr);

    /// @notice Initialize the pool
    /// @param _assets The pool asset
    /// @param _coreAddress The CORE address
    /// @param _farmAddr The mainChef address
    function initialize(
        IERC20 _assets,
        address _coreAddress,
        address _farmAddr
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        assets = _assets;
        coreAddress = _coreAddress;
        farmAddress = _farmAddr;
    }

    /// @notice Set vault strategy
    /// @param _strategy Strategy address
    function setVaultStrategy(ICorepoundStrategy _strategy) external onlyOwner {
        strategy = _strategy;

        if (address(_strategy) != address(0)) {
            if (address(assets) != coreAddress) {
                IERC20(assets).approve(address(_strategy), 0);
                IERC20(assets).approve(address(_strategy), type(uint256).max);
                transferERC20ToStrategy();
            } else {
                transferNativeToStrategy();
            }
        }

        emit EventSetVaultStrategy(address(_strategy));
    }

    /// @notice Set the mainChef
    /// @param _farmAddr The mainChef address
    function setFarmAddress(address _farmAddr) external onlyOwner {
        require(_farmAddr != address(0), "farm address cannot be address 0");
        farmAddress = _farmAddr;

        emit EventSetMainChef(address(_farmAddr));
    }

    /// @notice Set CORE address
    /// @param _coreAddress CORE address
    function setCoreAddress(address _coreAddress) external onlyOwner {
        coreAddress = _coreAddress;

        emit EventSetCoreAddress(_coreAddress);
    }

    /// @notice Set the assets of the vault
    /// @param _assets The assets of the vault
    function setAssets(address _assets) external onlyOwner {
        assets = IERC20(_assets);

        emit EventSetAssets(address(_assets));
    }

    /// @notice Return vault pool balance only (strategy balance not included)
    function vaultBalance() external view returns (uint256) {
        return assets.balanceOf(address(this));
    }

    /// @notice Return vault balance, included the strategy balance if has
    function balance() public view returns (uint256) {
        if (address(assets) == coreAddress) {
            if (address(strategy) != address(0)) {
                return address(this).balance + ICorepoundStrategy(strategy).balanceOf();
            } else {
                return address(this).balance;
            }
        } else {
            if (address(strategy) != address(0)) {
                return assets.balanceOf(address(this)) + ICorepoundStrategy(strategy).balanceOf();
            } else {
                return assets.balanceOf(address(this));
            }
        }
    }

    /// @notice Return users list that interact with the vault
    function getVaultUserList() public view returns (address[] memory) {
        return userList;
    }

    /// @notice Deposit assets to the vault
    /// @param _userAddr User address
    /// @param _amount Deposit amount
    function depositTokenToVault(address _userAddr, uint256 _amount) public payable nonReentrant returns (uint256){
        require(msg.sender == farmAddress, "!mainChef");
        require(_userAddr != address(0), "user address cannot be zero address");

        if (address(strategy) != address(0)) {
            strategy.beforeDeposit();
        }

        uint256 _depositAmount;
        if (address(assets) == coreAddress) {
            _depositAmount = _depositNative(_userAddr, msg.value);
        } else {
            _depositAmount = _deposit(_userAddr, farmAddress, _amount);
        }

        userList.push(_userAddr);
        emit EventDepositTokenToVault(_userAddr, _depositAmount);

        return _depositAmount;
    }

    /// @dev Process CORE deposit
    function _depositNative(address _userAddr, uint256 _amount) private returns (uint256){
        VaultUserInfo storage _userInfo = userInfoMap[_userAddr];

        _userInfo.amount = _userInfo.amount + _amount;
        totalAssets = totalAssets + _amount;

        // deposit to strategy if has
        if (address(strategy) != address(0)) {
            ICorepoundStrategy(strategy).depositNative{value: _amount}(address(this));
        }

        return _amount;
    }

    /// @dev Process ERC20 deposit
    function _deposit(address _userAddr, address _farmAddr, uint256 _amount) private returns (uint256){
        VaultUserInfo storage _userInfo = userInfoMap[_userAddr];

        uint256 _poolBalance = balance();
        TransferTokenHelper.safeTokenTransferFrom(address(assets), _farmAddr, address(this), _amount);

        uint256 _afterPoolBalance = balance();
        uint256 _depositAmount = _afterPoolBalance - _poolBalance;

        _userInfo.amount = _userInfo.amount + _depositAmount;
        totalAssets = totalAssets + _depositAmount;

        // deposit to strategy if has
        if (address(strategy) != address(0)) {
            ICorepoundStrategy(strategy).deposit(address(this), _amount);
        }

        return _depositAmount;
    }

    /// @notice Withdraw assets from the vault
    /// @param _userAddr User Address
    /// @param _amount Withdrawal Amount
    function withdrawTokenFromVault(address _userAddr, uint256 _amount) public nonReentrant returns (uint256){
        require(msg.sender == farmAddress, "!mainChef");
        require(_userAddr != address(0), "User address cannot be zero address");

        VaultUserInfo storage _userInfo = userInfoMap[_userAddr];
        require(_userInfo.amount >= _amount, "Insufficient balance");

        _userInfo.amount = _userInfo.amount - _amount;
        totalAssets = totalAssets - _amount;

        if (address(assets) == coreAddress) {
            // withdraw from strategy if has
            if (address(strategy) != address(0)) {
                ICorepoundStrategy(strategy).withdrawNative(_userAddr, _amount);
            } else {
                TransferTokenHelper.safeTransferNative(_userAddr, _amount);
            }

            emit EventWithdrawTokenFromVault(_userAddr, _amount);
            return _amount;
        } else {
            // withdraw from strategy if has
            if (address(strategy) != address(0)) {
                ICorepoundStrategy(strategy).withdraw(_userAddr, _amount);
            } else {
                TransferTokenHelper.safeTokenTransfer(address(assets), _userAddr, _amount);
            }

            emit EventWithdrawTokenFromVault(_userAddr, _amount);
            return _amount;
        }
    }

    // @dev Transfer CORE to strategy
    function transferNativeToStrategy() internal {
        if (address(this).balance > 0) {
            TransferTokenHelper.safeTransferNative(address(strategy), address(this).balance);
        }
    }

    /// @dev Transfer ERC20 to strategy
    function transferERC20ToStrategy() internal {
        uint256 tokenBal = assets.balanceOf(address(this));
        if (tokenBal > 0) {
            assets.safeTransfer(address(strategy), tokenBal);
        }
    }

    receive() external payable {}
}
