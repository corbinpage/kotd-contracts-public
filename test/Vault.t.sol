// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {ISuperfluid, ISuperToken} from "superfluid-contracts/interfaces/superfluid/ISuperfluid.sol";

contract VaultTest is Test {
    Vault public vault;
    int96 public immutable expectedKingFlowRate = 12731481481481481481481;
    int96 public immutable expectedLordFlowRate = 5401234567901234567901;
    int96 public immutable expectedKnightFlowRate = 2700617283950617283950;
    int96 public immutable expectedTownsfolkFlowRate = 1736111111111111111111;
    event StormTheCastle(address indexed stormAddress, uint256 indexed amountSent);

    function setUp() public {
        vault = new Vault(
            0x4200000000000000000000000000000000000006,
            0xfcF0489488397332579f35b0F711BE570Da0E8f5,
            30,
            1e29,
            1e15
        );
        vault.initGame();
    }

    function test_totalSupply() public {
        uint256 ts = vault.totalSupply();
        assertEq(ts, 1e29);
    }

    function test_flowRate() public {
        assertEq(expectedKingFlowRate, vault.flowRates(Vault.CourtRole.King));
        assertEq(expectedLordFlowRate, vault.flowRates(Vault.CourtRole.Lord));
        assertEq(expectedKnightFlowRate, vault.flowRates(Vault.CourtRole.Knight));
        assertEq(expectedTownsfolkFlowRate, vault.flowRates(Vault.CourtRole.Townsfolk));
    }

    function test_stormTheCastle() public {
        uint256 totalAssetsStart = vault.totalAssets();
        uint256 totalBalanceStart = address(vault).balance;
        hoax(address(12345));
        // Event
        vm.expectEmit(true, true, false, false);
        emit StormTheCastle(address(12345), 1e15);
        // Storm the castle
        Vault.CourtRole courtRole = vault.stormTheCastle{value: 1e15}();
        console.logUint(uint8(courtRole));
        // Check protocol fee as native
        assertEq(address(vault).balance, totalBalanceStart + 1e14);
        // Check wETH wrapped and added to vault
        assertEq(vault.totalAssets(), totalAssetsStart + 9e14);
        // Check flow
        if (courtRole == Vault.CourtRole.King) {
            assertEq(expectedKingFlowRate, vault.readFlowRate(address(12345)));
        } else if (courtRole == Vault.CourtRole.Lord) {
            assertEq(expectedLordFlowRate, vault.readFlowRate(address(12345)));
        } else if (courtRole == Vault.CourtRole.Knight) {
            assertEq(expectedKnightFlowRate, vault.readFlowRate(address(12345)));
        } else {
            assertEq(expectedTownsfolkFlowRate, vault.readFlowRate(address(12345)));
        }
    }
}
