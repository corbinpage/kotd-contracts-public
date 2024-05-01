// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {AlreadyDeployedScript} from "./AlreadyDeployedScript.sol";

contract StartGameScript is AlreadyDeployedScript {
    uint256 gameDurationBlocks = 1339200;
    // Starting Court
    address[1] public king = [0x2943E07Ca68FeBC79533d321F5D427136995ECB6];
    address[2] public lords = [
        0x0D9A5b29Db1A5d109a3f6E3D3D5141691461d44d,
        0x7f35303825129989C8B20CF99bafA5E8563e05E6
    ];
    address[3] public knights = [
        0x8C73622e3789d9d0297a9bEAC841bC9F153B1705,
        0x8C50b29a763E2BabBb6b0AE8A1133D59a537e48c,
        0xfFD680D72E71Bd125ee68E98e020beB43bc81D64
    ];
    address[4] public townsfolk = [
        0xFE8E6bd85e0c0869f8bEe9e67398eB4088c92d07,
        0x6f46d90553141D464C000D76e41d0d5380Fc0B23,
        0x4a3e6E66f8C32bC05A50879f872B1177A1573CDF,
        0x4b91475af6eC45997794b513349aADf7772De95a
    ];

    function run() public {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        deployedKingOfTheDegens.startGame(
            king,
            lords,
            knights,
            townsfolk,
            gameDurationBlocks,
            0
        );
        console.log("Game started");
        vm.stopBroadcast();
    }
}