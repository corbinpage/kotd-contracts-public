// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";

contract VaultTest is Test {
    Vault public vault;

    function setUp() public {
        vault = new Vault(0x4200000000000000000000000000000000000006, 0xfcF0489488397332579f35b0F711BE570Da0E8f5);
    }

    function test_totalSupply() public {
        uint256 ts = vault.totalSupply();
        assertEq(ts, 100000000000);
    }

}
