// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract SynthetixStaking is Ownable {
    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public endAt;
    uint256 public rewardRate;
    uint256 public rewardsDuration;
    uint256 public rewardPerTokenStored;
    uint256 public lastUpdateTime;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 public totalSupply;
    mapping(address => uint256) public balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    /* ========== VIEWS ========== */

    /// @notice Returns the last time rewards were applicable.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < endAt ? block.timestamp : endAt;
    }

    /// @notice Returns the reward per token earned by staking until the last time rewards were applicable.
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalSupply;
    }

    /// @notice Returns the amount of rewards earned by an account.
    function earned(address account) public view returns (uint256) {
        return (balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    /* ========== MODIFIERS ========== */

    /// @notice Updates the reward variables for an account before executing a function.
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Allows an account to stake tokens and earn rewards.
    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        totalSupply += amount;
        balances[msg.sender] += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /// @notice Allows an account to withdraw their staked tokens and claim their rewards.
    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        totalSupply -= amount;
        balances[msg.sender] -= amount;
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Allows an account to claim their rewards without withdrawing their staked tokens.
    function getReward() public updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Allows an account to withdraw their staked tokens and claim their rewards in a single transaction.
    function exit() external {
        withdraw(balances[msg.sender]);
        getReward();
    }

    /* ========== ONLYOWNER FUNCTIONS ========== */

    /// @notice Notifies the contract that a reward has been added for the current reward period. *
    /// It updates the reward rate and the last time rewards were applicable based on the amount of the reward and the duration of the reward period. *
    /// This function can only be called by the contract owner.
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= endAt) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = endAt - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        uint256 balance = rewardToken.balanceOf(address(this));
        require(rewardRate <= balance / rewardsDuration, "Provided reward too high");

        lastUpdateTime = block.timestamp;
        endAt = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    /// @notice Allows the contract owner to change the duration of the reward period.
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > endAt,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /// @notice Allows the contract owner to recover any ERC20 token sent to the contract in error except for the staking and reward tokens.
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(
            tokenAddress != address(stakingToken) && tokenAddress != address(rewardToken),
            "Cannot withdraw the staking or reward tokens"
        );
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
}
