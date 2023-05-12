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
        assertEq(staking.rewardRate(), initialRewardAmount / duration);
    }
}
