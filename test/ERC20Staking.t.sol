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
    uint256 initialRewardAmount = 2400;
    uint256 startAt = 100;
    uint256 endAt = 500;
    uint256 initialReward = 1200;
    // reward rate is going to be 1200/400 = 3

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

    function test_MockTokenDeployment() public {
        assertEq(stakingToken.name(), "Staking Token");
        assertEq(stakingToken.symbol(), "ST");
        assertEq(stakingToken.balanceOf(owner), 0);
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance);
        assertEq(stakingToken.balanceOf(actor2), initialStakingBalance);
        assertEq(stakingToken.balanceOf(actor3), initialStakingBalance);
        assertEq(stakingToken.totalSupply(), initialStakingBalance * 3);

        assertEq(rewardToken.name(), "Reward Token");
        assertEq(rewardToken.symbol(), "RT");
        assertEq(rewardToken.balanceOf(owner), initialRewardAmount);
        assertEq(rewardToken.totalSupply(), initialRewardAmount);
    }

    function test_ERC20StakingDeployment() public {
        assertEq(address(staking.stakingToken()), address(stakingToken));
        assertEq(address(staking.rewardToken()), address(rewardToken));
        assertEq(staking.owner(), owner);
    }

    function test_setStartAt() public {
        // non-owner cannot set startAt
        vm.prank(actor1);
        vm.expectRevert("Ownable: caller is not the owner");
        staking.setStartAt(1);

        // owner can set startAt
        vm.prank(owner);
        staking.setStartAt(startAt);
        assertEq(staking.startAt(), startAt);
    }

    function test_setEndAt() public {
        // non-owner cannot set endAt
        vm.prank(actor1);
        vm.expectRevert("Ownable: caller is not the owner");
        staking.setEndAt(1);

        // Cannot set endAt in the past
        vm.startPrank(owner);
        vm.expectRevert("Cannot set endAt in the past");
        staking.setEndAt(block.timestamp - 1);

        staking.setStartAt(startAt);
        vm.expectRevert("Cannot set endAt before startAt");
        staking.setEndAt(startAt);

        staking.setEndAt(endAt);
        vm.stopPrank();
        assertEq(staking.endAt(), endAt);
        assertEq(staking.rewardRate(), 0);
    }

    function test_lastTimeRewardApplicable() public {
        vm.startPrank(owner);
        staking.setStartAt(startAt);
        staking.setEndAt(endAt);
        assertEq(staking.lastTimeRewardApplicable(), startAt);
        vm.warp(startAt + 10);
        assertEq(staking.lastTimeRewardApplicable(), startAt + 10);
        vm.warp(endAt + 10);
        assertEq(staking.lastTimeRewardApplicable(), endAt);
    }

    function test_updateRewardAllocation() public {
        vm.startPrank(owner);
        vm.expectRevert("Cannot update reward allocation after endAt");
        staking.updateRewardAllocation(10);
        staking.setEndAt(endAt);
        vm.expectRevert("Cannot update reward allocation before startAt");
        staking.updateRewardAllocation(10);
        staking.setStartAt(startAt);
        vm.expectRevert("Cannot update reward allocation to more than the balance of the contract");
        staking.updateRewardAllocation(10);

        // transfer reward to distribute
        rewardToken.transfer(address(staking), initialReward);
        staking.updateRewardAllocation(initialReward);
        assertEq(staking.rewardRate(), initialReward / (endAt - startAt));
        assertEq(staking.lastUpdateTime(), startAt);
        assertEq(staking.rewardPerTokenStored(), 0);
        assertEq(staking.toDistributeRewards(), initialReward);

        // change reward rate modifying endAt
        staking.setEndAt(endAt + 100);
        assertEq(staking.rewardRate(), initialReward / (endAt + 100 - startAt));

        // change reward rate adding more rewards
        rewardToken.transfer(address(staking), initialReward);
        staking.updateRewardAllocation(initialReward);
        assertEq(staking.rewardRate(), (initialReward * 2) / (endAt + 100 - startAt));
    }

    function test_Simulation1() public {
        /// Simulation: actor1 stakes 100 tokens before owner initialize the contract and load rewards. The owner initialize the staking contract after 10 seconds. The user waits for 20 seconds and then claims rewards.

        uint256 stakeAmount = 100;

        // initialize staking contract
        vm.startPrank(owner);
        staking.setStartAt(startAt);
        staking.setEndAt(endAt);
        rewardToken.transfer(address(staking), initialReward);
        staking.updateRewardAllocation(initialReward);
        vm.stopPrank();

        // stake
        vm.startPrank(actor1);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(100);

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance - stakeAmount);
        assertEq(staking.totalStaked(), stakeAmount);
        assertEq(staking.balances(actor1), stakeAmount);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardRate(), 3);
        assertEq(staking.rewardPerToken(), 0);
        assertEq(staking.lastUpdateTime(), startAt);

        // forward to 10 seconds before startAt
        vm.warp(startAt - 10);

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance - stakeAmount);
        assertEq(staking.totalStaked(), stakeAmount);
        assertEq(staking.balances(actor1), stakeAmount);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardRate(), 3);
        assertEq(staking.rewardPerToken(), 0);
        assertEq(staking.lastUpdateTime(), startAt);

        // forward to 10 seconds after startAt
        vm.warp(startAt + 10);

        // evaluate
        assertEq(staking.earned(actor1), 30);
        assertEq(staking.rewardPerToken(), (10 * 3 * 1e18) / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt);
        assertEq(staking.rewardPerTokenStored(), 0);
        assertEq(staking.userRewardPerTokenPaid(actor1), 0);
        assertEq(staking.toDistributeRewards(), initialReward);
        assertEq(staking.owedRewards(), 0);

        // user claims rewards and exit
        staking.exit();

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor1), 30);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.balances(actor1), 0);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardPerToken(), (10 * 3 * 1e18) / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt + 10);
        assertEq(staking.userRewardPerTokenPaid(actor1), (10 * 3 * 1e18) / stakeAmount);
        assertEq(staking.toDistributeRewards(), initialReward - 30);
        assertEq(staking.owedRewards(), 0);
    }

    function test_Simulation3() public {
        /// Simulation: owner initializes the staking contract and loads rewards. 10 seconds after startAt, the actor1 stakes 100 tokens. After 20 seconds the user1 claims rewards.

        uint256 stakeAmount = 100;

        // initialize staking contract
        vm.startPrank(owner);
        staking.setStartAt(startAt);
        staking.setEndAt(endAt);
        rewardToken.transfer(address(staking), initialReward);
        staking.updateRewardAllocation(initialReward);
        vm.stopPrank();
    }
}
