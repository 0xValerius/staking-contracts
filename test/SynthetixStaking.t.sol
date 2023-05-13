// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import {MockToken} from "../src/contracts/MockToken.sol";
import {SynthetixStaking} from "../src/contracts/SynthetixStaking.sol";

contract SynthetixStakingTest is Test {
    MockToken stakingToken;
    MockToken rewardToken;

    SynthetixStaking staking;

    address owner = makeAddr("owner");
    address actor1 = makeAddr("actor1");
    address actor2 = makeAddr("actor2");
    address actor3 = makeAddr("actor3");

    uint256 initialStakingBalance = 1000;
    uint256 initialRewardAmount = 3000;
    uint256 duration = 1000;

    function setUp() public {
        // Initilize tokens and staking contract
        stakingToken = new MockToken('Staking Token', 'ST');
        rewardToken = new MockToken('Reward Token', 'RT');
        vm.prank(owner);
        staking = new SynthetixStaking(address(stakingToken), address(rewardToken));

        // Mint tokens to actors
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

    function test_SynthetixDeployment() public {
        assertEq(address(staking.stakingToken()), address(stakingToken));
        assertEq(address(staking.rewardToken()), address(rewardToken));
        assertEq(staking.owner(), address(owner));
    }

    function test_SynthetixSetStaking() public {
        vm.startPrank(owner);
        staking.setRewardsDuration(duration);
        assertEq(staking.rewardsDuration(), duration);

        rewardToken.transfer(address(staking), initialRewardAmount);
        assertEq(rewardToken.balanceOf(address(staking)), initialRewardAmount);

        staking.notifyRewardAmount(initialRewardAmount);
        vm.stopPrank();
        assertEq(staking.totalSupply(), 0);
        assertEq(staking.rewardRate(), initialRewardAmount / duration);
        assertEq(staking.lastUpdateTime(), block.timestamp); // 1
        assertEq(staking.rewardPerTokenStored(), 0); // 0 because no one has staked yet | total supply is 0
    }

    function test_Simulation1() public {
        /// Simulation: user1 stakes 100 tokens before owner initialize the contract and load rewards. The owner initialize the staking contract after 10 seconds. The user waits for 20 seconds and then claims rewards.

        // stake
        vm.startPrank(actor1);
        stakingToken.approve(address(staking), 100);
        staking.stake(100);

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance - 100);
        assertEq(staking.totalSupply(), 100);
        assertEq(staking.balances(actor1), 100);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardRate(), 0);
        vm.stopPrank();

        // wait for 10 seconds
        vm.warp(11);

        // initialize staking contract
        vm.startPrank(owner);
        staking.setRewardsDuration(duration);
        assertEq(staking.rewardsDuration(), duration);
        rewardToken.transfer(address(staking), initialRewardAmount);
        assertEq(rewardToken.balanceOf(address(staking)), initialRewardAmount);
        staking.notifyRewardAmount(initialRewardAmount);
        vm.stopPrank();
        assertEq(staking.rewardRate(), initialRewardAmount / duration);
        assertEq(staking.lastUpdateTime(), block.timestamp); // 11
        assertEq(staking.rewardPerTokenStored(), 0); // 0 because even tho the user has staked, but the owner didn't have initialized the contract yet (rewardRate() was 0)
        assertEq(staking.endAt(), block.timestamp + duration);

        // forward 20 seconds
        vm.warp(31);

        // evaluate
        assertEq(staking.earned(actor1), 20 * staking.rewardRate());
        vm.prank(actor1);
        staking.exit();
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor1), 20 * staking.rewardRate());
        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balances(actor1), 0);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.userRewardPerTokenPaid(actor1), 20 * staking.rewardRate() * 1e18 / 100);
    }

    function test_Simulation2() public {
        /// Simulation: user1 stakes 100 tokens for 100 seconds starting from the beginning. Then user1 claims rewards.

        // initialize staking contract
        vm.startPrank(owner);
        staking.setRewardsDuration(duration);
        assertEq(staking.rewardsDuration(), duration);
        rewardToken.transfer(address(staking), initialRewardAmount);
        assertEq(rewardToken.balanceOf(address(staking)), initialRewardAmount);
        staking.notifyRewardAmount(initialRewardAmount);
        vm.stopPrank();
        assertEq(staking.totalSupply(), 0);
        assertEq(staking.rewardRate(), initialRewardAmount / duration);
        assertEq(staking.lastUpdateTime(), block.timestamp); // 1
        assertEq(staking.rewardPerTokenStored(), 0); // 0 because no one has staked yet | total supply is 0
        assertEq(staking.endAt(), block.timestamp + duration);

        // stake
        vm.startPrank(actor1);
        stakingToken.approve(address(staking), 100);
        staking.stake(100);

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance - 100);
        assertEq(staking.totalSupply(), 100);
        assertEq(staking.balances(actor1), 100);
        assertEq(staking.earned(actor1), 0);

        // forward 10 seconds
        vm.warp(11);
        assertEq(staking.earned(actor1), 10 * staking.rewardRate()); // 30 tokens
        staking.exit();
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor1), 30);
        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balances(actor1), 0);
        assertEq(staking.userRewardPerTokenPaid(actor1), 10 * 3 * 1e18 / 100);
        assertEq(staking.rewardPerTokenStored(), 10 * 3 * 1e18 / 100);
    }
}
