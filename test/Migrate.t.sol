// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {KingOfTheDegens as KingOfTheDegensOld} from "../src/KingOfTheDegensOld.sol";
import {Trustus} from "trustus/Trustus.sol";

contract MigrateTest is Test {
    KingOfTheDegensOld public contractOld = KingOfTheDegensOld(payable(0x9654E8131B6a37FFD3C57c167b218f54AFc58e66));
    KingOfTheDegens public contractNew = KingOfTheDegens(payable(0x12BE8ef11d78a09bE19Fe8680cdA0538Aef87E9c));
    address[10] public oldCourtAddresses;

    function setUp() public {
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

    function test_InitialCourtSize() public {
        assertEq(isCourtEmpty(contractNew.getCourtAddresses()), true);
        assertEq(isCourtEmpty(oldCourtAddresses), false);
    }

    function test_InitialGameStatus() public {
        // New & Old should match
        assertEq(contractNew.gameDurationBlocks(), contractOld.gameDurationBlocks());
        assertEq(contractNew.minPlayAmount(), contractOld.minPlayAmount());
        assertEq(contractNew.protocolFee(), contractOld.protocolFee());
        assertEq(contractNew.stormFrequencyBlocks(), contractOld.stormFrequencyBlocks());
        // Game Active on contractOld
        assertEq(contractOld.isGameActive(), true);
        // Game Not Active on contractNew
        assertEq(contractNew.isGameActive(), false);
        assertEq(contractNew.gameStartBlock(), 0);
    }

    function test_InitGame() public {
        uint8 courtCount;
        address[] memory degenUsers = vm.parseJsonAddressArray(vm.readFile('test/playerAddresses.json'), '');
        uint256[] memory points = new uint256[](degenUsers.length);
        uint256[] memory stormBlocks = new uint256[](degenUsers.length);
        for (uint256 i = 0;i < degenUsers.length;i++) {
            uint256 _points = contractOld.pointsBalance(degenUsers[i]);
            uint256 _stormBlock = contractOld.stormBlock(degenUsers[i]);
            if (isInOldCourt(degenUsers[i])) {
                courtCount++;
            }
            points[i] = _points;
            stormBlocks[i] = _stormBlock;
        }
        assertEq(points.length, degenUsers.length);
        assertEq(stormBlocks.length, degenUsers.length);
        assertEq(courtCount, 10);
        assertGt(points[degenUsers.length - 1], 0);
        vm.startPrank(0xf0d5D3FcBFc0009121A630EC8AB67e012117f40c);
        contractNew.initGameState(contractOld.storms(), degenUsers, points, stormBlocks);
        vm.stopPrank();
        assertEq(contractNew.pointsBalance(degenUsers[0]), contractOld.pointsBalance(degenUsers[0]));
    }

    function isCourtEmpty(address[10] memory courtAddresses) private pure returns (bool) {
        for (uint256 i = 0;i < 10;i++) {
            if (courtAddresses[i] != address(0)) {
                return false;
            }
        }
        return true;
    }

    function isInOldCourt(address accountAddress) private view returns (bool) {
        for (uint256 i = 0;i < oldCourtAddresses.length;i++) {
            if (oldCourtAddresses[i] == accountAddress) {
                return true;
            }
        }
        return false;
    }

//    function test_TransferGameState() public {

//        newContract.startGame(king, lords, knights, townsfolk, kingOfTheDegens.gameStartBlock());

//        // Transfer Game Assets
//        deal(address(newContract.degenToken()), userAddress, kingOfTheDegens.totalAssets());
//        vm.startPrank(userAddress);
//        newContract.degenToken().approve(address(newContract), kingOfTheDegens.totalAssets());
//        newContract.depositDegenToGameAssets(kingOfTheDegens.totalAssets());
//        vm.stopPrank();
//        assertEq(newContract.totalAssets(), kingOfTheDegens.totalAssets());
//    }

//        assertEq(newContract.gameEndBlock(), kingOfTheDegens.gameEndBlock());

}