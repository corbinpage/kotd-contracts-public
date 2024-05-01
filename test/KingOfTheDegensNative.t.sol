// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {KingOfTheDegensNative} from "../src/KingOfTheDegensNative.sol";
import {Trustus} from "trustus/Trustus.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {KingOfTheDegensTest} from "./KingOfTheDegens.t.sol";

contract KingOfTheDegensNativeTest is KingOfTheDegensTest {
    function setUp() public override {
        // Deploy
        kingOfTheDegens = new KingOfTheDegensNative(
            courtRoleOdds,
            roleCounts,
            pointAllocationTemplates
        );
        // Init
        kingOfTheDegens.startGame(
            king,
            lords,
            knights,
            townsfolk,
            gameDurationBlocks,
            0
        );
        // Set Trustus address
        kingOfTheDegens.setIsTrusted(trustedSignerAddress, true);
    }

    function getProtocolFeeBalance() internal view override returns (uint256) {
        return KingOfTheDegensNative(payable(kingOfTheDegens)).protocolFeeBalance();
    }

    function getAddressBalance(address accountAddress) internal view override returns (uint256) {
        return address(accountAddress).balance;
    }

    function test_DepositDegen() public override {
        // Skip for native
    }

    function test_SendETH() public override {
        address friendlyUser = address(123123123456);
        uint256 nativeBalanceBefore = getAddressBalance(address(kingOfTheDegens));
        uint256 protocolFeeBalanceBefore = getProtocolFeeBalance();
        hoax(friendlyUser);
        uint256 balanceBefore = address(friendlyUser).balance;
        SafeTransferLib.safeTransferETH(address(kingOfTheDegens), 1 ether);
        assertEq(balanceBefore, address(friendlyUser).balance + 1 ether);
        assertEq(protocolFeeBalanceBefore + getProtocolFee(1 ether), getProtocolFeeBalance());
        assertEq(address(kingOfTheDegens).balance, nativeBalanceBefore + 1 ether);
    }
}