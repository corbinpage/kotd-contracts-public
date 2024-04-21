// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {AlreadyDeployedScript} from "./AlreadyDeployedScript.sol";

contract TransferOwnerScript is AlreadyDeployedScript {
    function run(address newOwner) public {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        deployedKingOfTheDegens.transferOwnership(newOwner);
        console.log("Ownership transferred to: %s", deployedKingOfTheDegens.owner());
        vm.stopBroadcast();
    }
}