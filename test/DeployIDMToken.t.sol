// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployIDMToken} from "../script/DeployIDMToken.s.sol";
import {IDMToken} from "../src/IDMToken.sol";

/// @notice The deploy helper's `deploy()` is called directly, with no environment and no broadcast.
contract DeployIDMTokenTest is Test {
    function test_deployMintsTheSupplyToTheScriptCaller() public {
        DeployIDMToken script = new DeployIDMToken();
        IDMToken token = script.deploy();
        assertEq(token.name(), "Intelligent Dance Markets");
        assertEq(token.symbol(), "IDM");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        // `new` inside the script makes the script contract the deployer and so the holder.
        assertEq(token.balanceOf(address(script)), 1_000_000_000 ether);
    }
}
