// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import "forge-std/console.sol";

contract DeployKingOfTheDegensScript is Script {
    KingOfTheDegens kingOfTheDegens;
    // Settings
    uint256 public immutable gameDurationBlocks = 1339200;
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
    uint256 public immutable pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
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
        vm.startBroadcast(pk);
        kingOfTheDegens = newKingOfTheDegens();
        console.log("KingOfTheDegens Game deployed to: %s", address(kingOfTheDegens));
        startGame(0);
        // Set Trustus address
        kingOfTheDegens.setIsTrusted(trustedSignerAddress, true);
        console.log("Trustus signer added: %s", trustedSignerAddress);
        //transferOwnership(newOwnerAddress);
        vm.stopBroadcast();
    }

    function newKingOfTheDegens() internal virtual returns (KingOfTheDegens) {
        return new KingOfTheDegens(
            courtRoleOdds,
            roleCounts,
            pointAllocationTemplates
        );
    }

    function startGame(uint256 _startBlock) private {
        kingOfTheDegens.startGame(
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
    }

//    function transferOwnership(address newOwner) private {
//        kingOfTheDegens.transferOwnership(newOwner);
//        console.log("Ownership transferred to: %s", kingOfTheDegens.owner());
//    }
}