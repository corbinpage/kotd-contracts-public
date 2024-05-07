// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TransferOwnerScript} from "../TransferOwnerScript.s.sol";

contract TransferOwnerTestnetScript is TransferOwnerScript {
    constructor() {
        pk = vm.envUint("TESTNET_DEPLOYER_PRIVATE_KEY");
    }
}