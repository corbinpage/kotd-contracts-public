// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {Script, console} from "forge-std/Script.sol";

contract SetStormFrequencyScript is Script {
    uint256 public immutable pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function run(address contractAddress, uint256 blocks) public {
        KingOfTheDegens kotd = KingOfTheDegens(payable(contractAddress));
        vm.startBroadcast(pk);
        kotd.setStormFrequency(blocks);
        console.log("Storm Frequency set to: %d on contractAddress: %s", kotd.stormFrequencyBlocks(), contractAddress);
        vm.stopBroadcast();
    }
}