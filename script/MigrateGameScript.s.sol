// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {KingOfTheDegens as KingOfTheDegensOld} from "../src/KingOfTheDegensOld.sol";
import "forge-std/console.sol";

contract MigrateGameScript is Script {
    KingOfTheDegensOld public contractOld = KingOfTheDegensOld(payable(0x9654E8131B6a37FFD3C57c167b218f54AFc58e66));
    KingOfTheDegens public contractNew = KingOfTheDegens(payable(0x12BE8ef11d78a09bE19Fe8680cdA0538Aef87E9c));
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
        uint256[] memory roleStartBlocks = vm.parseJsonUintArray(vm.readFile('script/startRoleBlock.json'), '');
        for (uint256 i = 0;i < degenUsers.length;i++) {
            uint256 _points = contractOld.pointsBalance(degenUsers[i]);
            uint256 _stormBlock = contractOld.stormBlock(degenUsers[i]);
            uint256 oldCourtIndex = getOldCourtIndex(degenUsers[i]);
            if (oldCourtIndex != 1010) {
                courtCount++;
                // Add points up to current block
                _points += calculatePointsEarned(
                    roleStartBlocks[uint256(oldCourtIndex)],
                    block.number,
                    uint8(contractNew.getCourtRoleFromAddressesIndex(uint256(oldCourtIndex)))
                );
            }
            points[i] = _points;
            stormBlocks[i] = _stormBlock;
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
        oldCourtAddresses[0] = contractOld.king(0);
        for (uint i = 0; i < 2; i++) {
            oldCourtAddresses[i+1] = contractOld.lords(i);
        }
        for (uint i = 0; i < 3; i++) {
            oldCourtAddresses[i+3] = contractOld.knights(i);
        }
        for (uint i = 0; i < 4; i++) {
            oldCourtAddresses[i+6] = contractOld.townsfolk(i);
        }
    }

    function calculatePointsEarned(
        uint256 startBlockNumber,
        uint256 endBlockNumber,
        uint8 courtRoleInt
    ) private view returns (uint256) {
        endBlockNumber = endBlockNumber > contractOld.gameEndBlock() ? contractOld.gameEndBlock() : endBlockNumber;
        if (startBlockNumber == 0 || endBlockNumber <= startBlockNumber) return 0;
        return (endBlockNumber - startBlockNumber) * contractOld.getPointsPerBlock(KingOfTheDegensOld.CourtRole(courtRoleInt));
    }

    function startGame() private {
        contractNew.startGame(
            [oldCourtAddresses[0]],
            [oldCourtAddresses[1], oldCourtAddresses[2]],
            [oldCourtAddresses[3], oldCourtAddresses[4], oldCourtAddresses[5]],
            [oldCourtAddresses[6], oldCourtAddresses[7], oldCourtAddresses[8], oldCourtAddresses[9]],
            contractOld.gameStartBlock()
        );
        console.log("Game started at block: %d", block.number);
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