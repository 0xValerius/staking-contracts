// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import {MockToken} from "../src/contracts/MockToken.sol";
import {ERC20Staking} from "../src/contracts/ERC20Staking.sol";

contract ERC20StakingTest is Test {
    MockToken stakingToken = new MockToken("Staking Token", "ST");
    MockToken rewardToken = new MockToken("Reward Token", "RT");

    ERC20Staking staking;

    address owner = makeAddr("owner");
    address actor1 = makeAddr("actor1");
    address actor2 = makeAddr("actor2");
    address actor3 = makeAddr("actor3");

    uint256 initialStakingBalance = 1000;
    uint256 initialRewardAmount = 1000;
    //uint256 duration = 100;

    function setUp() public {
        // deploy staking contract
        vm.prank(owner);
        staking = new ERC20Staking(address(stakingToken), address(rewardToken));

        // Mint staking tokens to actors
        deal(address(stakingToken), actor1, initialStakingBalance, true);
        deal(address(stakingToken), actor2, initialStakingBalance, true);
        deal(address(stakingToken), actor3, initialStakingBalance, true);

        // Mint reward tokens to owner
        deal(address(rewardToken), owner, initialRewardAmount, true);
    }
}
