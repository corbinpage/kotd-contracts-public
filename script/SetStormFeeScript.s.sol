// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";

contract SetStormFeeScript is Script {
    uint256 public immutable pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function run(address contractAddress, uint256 _stormFee) public {
        KingOfTheDegens kotd = KingOfTheDegens(payable(contractAddress));
        vm.startBroadcast(pk);
        kotd.setStormFee(_stormFee);
        console.log("Storm Fee set to: %d on contractAddress: %s", kotd.stormFee(), contractAddress);
        vm.stopBroadcast();
    }
}