// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {KingOfTheDegensNative} from "../src/KingOfTheDegensNative.sol";
import {DeployKingOfTheDegensScript} from "./DeployKingOfTheDegensScript.s.sol";
import "forge-std/console.sol";

contract DeployKingOfTheDegensNativeScript is DeployKingOfTheDegensScript {

    function newKingOfTheDegens() internal override returns (KingOfTheDegens) {
        return new KingOfTheDegensNative(
            gameDurationBlocks,
            stormFee,
            protocolFeePercentage,
            stormFrequencyBlocks,
            redeemAfterGameEndedBlocks,
            courtRoleOdds,
            roleCounts,
            pointAllocationTemplates
        );
    }
}