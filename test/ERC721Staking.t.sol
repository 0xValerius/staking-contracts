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
        deal(address(rewardToken), owner, initialMintAmount, true);
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
        assertEq(rewardToken.totalSupply(), initialMintAmount);
        assertEq(rewardToken.balanceOf(owner), initialMintAmount);
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
}
