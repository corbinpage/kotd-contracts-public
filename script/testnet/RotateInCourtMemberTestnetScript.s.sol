// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RotateInCourtMemberScript} from "../RotateInCourtMemberScript.s.sol";

contract RotateInCourtMemberTestnetScript is RotateInCourtMemberScript {
    constructor() {
        pk = vm.envUint("TESTNET_DEPLOYER_PRIVATE_KEY");
    }
}