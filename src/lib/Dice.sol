//SPDX-License-Identifier: None
pragma solidity ^0.8.13;

import "./UniformRandomNumber.sol";

library Dice {
    function rollDiceSet(uint8 resultSetSize, uint upperLimit, uint seed) internal pure returns (uint) {
        uint sum;
        for (uint i = 0;i < resultSetSize;i++) {
            sum += UniformRandomNumber.uniform(
                uint(keccak256(abi.encode(seed, i))),
                upperLimit
            ) + 1;
        }
        return sum;
    }
}