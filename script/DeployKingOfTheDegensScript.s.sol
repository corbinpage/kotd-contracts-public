// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import "forge-std/console.sol";

contract DeployKingOfTheDegensScript is Script {
    KingOfTheDegens kingOfTheDegens;
    // Settings
    uint256 public immutable gameDurationBlocks = 888300;
    uint256 public immutable stormFee = 1e15;
    uint256 public immutable protocolFeePercentage = 1000;
    uint256 public immutable stormFrequencyBlocks = 1800;
    uint256 public immutable redeemAfterGameEndedBlocks = 2592000;
    uint256[7][5] public pointAllocationTemplates = [
        [3100, 1400, 600, 350, 300, 300, 300],
        [4900, 1300, 500, 250, 0, 0, 0],
        [3100, 1400, 900, 350, 0, 0, 0],
        [2400, 1500, 800, 550, 0, 0, 0],
        [0, 1400, 1900, 375, 0, 0, 0]
    ];
    uint256[4] public courtRoleOdds = [500, 1000, 2500, 6000];
    uint256[7] public roleCounts = [1, 2, 3, 4, 1, 1, 1];
    uint256 public immutable trustedSignerPrivateKey = vm.envUint("TRUSTUS_SIGNER_PRIVATE_KEY");
    address public immutable trustedSignerAddress = vm.addr(trustedSignerPrivateKey);
//    address public immutable newOwnerAddress = 0x6Ca74A32F864918a7399d37592438A80Ec7Ec8D9;
    // Starting Court
    address[1] public king = [
        0xB8D30eF08522BE6A80cC6cbCDf00BE0A9BCE814A
    ];
    address[2] public lords = [
        0xea24Ba5441F85F71236596888206B6861914AAD1,
        0xE7874ea9AEe21E3EaDBEB8AFEDf0370067ef632C
    ];
    address[3] public knights = [
        0x77B4922Fcc0Fa745Bcd7d76025E682CFfFc9a149,
        0x869eC00FA1DC112917c781942Cc01c68521c415e,
        0x1160E5E2D9D301a81cF5e9280174BB93DDcCd606
    ];
    address[4] public townsfolk = [
        0xadA511478a5D5F7a5D8c59b5bb443a5452087d70,
        0xBcf86ab45846E385fBC92BC8a8A598766af2c015,
        0x8C2538fd519109CFBB1Db7e240ad9Df94fD05971,
        0xF6Ee39EfDB14909Da1e5B6121c5c67bC1Cf0Db31
    ];

    function run() public {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        kingOfTheDegens = newKingOfTheDegens();
        console.log("KingOfTheDegens Game deployed to: %s", address(kingOfTheDegens));
        startGame();
        // Set Trustus address
        kingOfTheDegens.setIsTrusted(trustedSignerAddress, true);
        console.log("Trustus signer added: %s", trustedSignerAddress);
        //transferOwnership(newOwnerAddress);
        vm.stopBroadcast();
    }

    function newKingOfTheDegens() internal virtual returns (KingOfTheDegens) {
        return new KingOfTheDegens(
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