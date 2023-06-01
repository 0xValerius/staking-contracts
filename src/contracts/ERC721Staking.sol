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
}
