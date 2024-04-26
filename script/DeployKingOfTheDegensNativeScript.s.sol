// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegensNative} from "../src/KingOfTheDegensNative.sol";
import "forge-std/console.sol";

contract DeployKingOfTheDegensScript is Script {
    KingOfTheDegensNative public kingOfTheDegens;
    // Settings
    uint256 public immutable gameDurationBlocks = 888300;
    uint256 public immutable minPlayAmount = 1e15;
    uint256 public immutable protocolFee = 1e14;
    uint256 public immutable stormFrequencyBlocks = 1;
    uint256 public immutable redeemAfterGameEndedBlocks = 2592000;
    uint256[5][5] public pointAllocationTemplates = [
        [3100, 1400, 600, 350, 900],
        [4900, 1300, 500, 250, 0],
        [3100, 1400, 900, 350, 0],
        [2400, 1500, 800, 550, 0],
        [0, 1400, 1900, 375, 0]
    ];
    uint256[4] public courtRoleOdds = [500, 1000, 2500, 6000];
    uint256[5] public roleCounts = [1, 2, 3, 4, 1];
    uint256 public immutable trustedSignerPrivateKey = vm.envUint("TRUSTUS_SIGNER_PRIVATE_KEY");
    address public immutable trustedSignerAddress = vm.addr(trustedSignerPrivateKey);
//    address public immutable newOwnerAddress = 0x6Ca74A32F864918a7399d37592438A80Ec7Ec8D9;
    // Starting Court
    address[1] public king = [address(1)];
    address[2] public lords = [address(2), address(3)];
    address[3] public knights = [address(4), address(5), address(6)];
    address[4] public townsfolk = [address(7), address(8), address(9), address(10)];

    function run() public {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        kingOfTheDegens = new KingOfTheDegensNative(
            gameDurationBlocks,
            minPlayAmount,
            protocolFee,
            stormFrequencyBlocks,
            redeemAfterGameEndedBlocks,
            courtRoleOdds,
            roleCounts,
            pointAllocationTemplates
        );
        console.log("KingOfTheDegens Game deployed to: %s", address(kingOfTheDegens));
        startGame();
        // Set Trustus address
        kingOfTheDegens.setIsTrusted(trustedSignerAddress, true);
        console.log("Trustus signer added: %s", trustedSignerAddress);
        //transferOwnership(newOwnerAddress);
        vm.stopBroadcast();
    }

    function startGame() private {
        kingOfTheDegens.startGame(
            king,
            lords,
            knights,
            townsfolk,
            0
        );
        console.log("Game started");
    }

//    function transferOwnership(address newOwner) private {
//        kingOfTheDegens.transferOwnership(newOwner);
//        console.log("Ownership transferred to: %s", kingOfTheDegens.owner());
//    }
}