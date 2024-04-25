// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {KingOfTheDegens} from "./KingOfTheDegens.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract KingOfTheDegensNative is KingOfTheDegens {
    uint256 public protocolFeeBalance;

    constructor(
        uint256 _gameDurationBlocks,
        uint256 _minPlayAmount,
        uint256 _protocolFee,
        uint256 _stormFrequencyBlocks,
        uint256 _redeemAfterGameEndedBlocks,
        uint256[5] memory _courtRolePointAllocation,
        uint256[4] memory _courtRoleOdds,
        uint256[5] memory _roleCounts
    )
    KingOfTheDegens(
    _gameDurationBlocks,
    _minPlayAmount,
    _protocolFee,
    _stormFrequencyBlocks,
    _redeemAfterGameEndedBlocks,
    _courtRolePointAllocation,
    _courtRoleOdds,
    _roleCounts
    )
    {

    }

    function redeem() public override whenNotPaused {
        if (isGameActive()) revert GameIsActive();
        if (_hasRedeemEnded()) revert RedeemEnded();
        if (address(this).balance == 0) revert RedeemEnded();
        // Close out stream if this user still in court
        if (courtRoles[msg.sender] != CourtRole.None && roleStartBlock[msg.sender] < gameEndBlock()) {
            updatePointsBalance(msg.sender, courtRoles[msg.sender]);
        }
        if (pointsBalance[msg.sender] == 0) revert InsufficientBalance();
        uint256 nativeToSend = convertPointsToAssets(pointsBalance[msg.sender]);
        SafeTransferLib.safeTransferETH(msg.sender, nativeToSend);
        emit Redeemed(msg.sender, nativeToSend, pointsBalance[msg.sender]);
        // Clear points balance
        pointsBalance[msg.sender] = 0;
    }

    function depositToTreasury(uint256 nativeIn) internal override {
        gameAssets += (nativeIn - protocolFee);
        protocolFeeBalance += protocolFee;
    }

    function collectProtocolFees() public override onlyOwner {
        if (protocolFeeBalance == 0) revert InsufficientBalance();
        if (!isGameEnded()) revert GameIsActive();
        SafeTransferLib.safeTransferETH(msg.sender, protocolFeeBalance);
        protocolFeeBalance = 0;
    }

    function protocolRedeem() public override onlyOwner {
        if (!_hasRedeemEnded()) revert RedeemStillActive();
        SafeTransferLib.safeTransferETH(owner, address(this).balance);
    }

    receive() external payable override {
        gameAssets += msg.value;
    }
}
