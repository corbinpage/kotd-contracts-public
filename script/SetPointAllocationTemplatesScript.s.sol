// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {Script, console} from "forge-std/Script.sol";

contract SetPointAllocationTemplatesScript is Script {
    uint256 public immutable pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    uint256[7][5] public newPointAllocationTemplates = [
        [3100, 1400, 600, 350, 300, 300, 300],
        [4300, 1100, 500, 250, 0, 1000, 0],
        [3000, 1100, 800, 250, 400, 1000, 0],
        [2200, 1000, 800, 550, 600, 600, 0],
        [0, 1100, 1600, 550, 0, 800, 0]
    ];

    function run(address contractAddress) public {
        KingOfTheDegens kotd = KingOfTheDegens(payable(contractAddress));
        vm.startBroadcast(pk);
        kotd.setPointAllocationTemplates(newPointAllocationTemplates);
        console.log("Set new point allocation templates on contractAddress: %s", contractAddress);
        vm.stopBroadcast();
    }
}