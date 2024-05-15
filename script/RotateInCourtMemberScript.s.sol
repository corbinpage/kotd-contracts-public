// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";

contract RotateInCourtMemberScript is Script {
    uint256 public pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function run(address contractAddress, address inAddress, KingOfTheDegens.CourtRole courtRole) public {
        KingOfTheDegens kotd = KingOfTheDegens(payable(contractAddress));
        vm.startBroadcast(pk);
        kotd.rotateInCourtMember(inAddress, courtRole);
        console.log("New address rotated in: %s to courtRole: %d on contractAddress: %s",
            inAddress,
            uint8(courtRole),
            contractAddress
        );
        vm.stopBroadcast();
    }
}