// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {ISuperfluid, ISuperToken} from "superfluid-contracts/interfaces/superfluid/ISuperfluid.sol";

contract VaultTest is Test {
    Vault public vault;
    address public accountAddress = address(12345);
    event StormTheCastle(address indexed stormAddress, uint256 indexed amountSent);

    function setUp() public {
        vault = new Vault(
            0x4200000000000000000000000000000000000006,
            0xfcF0489488397332579f35b0F711BE570Da0E8f5,
            30,
            1e24,
            1e15
        );
        vault.initGame(
            address(1337),
            [address(11), address(12)],
            [address(13), address(14), address(15)],
            [address(16), address(17), address(18), address(19)]
        );
    }

    function test_totalSupply() public {
        uint256 ts = vault.totalSupply();
        assertEq(ts, 1e24);
    }

    function test_stormTheCastle() public {
        uint256 totalAssetsStart = vault.totalAssets();
        uint256 totalBalanceStart = address(vault).balance;
        // Switch to accountAddress
        hoax(accountAddress);
        // Event
        vm.expectEmit(true, true, false, false);
        emit StormTheCastle(accountAddress, 1e15);
        // Storm the castle
        vault.stormTheCastle{value: 1e15}();
        // Check protocol fee as native
        assertEq(address(vault).balance, totalBalanceStart + 1e14);
        // Check wETH wrapped and added to vault
        assertEq(vault.totalAssets(), totalAssetsStart + 9e14);
        // Make sure account is flagged as storming
        assertEq(vault.storming(accountAddress), true);
    }

}
