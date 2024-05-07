// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetStormFrequencyScript} from "../SetStormFrequencyScript.s.sol";

contract SetStormFrequencyTestnetScript is SetStormFrequencyScript {
    constructor() {
        pk = vm.envUint("TESTNET_DEPLOYER_PRIVATE_KEY");
    }
}