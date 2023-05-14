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
        /// Simulation: actor1 stakes 100 tokens before owner initialize the contract and load rewards. The owner initialize the staking contract after 10 seconds. The user waits for 20 seconds and then claims rewards.

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
        /// Simulation: actor1 stakes 100 tokens for 100 seconds starting from the beginning. Then user1 claims rewards.

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

    function test_Simulation3() public {
        /// Simulation: owner initializes the staking contract and loads rewards. After 10 seconds the actor1 stakes 100 tokens. After 20 seconds the user1 claims rewards.

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

        // forward 10 seconds
        vm.warp(11);

        // stake
        vm.startPrank(actor1);
        stakingToken.approve(address(staking), 100);
        staking.stake(100);

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance - 100);
        assertEq(staking.totalSupply(), 100);
        assertEq(staking.balances(actor1), 100);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.userRewardPerTokenPaid(actor1), 0);
        assertEq(staking.rewardRate(), initialRewardAmount / duration);
        assertEq(staking.lastUpdateTime(), 11); // 11
        assertEq(staking.rewardPerTokenStored(), 0); // 0, actor1 is the first one to stake

        // forward 20 seconds
        vm.warp(31);
        assertEq(staking.earned(actor1), 20 * staking.rewardRate()); // the user earn reward during the 20 seconds staking period. Rewards from the moment owner initialized the contract and first user staked will not be distrubted as staking reward and will remain in the contract.
        staking.exit();
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor1), 20 * staking.rewardRate());
        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balances(actor1), 0);
        assertEq(staking.userRewardPerTokenPaid(actor1), 20 * 3 * 1e18 / 100);
        assertEq(staking.rewardPerTokenStored(), 20 * 3 * 1e18 / 100);
    }

    function test_Simulation4() public {
        /// Simulation: owner initializes the staking contract and loads rewards. At time 0 the actor1 stakes 100 tokens. After 10 seconds the actor2 stakes 100 tokens. After 10 seconds the user3 stakes 100 tokens. After 10 seconds the user1 claims rewards. After 10 seconds the user2 claims rewards. After 10 seconds the user3 claims rewards.

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

        // user1 stakes
        vm.startPrank(actor1);
        stakingToken.approve(address(staking), 100);
        staking.stake(100);
        vm.stopPrank();

        // evaluate
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance - 100);
        assertEq(staking.totalSupply(), 100);
        assertEq(staking.balances(actor1), 100);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.userRewardPerTokenPaid(actor1), 0);
        assertEq(staking.rewardRate(), initialRewardAmount / duration);
        assertEq(staking.lastUpdateTime(), 1); // 1
        assertEq(staking.rewardPerTokenStored(), 0); // 0, actor1 is the first one to stake

        // forward 10 seconds
        vm.warp(11);

        // user2 stakes
        vm.startPrank(actor2);
        stakingToken.approve(address(staking), 100);
        staking.stake(100);
        vm.stopPrank();

        // evaluate user2 position
        assertEq(stakingToken.balanceOf(actor2), initialStakingBalance - 100);
        assertEq(staking.totalSupply(), 200);
        assertEq(staking.balances(actor2), 100);
        assertEq(staking.earned(actor2), 0);
        assertEq(staking.userRewardPerTokenPaid(actor2), 10 * 3 * 1e18 / 100);
        assertEq(staking.lastUpdateTime(), 11); // 11

        // evaluate user1 position
        assertEq(staking.earned(actor1), 30);

        // forward 10 seconds
        vm.warp(21);

        // user3 stakes
        vm.startPrank(actor3);
        stakingToken.approve(address(staking), 100);
        staking.stake(100);
        vm.stopPrank();

        // evaluate user3 position
        assertEq(stakingToken.balanceOf(actor3), initialStakingBalance - 100);
        assertEq(staking.totalSupply(), 300);
        assertEq(staking.balances(actor3), 100);
        assertEq(staking.earned(actor3), 0);
        assertEq(staking.userRewardPerTokenPaid(actor3), 10 * 3 * 1e18 / 100 + 10 * 3 * 1e18 / 200);

        // evaluate user1 and user2 position
        assertEq(staking.earned(actor1), 45);
        assertEq(staking.earned(actor2), 15);

        // forward 10 seconds
        vm.warp(31);

        // user1 exit
        vm.prank(actor1);
        staking.exit();

        // evaluate user1 position
        assertEq(stakingToken.balanceOf(actor1), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor1), 55);

        // evaluate user2 and user3 position
        assertEq(staking.earned(actor2), 25);
        assertEq(staking.earned(actor3), 10);

        // forward 10 seconds
        vm.warp(41);

        // user2 exit
        vm.prank(actor2);
        staking.exit();

        // evaluate user2 position
        assertEq(stakingToken.balanceOf(actor2), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor2), 40);

        // evaluate user3 position
        assertEq(staking.earned(actor3), 25);

        // forward 10 seconds
        vm.warp(51);

        // user3 exit
        vm.prank(actor3);
        staking.exit();

        // evaluate user3 position
        assertEq(stakingToken.balanceOf(actor3), initialStakingBalance);
        assertEq(rewardToken.balanceOf(actor3), 55);
    }
}
