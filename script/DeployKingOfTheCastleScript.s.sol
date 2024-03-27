// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {KingOfTheCastle} from "../src/KingOfTheCastle.sol";
import "forge-std/console.sol";

contract DeployKingOfTheCastleScript is Script {
    KingOfTheCastle kingOfTheCastle;
    // Settings
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

    function run(address assetAddress, address superTokenFactory) public {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        console.log("Underlying asset address: %s", assetAddress);
        console.log("SuperTokenFactory address: %s", superTokenFactory);
        kingOfTheCastle = new KingOfTheCastle(
            assetAddress,
            superTokenFactory,
            gameDurationDays,
            tokenTotalSupply,
            minPlayAmount,
            protocolFee,
            tokenName,
            tokenSymbol,
            courtBps
        );
        console.log("KingOfTheCastle Game deployed at: %s", address(kingOfTheCastle));
        console.log("KING token Total supply: %s", kingOfTheCastle.totalSupply());
        //initGame();
        //transferOwnership(0x6Ca74A32F864918a7399d37592438A80Ec7Ec8D9);
        vm.stopBroadcast();
    }

    function initGame() private {
        kingOfTheCastle.initGame(
            king,
            lords,
            knights,
            townsfolk
        );
        console.log("Game started");
        console.log("Superfluid token deployed at: %s", address(kingOfTheCastle.superToken()));
    }

    function transferOwnership(address newOwner) private {
        kingOfTheCastle.transferOwnership(newOwner);
        console.log("Ownership transferred to: %s", kingOfTheCastle.owner());
    }
}