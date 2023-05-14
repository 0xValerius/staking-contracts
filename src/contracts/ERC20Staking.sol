// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract ERC20Staking is Ownable {
    /* ========== STATE VARIABLES ========== */
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public startAt;
    uint256 public endAt;
    uint256 public rewardRate;
    uint256 public rewardsDuration;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 public totalSupply;
    mapping(address => uint256) public balances;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }
}
