// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import "forge-std/console.sol";

contract DeployVaultScript is Script {
    function run(address assetAddress, address superTokenFactory) public {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        console.log("Asset address: %s", assetAddress);
        console.log("SuperTokenFactory address: %s", superTokenFactory);
        Vault vault = new Vault(assetAddress, superTokenFactory, 30, 1e29, 1e15);
        console.log("KING Vault deployed at: %s", address(vault));
        console.log("KING Total supply: %s", vault.totalSupply());
        vault.initGame();
        console.log("Game started");
        console.log("Superfluid token deployed at: %s", address(vault.superToken()));
        //vault.transferOwnership(0x6Ca74A32F864918a7399d37592438A80Ec7Ec8D9);
        //console.log("Ownership transferred to: %s", vault.owner());
        vm.stopBroadcast();
    }
}