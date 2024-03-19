// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import { ISuperfluid, ISuperToken } from "@superfluid-protocol-monorepo/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";



contract VaultTest is Test {
    Vault public vault;

    function setUp() public {
        vault = new Vault(0x4200000000000000000000000000000000000006, 0xf0d5D3FcBFc0009121A630EC8AB67e012117f40c);
    }

    function test_totalSupply() public {
        uint256 ts = vault.totalSupply();
        assertEq(ts, 1000000000);
    }
}
