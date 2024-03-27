// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {KingOfTheCastle} from "../src/KingOfTheCastle.sol";
import {ISuperfluid, ISuperToken} from "superfluid-contracts/interfaces/superfluid/ISuperfluid.sol";

contract KingOfTheCastleTest is Test {
    KingOfTheCastle public kingOfTheCastle;

    // Settings
    address public immutable assetAddress = 0x4200000000000000000000000000000000000006;
    address public immutable superTokenFactoryAddress = 0xfcF0489488397332579f35b0F711BE570Da0E8f5;
    uint8 public immutable gameDurationDays = 21;
    uint256 public immutable tokenTotalSupply = 1e29;
    uint256 public immutable minPlayAmount = 1e15;
    uint256 public immutable protocolFee = 1e14;
    string public tokenName = 'King Token';
    string public tokenSymbol = 'KING';
    uint256[4] public courtBps = [3300, 1400, 700, 450];
    // Starting Court
    address[1] public king = [address(1)];
    address[2] public lords = [address(2), address(3)];
    address[3] public knights = [address(4), address(5), address(6)];
    address[4] public townsfolk = [address(7), address(8), address(9), address(10)];

    function setUp() public {
        // Deploy
        kingOfTheCastle = new KingOfTheCastle(
            assetAddress,
            superTokenFactoryAddress,
            gameDurationDays,
            tokenTotalSupply,
            minPlayAmount,
            protocolFee,
            tokenName,
            tokenSymbol,
            courtBps
        );
        // Init
        kingOfTheCastle.initGame(
            king,
            lords,
            knights,
            townsfolk
        );
    }

    function test_totalSupply() public {
        uint256 ts = kingOfTheCastle.totalSupply();
        assertEq(ts, tokenTotalSupply);
    }

    function test_stormTheCastle() public {
        vm.recordLogs();
        uint256 totalAssetsStart = kingOfTheCastle.totalAssets();
        uint256 totalBalanceStart = address(kingOfTheCastle).balance;
        hoax(address(12345));
        // Storm the castle
        kingOfTheCastle.stormTheCastle{value: 1e15}(0, 0);
        // Event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 stormEventHash = keccak256("StormTheCastle(address,uint8,uint256,uint256)");
        uint256 stormTopic = 0;
        for (uint256 i = 0;i < entries.length;i++) {
            if (entries[i].topics[0] == stormEventHash) {
                stormTopic = i;
            }
        }
        assertEq(entries[stormTopic].topics[0], stormEventHash);
        assertEq(address(uint160(uint256(entries[stormTopic].topics[1]))), address(12345));
        uint8 courtRole = uint8(uint256(entries[stormTopic].topics[2]));
        assertGe(courtRole, 0);
        assertLe(courtRole, 5);
        assertEq(uint256(entries[stormTopic].topics[3]), 1e15);
        console.logUint(courtRole);

        // Check protocol fee as native
        assertEq(address(kingOfTheCastle).balance, totalBalanceStart + 1e14);
        // Check wETH wrapped and added to vault
        assertEq(kingOfTheCastle.totalAssets(), totalAssetsStart + 9e14);
        // Check flow
        if (courtRole == 1) {
            assertEq(kingOfTheCastle.getCourtRoleFlowRate(KingOfTheCastle.CourtRole.King), kingOfTheCastle.readFlowRate(address(12345)));
        } else if (courtRole == 2) {
            assertEq(kingOfTheCastle.getCourtRoleFlowRate(KingOfTheCastle.CourtRole.Lord), kingOfTheCastle.readFlowRate(address(12345)));
        } else if (courtRole == 3) {
            assertEq(kingOfTheCastle.getCourtRoleFlowRate(KingOfTheCastle.CourtRole.Knight), kingOfTheCastle.readFlowRate(address(12345)));
        } else {
            assertEq(kingOfTheCastle.getCourtRoleFlowRate(KingOfTheCastle.CourtRole.Townsfolk), kingOfTheCastle.readFlowRate(address(12345)));
        }
    }
}
