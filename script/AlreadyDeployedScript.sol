// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {Script, console} from "forge-std/Script.sol";

contract AlreadyDeployedScript is Script {
    KingOfTheDegens deployedKingOfTheDegens = KingOfTheDegens(payable(0x12BE8ef11d78a09bE19Fe8680cdA0538Aef87E9c));
}