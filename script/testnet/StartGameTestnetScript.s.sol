// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {StartGameScript} from "../StartGameScript.s.sol";

contract StartGameTestnetScript is StartGameScript {

    constructor() {
        king = [address(1)];
        lords = [address(2), address(3)];
        knights = [address(4), address(5), address(6)];
        townsfolk = [address(7), address(8), address(9), address(10)];
        pk = vm.envUint("TESTNET_DEPLOYER_PRIVATE_KEY");
    }

}