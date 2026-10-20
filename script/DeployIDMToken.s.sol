// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IDMToken} from "../src/IDMToken.sol";

/// @title Deploy helper for IDMToken
/// @notice On the IdentityMD launch the ProjectFactory deploys the token from its creation code, so
/// this script is not part of that flow. It exists for local forks and reviews: `deploy()` is the
/// single, argument-free step the tests exercise, and `run()` only wraps it in a broadcast.
/// @dev The script reads no environment variables and takes no configuration: the token has none.
contract DeployIDMToken is Script {
    /// @notice Deploys the token. The caller of this function becomes the holder of the whole supply.
    function deploy() public returns (IDMToken token) {
        token = new IDMToken();
    }

    /// @notice Broadcast wrapper. Which account signs is the operator's choice on the command line.
    function run() external returns (IDMToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
