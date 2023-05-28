// SPDX-License-Identifier: MIT

/*
      .oooo.               oooooo     oooo           oooo                      o8o                       
     d8P'`Y8b               `888.     .8'            `888                      `"'                       
    888    888 oooo    ooo   `888.   .8'    .oooo.    888   .ooooo.  oooo d8b oooo  oooo  oooo   .oooo.o 
    888    888  `88b..8P'     `888. .8'    `P  )88b   888  d88' `88b `888""8P `888  `888  `888  d88(  "8 
    888    888    Y888'        `888.8'      .oP"888   888  888ooo888  888      888   888   888  `"Y88b.  
    `88b  d88'  .o8"'88b        `888'      d8(  888   888  888    .o  888      888   888   888  o.  )88b 
     `Y8bd8P'  o88'   888o       `8'       `Y888""8o o888o `Y8bod8P' d888b    o888o  `V88V"V8P' 8""888P' 
*/

pragma solidity ^0.8.17;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

/**
 * @title ERC20Staking
 * @author 0xValerius
 * @notice This contract allows users to stake ERC20 tokens and earn rewards.
 * @dev The contract owner can set the reward allocation and recover erroneously sent tokens.
 * The staking period is defined by a start and end timestamp, which can only be set once by the contract owner.
 * Users can stake tokens, withdraw their stake, and claim rewards at any time. Unclaimed rewards are stored in the contract.
 * This contract uses the OpenZeppelin library for secure math operations and access control.
 */
contract ERC20Staking is Ownable {
    /* ========== STATE VARIABLES ========== */
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public startAt;
    uint256 public endAt;
    uint256 public rewardRate;
    uint256 public rewardPerTokenStored;
    uint256 public lastUpdateTime;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    // balance of this contract = toDistributeRewards + owedRewards

    uint256 public totalStaked;
    uint256 public toDistributeRewards;
    uint256 public owedRewards;
    mapping(address => uint256) public balances;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    /* ========== ADMIN FUNCTIONS ========== */
    /**
     * @notice Set the starting timestamp of the staking period.
     * @dev Can only be called by the contract owner and only once.
     * The starting timestamp must be in the future.
     * @param _startAt The starting timestamp of the staking period.
     */
    function setStartAt(uint256 _startAt) external onlyOwner {
        require(startAt == 0, "Cannot set startAt twice");
        require(_startAt > block.timestamp, "Cannot set startAt in the past");
        startAt = _startAt;
    }

    /**
     * @notice Set the ending timestamp of the staking period.
     * @dev Can only be called by the contract owner.
     * The ending timestamp must be equal to or later than the current time and later than the starting timestamp.
     * The reward rate is recalculated based on the new ending timestamp.
     * Emits a {ChangedEndAt} event.
     * @param _endAt The ending timestamp of the staking period.
     */
    function setEndAt(uint256 _endAt) external onlyOwner updateReward(address(0)) {
        require(_endAt >= block.timestamp, "Cannot set endAt in the past");
        require(_endAt > startAt, "Cannot set endAt before startAt");
        endAt = _endAt;
        rewardRate = toDistributeRewards / (_endAt - lastTimeRewardApplicable());
        emit ChangedEndAt(_endAt);
    }

    /**
     * @notice Increase the reward allocation.
     * @dev Can only be called by the contract owner.
     * The new reward allocation must not exceed the contract balance.
     * The reward rate is recalculated based on the new reward allocation.
     * Emits a {UpdatedRewardAllocation} event.
     * @param reward The amount of reward tokens to add to the allocation.
     */
    function increaseRewardAllocation(uint256 reward) external onlyOwner updateReward(address(0)) {
        uint256 _endAt = endAt;
        //require(_endAt >= block.timestamp, "Cannot update reward allocation after endAt");
        //require(startAt > 0, "Cannot update reward allocation before startAt");
        require(
            rewardToken.balanceOf(address(this)) >= toDistributeRewards + reward + owedRewards,
            "Cannot update reward allocation to more than the balance of the contract"
        );

        toDistributeRewards += reward;
        rewardRate = toDistributeRewards / (_endAt - lastTimeRewardApplicable());
        emit UpdatedRewardAllocation(toDistributeRewards, rewardRate);
    }

    /**
     * @notice Decrease the reward allocation.
     * @dev Can only be called by the contract owner.
     * The new reward allocation must not be less than the total owed rewards.
     * The reward rate is recalculated based on the new reward allocation.
     * Emits a {UpdatedRewardAllocation} event.
     * @param reward The amount of reward tokens to subtract from the allocation.
     */
    function decreaseRewardAllocation(uint256 reward) external onlyOwner updateReward(address(0)) {
        uint256 _endAt = endAt;
        //require(_endAt >= block.timestamp, "Cannot update reward allocation after endAt");
        //require(startAt > 0, "Cannot update reward allocation before startAt");
        require(
            rewardToken.balanceOf(address(this)) - reward >= owedRewards,
            "Cannot decrease reward allocation to less than the owed rewards"
        );

        toDistributeRewards -= reward;
        rewardRate = toDistributeRewards / (_endAt - lastTimeRewardApplicable());
        emit UpdatedRewardAllocation(toDistributeRewards, rewardRate);
    }

    /**
     * @notice Recover any ERC20 token sent to the contract by mistake.
     * @dev Can only be called by the contract owner.
     * Does not allow recovering the staking token.
     * If the token to recover is the reward token, does not allow recovering more than the excess amount in the contract.
     * Emits a {Recovered} event.
     * @param tokenAddress The address of the token to recover.
     * @param tokenAmount The amount of tokens to recover.
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner updateReward(address(0)) {
        require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");

        if (tokenAddress == address(rewardToken)) {
            require(
                tokenAmount <= rewardToken.balanceOf(address(this)) - owedRewards - toDistributeRewards,
                "Cannot remove more rewardToken than the excess amount present in the contract."
            );
            rewardToken.transfer(msg.sender, tokenAmount);
        } else {
            IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        }
        emit Recovered(tokenAddress, tokenAmount);
    }

    /* ========== MODIFIERS ========== */
    /**
     * @dev Modifier that updates the rewards for an account before executing a function.
     * The reward per token is updated and stored, and the last update time is set to the last time rewards were applicable.
     * If the account is not the zero address, the rewards and paid reward per token for the account are updated.
     * This modifier is used before stake, withdraw, and claimReward functions, and all admin functions that change reward parameters.
     *
     * @param account The account for which to update the rewards. If this is the zero address, no rewards are updated for any account.
     */
    modifier updateReward(address account) {
        // update distributed rewards when totalStaked != 0, otherwise no rewards are distributed
        if (totalStaked != 0) {
            uint256 released = (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate;
            owedRewards += released;
            toDistributeRewards -= released;
        }

        // updated reward per token
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /**
     * @notice Stake ERC20 tokens to earn rewards.
     * @dev Requires the staking amount to be greater than zero.
     * User's staking balance and the total staked amount are increased by the staking amount.
     * Staking tokens are transferred from the user to this contract.
     * Emits a {Staked} event.
     * @param amount The amount of staking tokens to stake.
     */
    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        totalStaked += amount;
        balances[msg.sender] += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Withdraw staked ERC20 tokens.
     * @dev Requires the withdrawal amount to be greater than zero.
     * User's staking balance and the total staked amount are decreased by the withdrawal amount.
     * Staking tokens are transferred from this contract to the user.
     * Emits a {Withdrawn} event.
     * @param amount The amount of staking tokens to withdraw.
     */
    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        totalStaked -= amount;
        balances[msg.sender] -= amount;
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Claim earned rewards without unstaking.
     * @dev The user's reward is set to zero and subtracted from the total owed rewards.
     * Reward tokens are transferred from this contract to the user.
     * Emits a {RewardPaid} event.
     */
    function claimReward() public updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            owedRewards -= reward;
            rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /**
     * @notice Unstake all staked tokens and claim earned rewards.
     * @dev This is a shortcut function that calls {withdraw} and {claimReward}.
     */
    function exit() external {
        withdraw(balances[msg.sender]);
        claimReward();
    }

    /* ========== VIEW FUNCTIONS ========== */
    /**
     * @notice Get the last time when rewards were applicable.
     * @return The minimum between the current timestamp and the staking period end timestamp,
     * or the staking period start timestamp if it's later than the current timestamp.
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < endAt ? Math.max(startAt, block.timestamp) : endAt;
    }

    /**
     * @notice Get the reward per token until the last time rewards were applicable.
     * @return If there are no staked tokens, returns the stored reward per token.
     * Otherwise, returns the sum of the stored reward per token and the newly accumulated reward per token.
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStaked;
    }

    /**
     * @notice Get the amount of rewards earned by an account.
     * @param account The address of the account.
     * @return The amount of rewards earned by the account.
     */
    function earned(address account) public view returns (uint256) {
        return (balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    /* ========== EVENTS ========== */
    event ChangedEndAt(uint256);
    event UpdatedRewardAllocation(uint256 newToDistribute, uint256 newRewardRate);
    event Recovered(address token, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}
