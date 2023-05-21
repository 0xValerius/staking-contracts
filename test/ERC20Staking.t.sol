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
    uint256 initialRewardAmount = 24000;
    uint256 startAt = 100;
    uint256 endAt = 500;
    uint256 initialReward = 12000;
    // reward rate is going to be 1200/400 = 30

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
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), 0);
        assertEq(staking.lastUpdateTime(), startAt);

        // forward to 10 seconds before startAt
        vm.warp(startAt - 10);

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance - stakeAmount);
        assertEq(staking.totalStaked(), stakeAmount);
        assertEq(staking.balances(actor1), stakeAmount);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), 0);
        assertEq(staking.lastUpdateTime(), startAt);

        // forward to 10 seconds after startAt
        vm.warp(startAt + 10);

        // evaluate
        assertEq(staking.earned(actor1), 300);
        assertEq(staking.rewardPerToken(), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt);
        assertEq(staking.rewardPerTokenStored(), 0);
        assertEq(staking.userRewardPerTokenPaid(actor1), 0);
        assertEq(staking.toDistributeRewards(), initialReward);
        assertEq(staking.owedRewards(), 0);

        // user claims rewards and exit
        staking.exit();

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor1), 300);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.balances(actor1), 0);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardPerToken(), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt + 10);
        assertEq(staking.userRewardPerTokenPaid(actor1), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.toDistributeRewards(), initialReward - 300);
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

        // forward to 200 seconds after startAt
        vm.warp(startAt + 200);

        // stake
        vm.startPrank(actor1);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(100);

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance - stakeAmount);
        assertEq(staking.totalStaked(), stakeAmount);
        assertEq(staking.balances(actor1), stakeAmount);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), 0);
        assertEq(staking.lastUpdateTime(), startAt + 200);

        // forward to 210 seconds after startAt
        vm.warp(startAt + 210);

        // evaluate
        assertEq(staking.earned(actor1), 300);
        assertEq(staking.rewardPerToken(), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt + 200);
        assertEq(staking.rewardPerTokenStored(), 0);
        assertEq(staking.userRewardPerTokenPaid(actor1), 0);
        assertEq(staking.toDistributeRewards(), initialReward);
        assertEq(staking.owedRewards(), 0);

        // user claims rewards and exit
        staking.exit();
        vm.stopPrank();

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor1), 300);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.balances(actor1), 0);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardPerToken(), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt + 210);
        assertEq(staking.userRewardPerTokenPaid(actor1), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.toDistributeRewards(), initialReward - 300);
        assertEq(staking.owedRewards(), 0);

        /// reward are not distributed during the first 10 seconds. They can be either claimed by the owner or reintroduced in the staking contract. To maintain the same reward rate the owner should reintroduce the rewards in the staking contract and increase endAt. Reintroducing the rewards without increasing endAt will increase the reward rate. The latter scenario can be achieved by calling updateRewardAllocation(0). This will update the reward rate so that the pre-fixed staking reward are distributed by the end of the staking period.

        // reintroduce rewards
        uint256 previousRewardRate = staking.rewardRate();
        console.log("LeftOver", staking.toDistributeRewards() - (endAt - block.timestamp) * previousRewardRate);
        console.log("previousRewardRate", previousRewardRate);

        vm.startPrank(owner);
        staking.updateRewardAllocation(0);
        vm.stopPrank();
        console.log("newRewardRate", staking.rewardRate());
        assertGt(staking.rewardRate(), previousRewardRate);
    }

    function test_Simulation4() public {
        /// Simulation: owner initializes the staking contract and loads rewards. At time startAt the actor1 stakes 100 tokens. After 10 seconds the actor2 stakes 100 tokens. After 10 seconds the user3 stakes 100 tokens. After 10 seconds the user1 claims rewards. After 10 seconds the user2 claims rewards. After 10 seconds the user3 claims rewards.

        uint256 stakeAmount = 100;

        // initialize staking contract
        vm.startPrank(owner);
        staking.setStartAt(startAt);
        staking.setEndAt(endAt);
        rewardToken.transfer(address(staking), initialReward);
        staking.updateRewardAllocation(initialReward);
        vm.stopPrank();

        // actor1 stakes
        vm.startPrank(actor1);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance - stakeAmount);
        assertEq(staking.totalStaked(), stakeAmount);
        assertEq(staking.balances(actor1), stakeAmount);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), 0);
        assertEq(staking.lastUpdateTime(), startAt);

        // forward to startAt + 10
        vm.warp(startAt + 10);

        // actor2 stakes
        vm.startPrank(actor2);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        // evaluate actor2 position
        assertEq(staking.totalStaked(), stakeAmount * 2);
        assertEq(staking.balances(actor2), stakeAmount);
        assertEq(staking.earned(actor2), 0);
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), 10 * 30 * 1e18 / stakeAmount);
        assertEq(staking.userRewardPerTokenPaid(actor2), 10 * 30 * 1e18 / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt + 10);

        // evaluate actor1 position
        assertEq(staking.balances(actor1), stakeAmount);
        assertEq(staking.earned(actor1), 300);

        // forward to startAt + 20
        vm.warp(startAt + 20);

        // actor3 stakes
        vm.startPrank(actor3);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        // evaluate actor3 position
        assertEq(staking.totalStaked(), stakeAmount * 3);
        assertEq(staking.balances(actor3), stakeAmount);
        assertEq(staking.earned(actor3), 0);
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), (10 * 30 * 1e18 / 100) + (10 * 30 * 1e18 / 200));
        assertEq(staking.userRewardPerTokenPaid(actor3), (10 * 30 * 1e18 / 100) + (10 * 30 * 1e18 / 200));
        assertEq(staking.lastUpdateTime(), startAt + 20);

        // evaluate actor2 position
        assertEq(staking.balances(actor2), stakeAmount);
        assertEq(staking.earned(actor2), 150);

        // evaluate actor1 position
        assertEq(staking.balances(actor1), stakeAmount);
        assertEq(staking.earned(actor1), 450);

        // forward to startAt + 30
        vm.warp(startAt + 30);

        // evaluate staking contract reward balance
        assertEq(rewardToken.balanceOf(address(staking)), initialReward);
        assertEq(staking.toDistributeRewards(), initialReward - 450 - 150);
        assertEq(staking.owedRewards(), 450 + 150);

        // actor1 claims rewards
        vm.prank(actor1);
        staking.exit();

        // evaluate actor1 position
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor1), 550);

        // evaluate actor2 and actor3 position
        assertEq(staking.earned(actor2), 250);
        assertEq(staking.earned(actor3), 100);

        // evaluate staking contract reward balance
        assertEq(rewardToken.balanceOf(address(staking)), initialReward - 550);
        assertEq(staking.toDistributeRewards(), initialReward - 550 - 250 - 100);
        assertEq(staking.owedRewards(), 250 + 100);

        // forward to startAt + 40
        vm.warp(startAt + 40);

        // actor2 claims rewards
        vm.prank(actor2);
        staking.exit();

        // evaluate actor2 position
        assertEq(stakingToken.balanceOf(actor2), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor2), 400);

        // evaluate actor3 position
        assertEq(staking.earned(actor3), 250);

        // evaluate staking contract reward balance
        assertEq(rewardToken.balanceOf(address(staking)), initialReward - 550 - 400);
        assertEq(staking.toDistributeRewards(), initialReward - 550 - 400 - 250);
        assertEq(staking.owedRewards(), 250);

        // forward to startAt + 50
        vm.warp(startAt + 50);

        // actor3 claims rewards
        vm.prank(actor3);
        staking.exit();

        // evaluate actor3 position
        assertEq(stakingToken.balanceOf(actor3), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor3), 550);

        // evaluate staking contract reward balance
        assertEq(rewardToken.balanceOf(address(staking)), initialReward - 550 - 400 - 550);
        assertEq(staking.toDistributeRewards(), initialReward - 550 - 400 - 550);
        assertEq(staking.owedRewards(), 0);
        assertEq(staking.totalStaked(), 0);

        // no staking for 1000 timestamps
        vm.warp(startAt + 50 + 50);

        // reintroduce rewards
        uint256 previousRewardRate = staking.rewardRate();
        console.log("LeftOver", staking.toDistributeRewards() - (endAt - block.timestamp) * previousRewardRate);
        console.log("previousRewardRate", previousRewardRate);

        vm.startPrank(owner);
        staking.updateRewardAllocation(0);
        vm.stopPrank();
        console.log("newRewardRate", staking.rewardRate());
        assertGt(staking.rewardRate(), previousRewardRate);
    }
}
