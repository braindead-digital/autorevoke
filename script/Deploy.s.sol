// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {AutoRevoke} from "../src/AutoRevoke.sol";

contract DeployScript is Script {
    function run() external returns (AutoRevoke) {
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        vm.startBroadcast();
        AutoRevoke autoRevoke = new AutoRevoke{salt: salt}();
        vm.stopBroadcast();

        return autoRevoke;
    }
}
