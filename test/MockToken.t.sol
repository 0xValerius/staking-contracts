// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {MockToken} from "../src/contracts/MockToken.sol";

contract MockTokenTest is Test {
    MockToken token;
    address actor1 = address(0x1);

    function setUp() public {
        token = new MockToken("MockToken", "MTK");
        vm.prank(actor1);
    }

    function test_MockTokenDeploy() public {
        assertEq(token.name(), "MockToken");
        assertEq(token.symbol(), "MTK");
    }

    function test_MockTokenMint() public {
        token.mint(actor1, 100);
        assertEq(token.balanceOf(actor1), 100);
        assertEq(token.totalSupply(), 100);
    }
}
