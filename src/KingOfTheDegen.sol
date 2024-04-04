// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Dice} from "./lib/Dice.sol";

contract KingOfTheDegen is Owned {
    uint256 public immutable gameDurationBlocks;
    uint256 public immutable minPlayAmount;
    uint256 public immutable protocolFee;
    uint256 public immutable stormFrequencyBlocks;
    uint256 public immutable redeemAfterGameEndedBlocks;
    uint256 public immutable totalPointsPerBlock = 1e18;
    mapping(CourtRole => uint256) public courtBps;
    mapping(address => uint256) public stormBlock;
    mapping(address => CourtRole) public courtRoles;
    mapping(address => uint256) public pointsBalance;
    mapping(address => uint256) private roleStartBlock;
    uint256 public storms;
    uint256 public gameStartBlock;
    uint256 public protocolFeeBalance;
    // Court
    address[1] public king;
    address[2] public lords;
    address[3] public knights;
    address[4] public townsfolk;
    // Role
    enum CourtRole {
        None,
        King,
        Lord,
        Knight,
        Townsfolk
    }
    // Events
    event StormTheCastle(
        address indexed accountAddress,
        uint8 indexed courtRole,
        uint256 indexed amountSent,
        uint256 fid
    );
    event Redeemed(address indexed accountAddress, uint256 indexed amountRedeemed, uint256 indexed pointsRedeemed);
    // Custom Errors
    error BadZeroAddress();
    error GameNotActive(uint256 gameStartBlock, uint256 gameEndBlock, uint256 currentBlock);
    error GameStillActive();
    error RedeemStillActive(uint256 redeemEndedBlock);
    error RedeemEnded();
    error InsufficientFunds(uint256 valueSent);
    error TooFrequentStorms(uint256 nextBlockAllowed, uint256 currentBlockNumber);
    error AlreadyCourtMember(address accountAddress, CourtRole courtRole);
    error BadCourtRole(CourtRole courtRole);
    error NoNativeToSend();
    error CourtRoleMismatch(address accountAddress, CourtRole courtRole, CourtRole expectedCourtRole);

    constructor(
        uint256 _gameDurationBlocks,
        uint256 _minPlayAmount,
        uint256 _protocolFee,
        uint256 _stormFrequencyBlocks,
        uint256 _redeemAfterGameEndedBlocks,
        uint256[4] memory _courtBps
    ) Owned(msg.sender) {
        gameDurationBlocks = _gameDurationBlocks;
        minPlayAmount = _minPlayAmount;
        protocolFee = _protocolFee;
        stormFrequencyBlocks = _stormFrequencyBlocks;
        redeemAfterGameEndedBlocks = _redeemAfterGameEndedBlocks;
        // Court Bps
        for (uint256 i = 0;i < 4;i++) {
            courtBps[CourtRole(i + 1)] = _courtBps[i];
        }
    }

    function startGame(
        address[1] calldata _king,
        address[2] calldata _lords,
        address[3] calldata _knights,
        address[4] calldata _townsfolk
    ) public onlyOwner {
        // Starting court
        confirmTheStorm(_king[0], CourtRole.King);
        confirmTheStorm(_lords[0], CourtRole.Lord);
        confirmTheStorm(_lords[1], CourtRole.Lord);
        confirmTheStorm(_knights[0], CourtRole.Knight);
        confirmTheStorm(_knights[1], CourtRole.Knight);
        confirmTheStorm(_knights[2], CourtRole.Knight);
        confirmTheStorm(_townsfolk[0], CourtRole.Townsfolk);
        confirmTheStorm(_townsfolk[1], CourtRole.Townsfolk);
        confirmTheStorm(_townsfolk[2], CourtRole.Townsfolk);
        confirmTheStorm(_townsfolk[3], CourtRole.Townsfolk);
        // Set starting block
        gameStartBlock = block.number;
    }

    function collectProtocolFees() public onlyOwner {
        if (protocolFeeBalance == 0) revert NoNativeToSend();
        if (!isGameEnded()) revert GameStillActive();
        SafeTransferLib.safeTransferETH(msg.sender, protocolFeeBalance);
        protocolFeeBalance = 0;
    }

    function protocolRedeem() public onlyOwner {
        uint256 redeemEndedBlock = gameEndBlock() + redeemAfterGameEndedBlocks;
        if (block.number < redeemEndedBlock) revert RedeemStillActive(redeemEndedBlock);
        SafeTransferLib.safeTransferETH(msg.sender, address(this).balance);
    }

    function stormTheCastle(uint256 _randomSeed, uint256 _fid) public payable {
        if (msg.sender == address(0)) revert BadZeroAddress();
        if (!isGameActive()) revert GameNotActive(gameStartBlock, gameEndBlock(), block.number);
        if (msg.value < minPlayAmount) revert InsufficientFunds(msg.value);
        if (stormBlock[msg.sender] + stormFrequencyBlocks >= block.number) revert TooFrequentStorms(
            stormBlock[msg.sender] + stormFrequencyBlocks,
            block.number
        );
        if (courtRoles[msg.sender] != CourtRole.None) revert AlreadyCourtMember(
            msg.sender,
            courtRoles[msg.sender]
        );
        // Increment play count
        storms++;
        // Make sure account can only storm every stormFrequencyBlocks blocks
        stormBlock[msg.sender] = block.number;
        // Determine courtRole
        CourtRole courtRole = determineCourtRole(msg.sender, _randomSeed);
        confirmTheStorm(msg.sender, courtRole);
        // Add protocol fee to balance
        protocolFeeBalance += protocolFee;
        emit StormTheCastle(msg.sender, uint8(courtRole), msg.value, _fid);
    }

    function isGameStarted() public view returns (bool) {
        return gameStartBlock <= block.number;
    }

    function isGameEnded() public view returns (bool) {
        return gameEndBlock() <= block.number;
    }

    function isGameActive() public view returns (bool) {
        return isGameStarted() && !isGameEnded();
    }

    function gameEndBlock() public view returns (uint256) {
        return gameStartBlock + gameDurationBlocks;
    }

    function gameLastBlock() public view returns (uint256) {
        return gameEndBlock() - 1;
    }

    function totalAssets() public view returns (uint256) {
        return address(this).balance - protocolFeeBalance;
    }

    function redeem() public {
        if (isGameActive()) revert GameStillActive();
        if (address(this).balance == 0) revert RedeemEnded();
        // Close out stream if this user still in court
        if (courtRoles[msg.sender] != CourtRole.None) {
            stopPointsFlow(msg.sender, courtRoles[msg.sender]);
        }
        if (pointsBalance[msg.sender] == 0) revert NoNativeToSend();
        uint256 nativeToSend = convertPointsToNative(pointsBalance[msg.sender]);
        SafeTransferLib.safeTransferETH(msg.sender, nativeToSend);
        emit Redeemed(msg.sender, nativeToSend, pointsBalance[msg.sender]);
        // Clear points balance
        pointsBalance[msg.sender] = 0;
    }

    function getTotalPoints() public view returns (uint256) {
        return gameDurationBlocks * totalPointsPerBlock;
    }

    function getPointsPerBlock(CourtRole courtRole) public view returns (uint256) {
        uint256 bps = courtBps[courtRole];
        return (totalPointsPerBlock * bps / 10_000);
    }

    function determineCourtRole(address accountAddress, uint256 _randomSeed) public pure returns (CourtRole) {
        uint256 random = Dice.rollDiceSet(
            1,
            100,
            uint256(keccak256(abi.encodePacked(accountAddress, _randomSeed)))
        );
        if (random >= 1 && random <= 5) {
            // 5%
            return CourtRole.King;
        } else if (random >= 6 && random <= 15) {
            // 10%
            return CourtRole.Lord;
        } else if (random >= 16 && random <= 36) {
            // 20%
            return CourtRole.Knight;
        } else {
            // 65%
            return CourtRole.Townsfolk;
        }
    }

    function confirmTheStorm(address accountAddress, CourtRole courtRole) private {
        // Switch flows
        if (courtRole == CourtRole.King) {
            switchFlows(king[0], accountAddress, CourtRole.King);
            king[0] = accountAddress;
        } else if (courtRole == CourtRole.Lord) {
            switchFlows(lords[0], accountAddress,CourtRole.Lord);
            lords[0] = lords[1];
            lords[1] = accountAddress;
        } else if (courtRole == CourtRole.Knight) {
            switchFlows(knights[0], accountAddress, CourtRole.Knight);
            knights[0] = knights[1];
            knights[1] = knights[2];
            knights[2] = accountAddress;
        } else {
            switchFlows(townsfolk[0], accountAddress, CourtRole.Townsfolk);
            townsfolk[0] = townsfolk[1];
            townsfolk[1] = townsfolk[2];
            townsfolk[2] = townsfolk[3];
            townsfolk[3] = accountAddress;
        }
    }

    function switchFlows(address oldAddress, address newAddress, CourtRole courtRole) private {
        if (oldAddress != address(0)) {
            stopPointsFlow(oldAddress, courtRole);
        }
        startPointsFlow(newAddress, courtRole);
    }

    function stopPointsFlow(address accountAddress, CourtRole courtRole) private {
        if (courtRoles[accountAddress] != courtRole) revert CourtRoleMismatch(
            accountAddress,
            courtRole,
            courtRoles[accountAddress]
        );
        // Add earnedPoints
        pointsBalance[accountAddress] += calculatePointsEarned(accountAddress, block.number, courtRole);
        // Reset courtRole mapping for this user
        courtRoles[accountAddress] = CourtRole.None;
        // Reset roleStartBlock
        roleStartBlock[accountAddress] = 0;
    }

    function startPointsFlow(address accountAddress, CourtRole courtRole) private {
        // Update courtRole
        courtRoles[accountAddress] = courtRole;
        // Update roleStartBlock
        roleStartBlock[accountAddress] = block.number;
    }

    function calculatePointsEarned(
        address accountAddress,
        uint256 endBlockNumber,
        CourtRole courtRole
    ) private view returns (uint256) {
        endBlockNumber = endBlockNumber > gameEndBlock() ? gameEndBlock() : endBlockNumber;
        if (roleStartBlock[accountAddress] == 0 || endBlockNumber <= roleStartBlock[accountAddress]) return 0;
        return (endBlockNumber - roleStartBlock[accountAddress]) * getPointsPerBlock(courtRole);
    }

    function convertPointsToNative(uint256 points) public view returns (uint256) {
        // Ensure points is not too large to cause overflow
        assert(points <= type(uint256).max / 1e18);
        uint256 pointsAdjusted = points * 1e18;
        uint256 percentage = pointsAdjusted / getTotalPoints();
        return (totalAssets() * percentage) / 1e18;
    }

    receive() external payable {}
}
