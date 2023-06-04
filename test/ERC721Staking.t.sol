// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import {MockToken} from "../src/contracts/MockToken.sol";
import {MockNFT} from "../src/contracts/MockNFT.sol";
import {ERC721Staking} from "../src/contracts/ERC721Staking.sol";

contract ERC721StakingTest is Test {
    MockNFT collection = new MockNFT("Staking NFT","SNFT");
    MockToken rewardToken = new MockToken("Reward Token", "RTK");

    ERC721Staking staking;

    address owner = makeAddr("owner");
    address actor1 = makeAddr("actor1");
    address actor2 = makeAddr("actor2");
    address actor3 = makeAddr("actor3");
    uint256[] actor1Tokens = [0, 1, 2, 3, 4];
    uint256[] actor2Tokens = [5, 6, 7, 8, 9];
    uint256[] actor3Tokens = [10, 11, 12, 13, 14];
    uint256 stakeAmount = 5;
    uint256[] noStaked;

    uint256 initialMintAmount = 5;
    uint256 initialRewardMinted = 24000;
    uint256 initialRewardAllocated = 12000;
    uint256 startAt = 100;
    uint256 endAt = 500;
    // reward rate is going to be 12000 / (500 - 100) = 30 per second

    function setUp() public {
        // deploy staking contract
        vm.prank(owner);
        staking = new ERC721Staking(address(collection), address(rewardToken));

        // Mint staking NFT to actors
        collection.mint(actor1, initialMintAmount);
        collection.mint(actor2, initialMintAmount);
        collection.mint(actor3, initialMintAmount);

        // Mint reward tokens to owner
        deal(address(rewardToken), owner, initialRewardMinted, true);
    }

    function test_MockTokenDeployment() public {
        assertEq(collection.name(), "Staking NFT");
        assertEq(collection.symbol(), "SNFT");
        assertEq(collection.totalSupply(), 15);
        assertEq(collection.balanceOf(owner), 0);
        assertEq(collection.balanceOf(actor1), 5);
        assertEq(collection.balanceOf(actor2), 5);
        assertEq(collection.balanceOf(actor3), 5);

        assertEq(rewardToken.name(), "Reward Token");
        assertEq(rewardToken.symbol(), "RTK");
        assertEq(rewardToken.totalSupply(), initialRewardMinted);
        assertEq(rewardToken.balanceOf(owner), initialRewardMinted);
    }

    function test_ERC721StakingDeployment() public {
        assertEq(address(staking.nftCollection()), address(collection));
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

    function test_increaseRewardAllocation() public {
        vm.startPrank(owner);
        //vm.expectRevert("Cannot update reward allocation after endAt");
        //staking.increaseRewardAllocation(10);
        staking.setEndAt(endAt);
        //vm.expectRevert("Cannot update reward allocation before startAt");
        //staking.increaseRewardAllocation(10);
        staking.setStartAt(startAt);
        vm.expectRevert("Cannot update reward allocation to more than the balance of the contract");
        staking.increaseRewardAllocation(10);

        // transfer reward to distribute
        rewardToken.transfer(address(staking), initialRewardAllocated);
        staking.increaseRewardAllocation(initialRewardAllocated);
        assertEq(staking.rewardRate(), initialRewardAllocated / (endAt - startAt));
        assertEq(staking.lastUpdateTime(), startAt);
        assertEq(staking.rewardPerTokenStored(), 0);
        assertEq(staking.toDistributeRewards(), initialRewardAllocated);

        // change reward rate modifying endAt
        staking.setEndAt(endAt + 100);
        assertEq(staking.rewardRate(), initialRewardAllocated / (endAt + 100 - startAt));

        // change reward rate adding more rewards
        rewardToken.transfer(address(staking), initialRewardAllocated);
        staking.increaseRewardAllocation(initialRewardAllocated);
        assertEq(staking.rewardRate(), (initialRewardAllocated * 2) / (endAt + 100 - startAt));
    }

    function test_decreaseRewardAllocation() public {
        vm.startPrank(owner);
        staking.setEndAt(endAt);
        staking.setStartAt(startAt);

        // transfer reward to distribute
        rewardToken.transfer(address(staking), initialRewardAllocated);
        staking.increaseRewardAllocation(initialRewardAllocated);
        assertEq(staking.rewardRate(), initialRewardAllocated / (endAt - startAt));
        assertEq(staking.lastUpdateTime(), startAt);
        assertEq(staking.rewardPerTokenStored(), 0);
        assertEq(staking.toDistributeRewards(), initialRewardAllocated);

        // change reward rate decreasing rewards
        staking.decreaseRewardAllocation(initialRewardAllocated / 2);
        assertEq(staking.rewardRate(), (initialRewardAllocated / 2) / (endAt - startAt));
        assertEq(staking.toDistributeRewards(), initialRewardAllocated / 2);
    }

    function test_Simulation1() public {
        /// Simulation: actor1 stakes 5 NFTs before owner initialize the contract and load rewards. The owner initialize the staking contract after 10 seconds. The user waits for 20 seconds and then claims rewards.

        // initialize staking contract
        vm.startPrank(owner);
        staking.setStartAt(startAt);
        staking.setEndAt(endAt);
        rewardToken.transfer(address(staking), initialRewardAllocated);
        staking.increaseRewardAllocation(initialRewardAllocated);
        vm.stopPrank();

        // stake
        vm.startPrank(actor1);
        collection.approve(address(staking), actor1Tokens[0]);
        collection.approve(address(staking), actor1Tokens[1]);
        collection.approve(address(staking), actor1Tokens[2]);
        collection.approve(address(staking), actor1Tokens[3]);
        collection.approve(address(staking), actor1Tokens[4]);
        staking.stake(actor1Tokens);

        // evaluate
        assertEq(collection.balanceOf(actor1), 0);
        assertEq(staking.totalStaked(), stakeAmount);
        (uint256[] memory _actor1Tokens, uint256 _earned) = staking.userStakeInfo(actor1);
        assertEq(_actor1Tokens, actor1Tokens);
        assertEq(_earned, 0);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), 0);
        assertEq(staking.lastUpdateTime(), startAt);

        // forward to 10 seconds before startAt
        vm.warp(startAt - 10);

        // evaluate
        assertEq(collection.balanceOf(actor1), 0);
        assertEq(staking.totalStaked(), stakeAmount);
        (_actor1Tokens, _earned) = staking.userStakeInfo(actor1);
        assertEq(_actor1Tokens, actor1Tokens);
        assertEq(_earned, 0);
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
        assertEq(staking.toDistributeRewards(), initialRewardAllocated);
        assertEq(staking.owedRewards(), 0);

        // user claims rewards and exit
        staking.exit();

        // evaluate
        assertEq(collection.balanceOf(actor1), 5);
        assertEq(rewardToken.balanceOf(actor1), 300);
        assertEq(staking.totalStaked(), 0);
        (_actor1Tokens, _earned) = staking.userStakeInfo(actor1);
        assertEq(_actor1Tokens, noStaked);
        assertEq(_earned, 0);

        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardPerToken(), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt + 10);
        assertEq(staking.userRewardPerTokenPaid(actor1), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.toDistributeRewards(), initialRewardAllocated - 300);
        assertEq(staking.owedRewards(), 0);
    }

    function test_Simulation3() public {
        /// Simulation: owner initializes the staking contract and loads rewards. 200 seconds after startAt, the actor1 stakes 5 NFTs. After 10 seconds the user1 claims rewards.

        // initialize staking contract
        vm.startPrank(owner);
        staking.setStartAt(startAt);
        staking.setEndAt(endAt);
        rewardToken.transfer(address(staking), initialRewardAllocated);
        staking.increaseRewardAllocation(initialRewardAllocated);
        vm.stopPrank();

        // forward to 200 seconds after startAt
        vm.warp(startAt + 200);

        // stake
        vm.startPrank(actor1);
        collection.approve(address(staking), actor1Tokens[0]);
        collection.approve(address(staking), actor1Tokens[1]);
        collection.approve(address(staking), actor1Tokens[2]);
        collection.approve(address(staking), actor1Tokens[3]);
        collection.approve(address(staking), actor1Tokens[4]);
        staking.stake(actor1Tokens);

        // evaluate
        assertEq(collection.balanceOf(actor1), 0);
        assertEq(staking.totalStaked(), stakeAmount);
        (uint256[] memory _actor1Tokens, uint256 _earned) = staking.userStakeInfo(actor1);
        assertEq(_actor1Tokens, actor1Tokens);
        assertEq(_earned, 0);
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
        assertEq(staking.toDistributeRewards(), initialRewardAllocated);
        assertEq(staking.owedRewards(), 0);

        // user claims rewards and exit
        staking.exit();
        vm.stopPrank();

        // evaluate
        assertEq(collection.balanceOf(actor1), 5);
        assertEq(rewardToken.balanceOf(actor1), 300);
        assertEq(staking.totalStaked(), 0);
        (_actor1Tokens, _earned) = staking.userStakeInfo(actor1);
        assertEq(_actor1Tokens, noStaked);
        assertEq(_earned, 0);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardPerToken(), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt + 210);
        assertEq(staking.userRewardPerTokenPaid(actor1), (10 * 30 * 1e18) / stakeAmount);
        assertEq(staking.toDistributeRewards(), initialRewardAllocated - 300);
        assertEq(staking.owedRewards(), 0);

        /// reward are not distributed during the first 10 seconds. They can be either claimed by the owner or reintroduced in the staking contract. To maintain the same reward rate the owner should reintroduce the rewards in the staking contract and increase endAt. Reintroducing the rewards without increasing endAt will increase the reward rate. The latter scenario can be achieved by calling updateRewardAllocation(0). This will update the reward rate so that the pre-fixed staking reward are distributed by the end of the staking period.

        // reintroduce rewards
        uint256 previousRewardRate = staking.rewardRate();
        console.log("Left Over", staking.toDistributeRewards() - (endAt - block.timestamp) * previousRewardRate);
        console.log("Previous Reward Rate", previousRewardRate);

        vm.startPrank(owner);
        staking.increaseRewardAllocation(0);
        vm.stopPrank();
        console.log("New Reward Rate", staking.rewardRate());
        assertGt(staking.rewardRate(), previousRewardRate);
    }

    function test_Simulation4() public {
        /// Simulation: owner initializes the staking contract and loads rewards. At time startAt the actor1 stakes 5 NFTs. After 10 seconds the actor2 stakes 5 NFTs. After 10 seconds the user3 stakes 5 NFTs. After 10 seconds the user1 claims rewards. After 10 seconds the user2 claims rewards. After 10 seconds the user3 claims rewards.

        // initialize staking contract
        vm.startPrank(owner);
        staking.setStartAt(startAt);
        staking.setEndAt(endAt);
        rewardToken.transfer(address(staking), initialRewardAllocated);
        staking.increaseRewardAllocation(initialRewardAllocated);
        vm.stopPrank();

        // actor1 stakes
        vm.startPrank(actor1);
        collection.approve(address(staking), actor1Tokens[0]);
        collection.approve(address(staking), actor1Tokens[1]);
        collection.approve(address(staking), actor1Tokens[2]);
        collection.approve(address(staking), actor1Tokens[3]);
        collection.approve(address(staking), actor1Tokens[4]);
        staking.stake(actor1Tokens);
        vm.stopPrank();

        // evaluate
        assertEq(collection.balanceOf(actor1), 0);
        assertEq(staking.totalStaked(), stakeAmount);
        (uint256[] memory _actor1Tokens, uint256 _earnedActor1) = staking.userStakeInfo(actor1);
        assertEq(_actor1Tokens, actor1Tokens);
        assertEq(_earnedActor1, 0);
        assertEq(staking.earned(actor1), 0);
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), 0);
        assertEq(staking.lastUpdateTime(), startAt);

        // forward to startAt + 10
        vm.warp(startAt + 10);

        // actor2 stakes
        vm.startPrank(actor2);
        collection.approve(address(staking), actor2Tokens[0]);
        collection.approve(address(staking), actor2Tokens[1]);
        collection.approve(address(staking), actor2Tokens[2]);
        collection.approve(address(staking), actor2Tokens[3]);
        collection.approve(address(staking), actor2Tokens[4]);
        staking.stake(actor2Tokens);
        vm.stopPrank();

        // evaluate actor2 position
        assertEq(collection.balanceOf(actor2), 0);
        assertEq(staking.totalStaked(), stakeAmount * 2);
        (uint256[] memory _actor2Tokens, uint256 _earnedActor2) = staking.userStakeInfo(actor2);
        assertEq(_actor2Tokens, actor2Tokens);
        assertEq(_earnedActor2, 0);
        assertEq(staking.earned(actor2), 0);
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), 10 * 30 * 1e18 / stakeAmount);
        assertEq(staking.userRewardPerTokenPaid(actor2), 10 * 30 * 1e18 / stakeAmount);
        assertEq(staking.lastUpdateTime(), startAt + 10);

        // evaluate actor1 position
        assertEq(staking.earned(actor1), 300);

        // forward to startAt + 20
        vm.warp(startAt + 20);

        // actor3 stakes
        vm.startPrank(actor3);
        collection.approve(address(staking), actor3Tokens[0]);
        collection.approve(address(staking), actor3Tokens[1]);
        collection.approve(address(staking), actor3Tokens[2]);
        collection.approve(address(staking), actor3Tokens[3]);
        collection.approve(address(staking), actor3Tokens[4]);
        staking.stake(actor3Tokens);
        vm.stopPrank();

        // evaluate actor3 position
        assertEq(collection.balanceOf(actor3), 0);
        assertEq(staking.totalStaked(), stakeAmount * 3);
        (uint256[] memory _actor3Tokens, uint256 _earnedActor3) = staking.userStakeInfo(actor3);
        assertEq(_actor3Tokens, actor3Tokens);
        assertEq(_earnedActor3, 0);
        assertEq(staking.earned(actor3), 0);
        assertEq(staking.rewardRate(), 30);
        assertEq(staking.rewardPerToken(), (10 * 30 * 1e18 / 5) + (10 * 30 * 1e18 / 10));
        assertEq(staking.userRewardPerTokenPaid(actor3), (10 * 30 * 1e18 / 5) + (10 * 30 * 1e18 / 10));
        assertEq(staking.lastUpdateTime(), startAt + 20);

        // evaluate actor1 position
        assertEq(staking.earned(actor1), 450);

        // evaluate actor2 position
        assertEq(staking.earned(actor2), 150);

        // forward to startAt + 30
        vm.warp(startAt + 30);

        // evaluate staking contract reward balance
        assertEq(rewardToken.balanceOf(address(staking)), initialRewardAllocated);
        assertEq(staking.toDistributeRewards(), initialRewardAllocated - 450 - 150);
        assertEq(staking.owedRewards(), 450 + 150);

        // actor1 claims rewards
        vm.prank(actor1);
        staking.exit();

        // evaluate actor1 position
        assertEq(collection.balanceOf(actor1), stakeAmount);
        assertEq(rewardToken.balanceOf(actor1), 550);

        // evaluate actor2 and actor3 position
        assertEq(staking.earned(actor2), 250);
        assertEq(staking.earned(actor3), 100);

        // evaluate staking contract reward balance
        assertEq(rewardToken.balanceOf(address(staking)), initialRewardAllocated - 550);
        assertEq(staking.toDistributeRewards(), initialRewardAllocated - 550 - 250 - 100);
        assertEq(staking.owedRewards(), 250 + 100);

        // forward to startAt + 40
        vm.warp(startAt + 40);

        // actor2 claims rewards
        vm.prank(actor2);
        staking.exit();

        // evaluate actor2 position
        assertEq(collection.balanceOf(actor2), stakeAmount);
        assertEq(rewardToken.balanceOf(actor2), 400);

        // evaluate actor3 position
        assertEq(staking.earned(actor3), 250);

        // evaluate staking contract reward balance
        assertEq(rewardToken.balanceOf(address(staking)), initialRewardAllocated - 550 - 400);
        assertEq(staking.toDistributeRewards(), initialRewardAllocated - 550 - 400 - 250);
        assertEq(staking.owedRewards(), 250);

        // forward to startAt + 50
        vm.warp(startAt + 50);

        // actor3 claims rewards
        vm.prank(actor3);
        staking.exit();

        // evaluate actor3 position
        assertEq(collection.balanceOf(actor3), stakeAmount);
        assertEq(rewardToken.balanceOf(actor3), 550);

        // evaluate staking contract reward balance
        assertEq(rewardToken.balanceOf(address(staking)), initialRewardAllocated - 550 - 400 - 550);
        assertEq(staking.toDistributeRewards(), initialRewardAllocated - 550 - 400 - 550);
        assertEq(staking.owedRewards(), 0);
        assertEq(staking.totalStaked(), 0);

        // no staking for 100 timestamps
        vm.warp(startAt + 100);

        // reintroduce rewards
        uint256 previousRewardRate = staking.rewardRate();
        console.log("LeftOver", staking.toDistributeRewards() - (endAt - block.timestamp) * previousRewardRate);
        console.log("previousRewardRate", previousRewardRate);

        vm.startPrank(owner);
        staking.increaseRewardAllocation(0);
        vm.stopPrank();
        console.log("newRewardRate", staking.rewardRate());
        assertGt(staking.rewardRate(), previousRewardRate);
    }
}
