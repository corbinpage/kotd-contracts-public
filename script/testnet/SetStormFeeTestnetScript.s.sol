// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetStormFeeScript} from "../SetStormFeeScript.s.sol";

contract SetStormFeeTestnetScript is SetStormFeeScript {
    constructor() {
        pk = vm.envUint("TESTNET_DEPLOYER_PRIVATE_KEY");
    }
}