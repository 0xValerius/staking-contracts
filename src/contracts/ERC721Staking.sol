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
import {IERC721A} from "ERC721A/IERC721A.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

/**
 * @title ERC721Staking
 * @author 0xValerius
 * @notice This contract allows users to stake ERC721 tokens and earn rewards as ERC20 tokens. Inspired by the Synthetix staking contract.
 * @dev The contract owner can set the reward allocation and recover erroneously sent ERC20 tokens.
 * The staking period is defined by a start and end timestamp, which can only be set once by the contract owner.
 * Users can stake items of a specific NFT collection, withdraw their stake, and claim rewards at any time. Unclaimed rewards are stored in the contract.
 * This contract uses the OpenZeppelin library for secure math operations and access control.
 * This contract uses the ERC721A library for secure and efficient NFT operations.
 */
contract ERC721Staking is Ownable {
    /* ========== STATE VARIABLES ========== */
    IERC721A public immutable nftCollection;
    IERC20 public immutable rewardToken;

    uint256 public startAt;
    uint256 public endAt;
    uint256 public rewardRate;
    uint256 public rewardPerTokenStored;
    uint256 public lastUpdateTime;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(uint256 => address) public stakedAssets;
    mapping(address => uint256[]) private tokensStaked;
    mapping(uint256 => uint256) public tokenIdToIndex;

    uint256 public totalStaked;
    uint256 public toDistributeRewards;
    uint256 public owedRewards;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _nftCollection, address _rewardToken) {
        nftCollection = IERC721A(_nftCollection);
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
     * Emits a {RecoveredERC20} event.
     * @param tokenAddress The address of the token to recover.
     * @param tokenAmount The amount of tokens to recover.
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner updateReward(address(0)) {
        if (tokenAddress == address(rewardToken)) {
            require(
                tokenAmount <= rewardToken.balanceOf(address(this)) - owedRewards - toDistributeRewards,
                "Cannot remove more rewardToken than the excess amount present in the contract."
            );
            rewardToken.transfer(msg.sender, tokenAmount);
        } else {
            IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        }
        emit RecoveredERC20(tokenAddress, tokenAmount);
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
        if (totalStaked != 0) {
            uint256 released = (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate;
            owedRewards += released;
            toDistributeRewards -= released;
        }

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
     * @notice Stake ERC721 tokens (NFTs) in the contract.
     * @dev Allows users to stake multiple NFTs in the contract.
     * @param tokenIds Array of token IDs to stake.
     */
    function stake(uint256[] memory tokenIds) external updateReward(msg.sender) {
        require(tokenIds.length != 0, "Staking: no tokenIds provided.");
        uint256 amount = tokenIds.length;
        for (uint256 i = 0; i < amount; i++) {
            stakedAssets[tokenIds[i]] = msg.sender;
            tokensStaked[msg.sender].push(tokenIds[i]);
            tokenIdToIndex[tokenIds[i]] = tokensStaked[msg.sender].length - 1;
            nftCollection.transferFrom(msg.sender, address(this), tokenIds[i]);
        }
        totalStaked += amount;
        emit Staked(msg.sender, tokenIds);
    }

    /**
     * @notice Withdraw staked ERC721 tokens (NFTs) from the contract.
     * @dev Allows users to withdraw multiple staked NFTs from the contract.
     * @param tokenIds Array of token IDs to withdraw.
     */
    function withdraw(uint256[] memory tokenIds) public updateReward(msg.sender) {
        require(tokenIds.length != 0, "Withdrawing: no tokenIds provided.");
        uint256 amount = tokenIds.length;

        for (uint256 i = 0; i < amount; i++) {
            require(stakedAssets[tokenIds[i]] == msg.sender, "Withdrawing: token not owned by user.");
            stakedAssets[tokenIds[i]] = address(0);
            uint256[] storage userTokens = tokensStaked[msg.sender];
            uint256 index = tokenIdToIndex[tokenIds[i]];
            uint256 lastTokenIdIndex = userTokens.length - 1;
            if (index != lastTokenIdIndex) {
                uint256 lastTokenId = userTokens[lastTokenIdIndex];
                userTokens[index] = lastTokenId;
                tokenIdToIndex[lastTokenId] = index;
            }
            userTokens.pop();
            nftCollection.transferFrom(address(this), msg.sender, tokenIds[i]);
        }
        totalStaked -= amount;
        emit Withdrawn(msg.sender, tokenIds);
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
     * @notice Unstake all staked ERC721 tokens (NFTs) and claim earned rewards.
     * @dev This is a shortcut function that calls {withdraw} and {claimReward}.
     */
    function exit() external {
        withdraw(tokensStaked[msg.sender]);
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
        return (tokensStaked[account].length * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18
            + rewards[account];
    }

    /**
     * @notice Get the staking information for a user.
     * @dev Returns the staking information for a user.
     * @param account Address of the user.
     * @return _tokensStaked and _claimableRewards, an array of staked token IDs and the total claimable rewards for a user.
     */
    function userStakeInfo(address account)
        public
        view
        returns (uint256[] memory _tokensStaked, uint256 _claimableRewards)
    {
        _tokensStaked = tokensStaked[account];
        _claimableRewards = earned(account);
    }

    /* ========== EVENTS ========== */
    event ChangedEndAt(uint256);
    event UpdatedRewardAllocation(uint256 newToDistribute, uint256 newRewardRate);
    event RecoveredERC20(address token, uint256 amount);
    event Staked(address indexed user, uint256[] tokenIds);
    event Withdrawn(address indexed user, uint256[] tokenIds);
    event RewardPaid(address indexed user, uint256 reward);
}
