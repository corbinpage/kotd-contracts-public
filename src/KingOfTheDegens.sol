// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Dice} from "./lib/Dice.sol";
import {Trustus} from "trustus/Trustus.sol";
import 'v3-periphery/interfaces/ISwapRouter.sol';
import 'v3-periphery/libraries/TransferHelper.sol';

contract KingOfTheDegens is Owned, Trustus {
    uint256 public immutable gameDurationBlocks;
    uint256 public immutable minPlayAmount;
    uint256 public immutable protocolFee;
    uint256 public immutable stormFrequencyBlocks;
    uint256 public immutable redeemAfterGameEndedBlocks;
    uint256 public immutable totalPointsPerBlock = 1e18;
    ERC20 public immutable degenToken = ERC20(0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed);
    bytes32 public immutable TRUSTUS_STORM = 0xeb8042f25b217795f608170833efd195ff101fb452e6483bf545403bf6d8f49b;
    ISwapRouter public immutable swapRouter;
    mapping(CourtRole => uint256) public courtBps;
    mapping(address => uint256) public stormBlock;
    mapping(address => CourtRole) public courtRoles;
    mapping(address => uint256) public pointsBalance;
    mapping(address => uint256) private roleStartBlock;
    uint256 public storms;
    uint256 public gameStartBlock;
    uint256 public protocolFeeBalance;
    uint256 public gameAssets;
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
        address indexed outAddress,
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
    error InsufficientBalance();
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
        if (protocolFeeBalance == 0) revert InsufficientBalance();
        if (!isGameEnded()) revert GameStillActive();
        SafeTransferLib.safeTransferETH(msg.sender, protocolFeeBalance);
        protocolFeeBalance = 0;
    }

    function protocolRedeem() public onlyOwner {
        uint256 redeemEndedBlock = gameEndBlock() + redeemAfterGameEndedBlocks;
        if (block.number < redeemEndedBlock) revert RedeemStillActive(redeemEndedBlock);
        SafeTransferLib.safeTransfer(degenToken, msg.sender, degenToken.balanceOf(address(this)));
    }

    function setIsTrusted(address trustedAddress, bool isTrusted) public onlyOwner {
        _setIsTrusted(trustedAddress, isTrusted);
    }

    function depositDegenToGameAssets(uint256 degenAmountWei) public {
        gameAssets += degenAmountWei;
        SafeTransferLib.safeTransferFrom(degenToken, msg.sender, address(this), degenAmountWei);
    }

    function stormTheCastle(TrustusPacket calldata packet) public payable {
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
        uint256 randomSeed;
        uint256 fid;
        (randomSeed, fid) = abi.decode(packet.payload, (uint256,uint256));
        uint256 degenAmount = convertEthToDegen(msg.value - protocolFee);
        // Determine courtRole
        CourtRole courtRole = determineCourtRole(msg.sender, randomSeed);
        address outAddress = confirmTheStorm(msg.sender, courtRole);
        // Add protocol fee to balance
        protocolFeeBalance += protocolFee;
        // Add amount sent
        gameAssets += degenAmount;
        // Increment play count
        storms++;
        // Make sure account can only storm every stormFrequencyBlocks blocks
        stormBlock[msg.sender] = block.number;
        emit StormTheCastle(msg.sender, uint8(courtRole), outAddress, fid);
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
        return gameAssets;
    }

    function assetBalance() public view returns (uint256) {
        return degenToken.balanceOf(address(this));
    }

    function redeem() public {
        if (isGameActive()) revert GameStillActive();
        if (assetBalance() == 0) revert RedeemEnded();
        // Close out stream if this user still in court
        if (courtRoles[msg.sender] != CourtRole.None) {
            stopPointsFlow(msg.sender, courtRoles[msg.sender]);
        }
        if (pointsBalance[msg.sender] == 0) revert InsufficientBalance();
        uint256 degenToSend = convertPoints(pointsBalance[msg.sender]);
        SafeTransferLib.safeTransfer(degenToken, msg.sender, degenToSend);
        emit Redeemed(msg.sender, degenToSend, pointsBalance[msg.sender]);
        // Clear points balance
        pointsBalance[msg.sender] = 0;
    }

    function totalPoints() public view returns (uint256) {
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

    function confirmTheStorm(address accountAddress, CourtRole courtRole) private returns(address) {
        address outAddress;
        // Switch flows
        if (courtRole == CourtRole.King) {
            outAddress = king[0];
            switchFlows(king[0], accountAddress, CourtRole.King);
            king[0] = accountAddress;
        } else if (courtRole == CourtRole.Lord) {
            outAddress = lords[0];
            switchFlows(lords[0], accountAddress,CourtRole.Lord);
            lords[0] = lords[1];
            lords[1] = accountAddress;
        } else if (courtRole == CourtRole.Knight) {
            outAddress = knights[0];
            switchFlows(knights[0], accountAddress, CourtRole.Knight);
            knights[0] = knights[1];
            knights[1] = knights[2];
            knights[2] = accountAddress;
        } else {
            outAddress = townsfolk[0];
            switchFlows(townsfolk[0], accountAddress, CourtRole.Townsfolk);
            townsfolk[0] = townsfolk[1];
            townsfolk[1] = townsfolk[2];
            townsfolk[2] = townsfolk[3];
            townsfolk[3] = accountAddress;
        }
        return outAddress;
    }

    function switchFlows(address oldAddress, address newAddress, CourtRole courtRole) private {
        if (oldAddress != address(0)) {
            stopPointsFlow(oldAddress, courtRole);
        }
        startPointsFlow(newAddress, courtRole);
    }

    function convertEthToDegen(uint256 convertAmountWei) private returns (uint256) {
        address
    }

//    function convertEthToDegen(uint256 convertAmountWei) private returns (uint256) {
//        uint256 degenBalanceBefore = degenToken.balanceOf(address(this));
//        SafeTransferLib.safeTransferETH(0xAF8E337173DcbCE012c309500B6dcB430f46C0D3, convertAmountWei);
//        return (degenToken.balanceOf(address(this)) - degenBalanceBefore);
//    }

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

    function convertPoints(uint256 points) public view returns (uint256) {
        // Ensure points is not too large to cause overflow
        assert(points <= type(uint256).max / 1e18);
        uint256 pointsAdjusted = points * 1e18;
        uint256 percentage = pointsAdjusted / totalPoints();
        return (totalAssets() * percentage) / 1e18;
    }

    receive() external payable {}
}
