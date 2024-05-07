// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {Script, console} from "forge-std/Script.sol";

contract StartGameScript is Script {
    uint256 public gameDurationBlocks = 1339200;
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
    uint256 public immutable pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function run(address contractAddress, uint256 _startBlock) public {
        KingOfTheDegens kotd = KingOfTheDegens(payable(contractAddress));
        vm.startBroadcast(pk);
        kotd.startGame(
            king,
            lords,
            knights,
            townsfolk,
            gameDurationBlocks,
            _startBlock
        );
        console.log("Game started at block: %d with duration of: %d blocks",
            _startBlock == 0 ? block.number : _startBlock,
            gameDurationBlocks
        );
        vm.stopBroadcast();
    }
}