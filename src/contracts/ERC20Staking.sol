// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

contract ERC20Staking is Ownable {
    /* ========== STATE VARIABLES ========== */
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public startAt;
    uint256 public endAt;
    uint256 public duration;
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
    /// @notice Set starting timestamp of the staking period.
    function setStartAt(uint256 _startAt) external onlyOwner {
        require(startAt == 0, "Cannot set startAt twice");
        require(_startAt > block.timestamp, "Cannot set startAt in the past");
        startAt = _startAt;
    }

    /// @notice Set ending timestamp of the staking period. Update duration.
    function setEndAt(uint256 _endAt) external onlyOwner {
        require(endAt >= block.timestamp, "Cannot set endAt in the past");
        require(_endAt > startAt, "Cannot set endAt before startAt");
        endAt = _endAt;
        duration = endAt - startAt;
    }

    /// @notice Update reward allocation.
    function updateRewardAllocation(uint256 reward) external onlyOwner {
        require(endAt >= block.timestamp, "Cannot update reward allocation after endAt");
        require(startAt > 0, "Cannot update reward allocation before startAt");
        require(reward > 0, "Cannot update reward allocation to zero");

        require(
            rewardToken.balanceOf(address(this)) >= toDistributeRewards + reward + owedRewards,
            "Cannot update reward allocation to more than the balance of the contract"
        );

        toDistributeRewards += reward;
        rewardRate = toDistributeRewards / duration;
    }

    /// @notice Allows the contract owner to recover any ERC20 token sent to the contract in error except for the staking and reward tokens.
    // TO-DO: remove excess reward tokens from the contract
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(
            tokenAddress != address(stakingToken) && tokenAddress != address(rewardToken),
            "Cannot withdraw the staking or reward tokens"
        );
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        //emit Recovered(tokenAddress, tokenAmount);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ========== VIEW FUNCTIONS ========== */
    /// @notice Returns the last time rewards were applicable
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < endAt ? Math.max(startAt, block.timestamp) : endAt;
    }
}
