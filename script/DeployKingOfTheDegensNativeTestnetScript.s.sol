// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegensNative} from "../src/KingOfTheDegensNative.sol";
import {DeployKingOfTheDegensScript} from "./DeployKingOfTheDegensScript.s.sol";
import {DeployKingOfTheDegensNativeScript} from "./DeployKingOfTheDegensNativeScript.s.sol";
import "forge-std/console.sol";

contract DeployKingOfTheDegensNativeTestnetScript is DeployKingOfTheDegensNativeScript {

    constructor() {
        stormFrequencyBlocks = 1;
        king = [address(1)];
        lords = [address(2), address(3)];
        knights = [address(4), address(5), address(6)];
        townsfolk = [address(7), address(8), address(9), address(10)];
    }

}