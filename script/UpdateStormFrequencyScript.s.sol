// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import "forge-std/console.sol";
import {AlreadyDeployedScript} from "./AlreadyDeployedScript.sol";

contract UpdateStormFrequencyScript is AlreadyDeployedScript {
    function run(uint256 blocks) public {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        deployedKingOfTheDegens.setStormFrequency(blocks);
        vm.stopBroadcast();
    }
}