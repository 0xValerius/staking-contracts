// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {MockNFT} from "../src/contracts/MockNFT.sol";

contract MockNFTTest is Test {
    MockNFT nft;
    address actor1 = address(0x1);
    address actor2 = address(0x2);

    function setUp() public {
        nft = new MockNFT("MockNFT", "MNFT");
    }

    function test_MockNFTDeploy() public {
        assertEq(nft.name(), "MockNFT");
        assertEq(nft.symbol(), "MNFT");
    }

    function test_MockNFTMint() public {
        nft.mint(actor1, 1);
        assertEq(nft.balanceOf(actor1), 1);
        assertEq(nft.totalSupply(), 1);
    }
}
