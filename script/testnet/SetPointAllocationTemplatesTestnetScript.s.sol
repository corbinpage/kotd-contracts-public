// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetPointAllocationTemplatesScript} from "../SetPointAllocationTemplatesScript.s.sol";

contract SetPointAllocationTemplatesTestnetScript is SetPointAllocationTemplatesScript {
    constructor() {
        pk = vm.envUint("TESTNET_DEPLOYER_PRIVATE_KEY");
    }
}