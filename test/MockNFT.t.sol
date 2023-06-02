// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {MockNFT} from "../src/contracts/MockNFT.sol";

contract MockNFTTest is Test {
    MockNFT collection;
    address actor1 = address(0x1);
    address actor2 = address(0x2);

    function setUp() public {
        collection = new MockNFT("MockNFT", "MNFT");
    }

    function test_MockNFTDeploy() public {
        assertEq(collection.name(), "MockNFT");
        assertEq(collection.symbol(), "MNFT");
    }

    function test_MockNFTMint() public {
        collection.mint(actor1, 1);
        assertEq(collection.balanceOf(actor1), 1);
        assertEq(collection.totalSupply(), 1);
    }

    function test_MockNFTTransfer() public {
        collection.mint(actor1, 1);
        vm.prank(actor1);
        collection.transferFrom(actor1, actor2, 0);
        assertEq(collection.balanceOf(actor1), 0);
        assertEq(collection.balanceOf(actor2), 1);
    }
}
