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

    // add other state variables here to track NFT ownership

    /* ========== CONSTRUCTOR ========== */
    constructor(address _nftCollection, address _rewardToken) {
        nftCollection = IERC721A(_nftCollection);
        rewardToken = IERC20(_rewardToken);
    }

    /* ========== ADMIN FUNCTIONS ========== */
    function setStartAt(uint256 _startAt) external onlyOwner {
        require(startAt == 0, "Cannot set startAt twice");
        require(_startAt > block.timestamp, "Cannot set startAt in the past");
        startAt = _startAt;
    }

    function setEndAt(uint256 _endAt) external onlyOwner updateReward(address(0)) {
        require(_endAt >= block.timestamp, "Cannot set endAt in the past");
        require(_endAt > startAt, "Cannot set endAt before startAt");
        endAt = _endAt;
        rewardRate = toDistributeRewards / (_endAt - lastTimeRewardApplicable());
        emit ChangedEndAt(_endAt);
    }

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

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            owedRewards -= reward;
            rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(tokensStaked[msg.sender]);
        claimReward();
    }

    /* ========== VIEW FUNCTIONS ========== */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < endAt ? Math.max(startAt, block.timestamp) : endAt;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        return (tokensStaked[account].length * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18
            + rewards[account];
    }

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
