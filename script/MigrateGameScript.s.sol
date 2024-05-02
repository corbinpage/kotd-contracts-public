// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import "forge-std/console.sol";
import {AlreadyDeployedScript} from "./AlreadyDeployedScript.sol";

contract MigrateGameScript is AlreadyDeployedScript {
    KingOfTheDegens public contractOld = deployedKingOfTheDegens;
    KingOfTheDegens public contractNew = KingOfTheDegens(payable(0x40Ec213312B4BFE20BAA68f7a3899115350A6607));
    address[10] public oldCourtAddresses;
    uint256 public chunkSize = 250;
    address[1] public transferKing;
    address[2] public transferLords;
    address[3] public transferKnights;
    address[4] public transferTownsfolk;


    function run() public {
        setOldCourt();
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint8 courtCount;
        address[] memory degenUsers = vm.parseJsonAddressArray(vm.readFile('script/playerAddresses.json'), '');
        uint256[] memory points = new uint256[](degenUsers.length);
        uint256[] memory stormBlocks = new uint256[](degenUsers.length);
        for (uint256 i = 0;i < degenUsers.length;i++) {
            points[i] = contractOld.getPoints(degenUsers[i]);
            stormBlocks[i] = contractOld.stormBlock(degenUsers[i]);
            // Count Court
            uint256 oldCourtIndex = getOldCourtIndex(degenUsers[i]);
            if (oldCourtIndex != 1010) {
                courtCount++;
            }
        }
        uint256 callsNeeded = degenUsers.length / chunkSize;
        if (degenUsers.length % chunkSize > 0) {
            callsNeeded += 1;
        }
        uint256 storms = contractOld.storms();
        vm.startBroadcast(key);
        for (uint256 i = 0;i < callsNeeded;i++) {
            contractNew.initGameState(
                storms,
                getChunkOf(degenUsers, i + 1),
                getChunkOf(points, i + 1),
                getChunkOf(stormBlocks, i + 1)
            );
        }
        startGame();
        vm.stopBroadcast();
        console.log("Court Count: %d", courtCount);
        console.log("Amount of DEGEN wei: %d", contractOld.totalAssets());
    }

    function getOldCourtIndex(address accountAddress) private view returns (uint256) {
        for (uint256 i = 0;i < oldCourtAddresses.length;i++) {
            if (oldCourtAddresses[i] == accountAddress) {
                return i;
            }
        }
        return 1010;
    }

    function setOldCourt() public {
        oldCourtAddresses[0] = contractOld.king()[0];
        for (uint i = 0; i < 2; i++) {
            oldCourtAddresses[i+1] = contractOld.lords()[i];
        }
        for (uint i = 0; i < 3; i++) {
            oldCourtAddresses[i+3] = contractOld.knights()[i];
        }
        for (uint i = 0; i < 4; i++) {
            oldCourtAddresses[i+6] = contractOld.townsfolk()[i];
        }
    }

    function startGame() private {
        contractNew.startGame(
            [oldCourtAddresses[0]],
            [oldCourtAddresses[1], oldCourtAddresses[2]],
            [oldCourtAddresses[3], oldCourtAddresses[4], oldCourtAddresses[5]],
            [oldCourtAddresses[6], oldCourtAddresses[7], oldCourtAddresses[8], oldCourtAddresses[9]],
            contractOld.gameDurationBlocks(),
            contractOld.gameStartBlock()
        );
        console.log("Game started at block: %d", contractOld.gameStartBlock());
    }

    function getChunkOf(uint256[] memory array, uint256 chunkIndex) public view returns (uint256[] memory) {
        require(chunkIndex > 0, "Chunk index must be greater than 0");
        uint256 start = (chunkIndex - 1) * chunkSize;
        require(array.length > start, "Array does not have enough elements for the chunk index");

        uint256 end = start + chunkSize;
        if (end > array.length) {
            end = array.length;
        }

        uint256 size = end - start;

        uint256[] memory result = new uint256[](size);
        for (uint i = 0; i < size; i++) {
            result[i] = array[start + i];
        }

        return result;
    }

    function getChunkOf(address[] memory array, uint256 chunkIndex) public view returns (address[] memory) {
        require(chunkIndex > 0, "Chunk index must be greater than 0");
        uint256 start = (chunkIndex - 1) * chunkSize;
        require(array.length > start, "Array does not have enough elements for the chunk index");

        uint256 end = start + chunkSize;
        if (end > array.length) {
            end = array.length;
        }

        uint256 size = end - start;

        address[] memory result = new address[](size);
        for (uint i = 0; i < size; i++) {
            result[i] = array[start + i];
        }

        return result;
    }
}