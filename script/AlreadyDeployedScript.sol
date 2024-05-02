// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {Script, console} from "forge-std/Script.sol";

contract AlreadyDeployedScript is Script {
    KingOfTheDegens deployedKingOfTheDegens = KingOfTheDegens(payable(0xea868EB203BA9D674CC0AB249A377e90B5997e21));
}