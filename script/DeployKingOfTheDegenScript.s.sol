// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegen} from "../src/KingOfTheDegen.sol";
import "forge-std/console.sol";

contract DeployKingOfTheDegenScript is Script {
    KingOfTheDegen kingOfTheDegen;
    // Settings
    uint256 public immutable gameDurationBlocks = 888300;
    uint256 public immutable minPlayAmount = 1e15;
    uint256 public immutable protocolFee = 1e14;
    uint256 public immutable stormFrequencyBlocks = 1800;
    uint256 public immutable redeemAfterGameEndedBlocks = 2592000;
    uint256[4] public courtBps = [3300, 1400, 700, 450];
    // Starting Court
    address[1] public king = [0xB8D30eF08522BE6A80cC6cbCDf00BE0A9BCE814A];
    address[2] public lords = [0x77B4922Fcc0Fa745Bcd7d76025E682CFfFc9a149, address(3)];
    address[3] public knights = [address(4), address(5), address(6)];
    address[4] public townsfolk = [address(7), address(8), address(9), address(10)];

    function run() public {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        kingOfTheDegen = new KingOfTheDegen(
            gameDurationBlocks,
            minPlayAmount,
            protocolFee,
            stormFrequencyBlocks,
            redeemAfterGameEndedBlocks,
            courtBps
        );
        console.log("KingOfTheDegen Game deployed to: %s", address(kingOfTheDegen));
        startGame();
        //transferOwnership(0x6Ca74A32F864918a7399d37592438A80Ec7Ec8D9);
        vm.stopBroadcast();
    }

    function startGame() private {
        kingOfTheDegen.startGame(
            king,
            lords,
            knights,
            townsfolk
        );
        console.log("Game started");
    }

    function transferOwnership(address newOwner) private {
        kingOfTheDegen.transferOwnership(newOwner);
        console.log("Ownership transferred to: %s", kingOfTheDegen.owner());
    }
}