// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC721A} from "ERC721A/IERC721A.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

contract ERC721AStaking is Ownable {
    /* ========== STATE VARIABLES ========== */
    IERC721A public immutable nftCollection;
    IERC20 public immutable rewardToken;

    uint256 public startAt;
    uint256 public endAt;
    uint256 public rewardRate;
    uint256 public rewardPerNFTStored;
    uint256 public lastUpdateTime;

    mapping(address => uint256) public userRewardPerItemPaid;
    mapping(address => uint256) public rewards;

    uint256 public totalStakedItem;
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
        emit Recovered(tokenAddress, tokenAmount);
    }

    // add a function recover wrongly sent NFT
}
