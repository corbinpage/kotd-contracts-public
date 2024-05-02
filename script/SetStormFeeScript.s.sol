// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {AlreadyDeployedScript} from "./AlreadyDeployedScript.sol";

contract SetStormFeeScript is AlreadyDeployedScript {
    function run() public {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        deployedKingOfTheDegens.setStormFee(1000000000000000);
        //console.log("Ownership transferred to: %s", deployedKingOfTheDegens.owner());
        vm.stopBroadcast();
    }
}