// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {Script, console} from "forge-std/Script.sol";

contract TransferOwnerScript is Script {
    uint256 public pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function run(address contractAddress, address newOwner) public {
        KingOfTheDegens kotd = KingOfTheDegens(payable(contractAddress));
        vm.startBroadcast(pk);
        kotd.transferOwnership(newOwner);
        console.log("Ownership transferred to: %s on contractAddress: %s", kotd.owner(), contractAddress);
        vm.stopBroadcast();
    }
}