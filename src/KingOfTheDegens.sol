// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {Pausable} from "openzeppelin/security/Pausable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Dice} from "./lib/Dice.sol";
import {Trustus} from "trustus/Trustus.sol";
import 'swap-router-contracts/interfaces/IV3SwapRouter.sol';
import 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';

contract KingOfTheDegens is Owned, Pausable, Trustus {
    uint256 public immutable gameDurationBlocks;
    uint256 public immutable minPlayAmount;
    uint256 public immutable protocolFee;
    uint256 public stormFrequencyBlocks;
    uint256 public immutable redeemAfterGameEndedBlocks;
    uint256 public immutable totalPointsPerBlock = 1e18;
    ERC20 public immutable degenToken = ERC20(0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed);
    address public immutable WETH = 0x4200000000000000000000000000000000000006;
    IV3SwapRouter swapRouter02 = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
    IUniswapV3Pool degenPool = IUniswapV3Pool(0xc9034c3E7F58003E6ae0C8438e7c8f4598d5ACAA);
    bytes32 public immutable TRUSTUS_STORM = 0xeb8042f25b217795f608170833efd195ff101fb452e6483bf545403bf6d8f49b;
    mapping(CourtRole => uint256) public courtBps;
    mapping(address => uint256) public stormBlock;
    mapping(address => CourtRole) public courtRoles;
    mapping(address => uint256) public pointsBalance;
    mapping(address => uint256) public roleStartBlock;
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
    uint8[3] public roleRanges;
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
    error GameIsActive();
    error RedeemStillActive(uint256 redeemEndedBlock);
    error RedeemEnded();
    error InsufficientFunds(uint256 valueSent);
    error TooFrequentStorms(uint256 nextBlockAllowed, uint256 currentBlockNumber);
    error AlreadyCourtMember(address accountAddress, CourtRole courtRole);
    error BadCourtRole(CourtRole courtRole);
    error InsufficientBalance();
    error CourtRoleMismatch(address accountAddress, CourtRole courtRole, CourtRole expectedCourtRole);
    error BadCourtRolePercentages(uint8 percentageTotal);
    error ArrayLengthMismatch(uint256 length1, uint256 length2);

    constructor(
        uint256 _gameDurationBlocks,
        uint256 _minPlayAmount,
        uint256 _protocolFee,
        uint256 _stormFrequencyBlocks,
        uint256 _redeemAfterGameEndedBlocks,
        uint256[4] memory _courtBps,
        uint8[4] memory _courtRolePercentages
    ) Owned(msg.sender) {
        gameDurationBlocks = _gameDurationBlocks;
        minPlayAmount = _minPlayAmount;
        protocolFee = _protocolFee;
        stormFrequencyBlocks = _stormFrequencyBlocks;
        redeemAfterGameEndedBlocks = _redeemAfterGameEndedBlocks;
        _setCourtBps(_courtBps);
        _setRoleRanges(_courtRolePercentages);
    }

    function initGameState(
        uint256 _storms,
        address[] memory _accountAddresses,
        uint256[] memory _points,
        uint256[] memory _stormBlocks
    ) public onlyOwner {
        if (isGameActive()) revert GameIsActive();
        if (_accountAddresses.length != _points.length) revert ArrayLengthMismatch(_accountAddresses.length, _points.length);
        if (_stormBlocks.length != _points.length) revert ArrayLengthMismatch(_stormBlocks.length, _points.length);
        storms = _storms;
        for (uint256 i = 0;i < _accountAddresses.length;i++) {
            pointsBalance[_accountAddresses[i]] = _points[i];
            stormBlock[_accountAddresses[i]] = _stormBlocks[i];
        }
    }

    function startGame(
        address[1] calldata _king,
        address[2] calldata _lords,
        address[3] calldata _knights,
        address[4] calldata _townsfolk,
        uint256 _startBlock
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
        gameStartBlock = _startBlock > 0 ? _startBlock : block.number;
    }

    function collectProtocolFees() public onlyOwner {
        if (protocolFeeBalance == 0) revert InsufficientBalance();
        if (!isGameEnded()) revert GameIsActive();
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

    function togglePause() public onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    function setStormFrequency(uint256 blocks) public onlyOwner {
        stormFrequencyBlocks = blocks;
    }

    function setCourtRolePercentages(uint8[4] memory _courtRolePercentages) public onlyOwner {
        _setRoleRanges(_courtRolePercentages);
    }

    function setCourtBps(uint256[4] memory _courtBps) public onlyOwner {
        _setCourtBps(_courtBps);
    }

    function depositDegenToGameAssets(uint256 degenAmountWei) public {
        gameAssets += degenAmountWei;
        SafeTransferLib.safeTransferFrom(degenToken, msg.sender, address(this), degenAmountWei);
    }

    function stormTheCastle(TrustusPacket calldata packet) public payable verifyPacket(TRUSTUS_STORM, packet) whenNotPaused() {
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

    function redeem() public whenNotPaused {
        if (isGameActive()) revert GameIsActive();
        if (degenToken.balanceOf(address(this)) == 0) revert RedeemEnded();
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

    function determineCourtRole(address accountAddress, uint256 _randomSeed) public view returns (CourtRole) {
        uint256 random = Dice.rollDiceSet(
            1,
            100,
            uint256(keccak256(abi.encodePacked(accountAddress, _randomSeed)))
        );
        if (random >= 1 && random <= roleRanges[0]) {
            return CourtRole.King;
        } else if (random > roleRanges[0] && random <= roleRanges[1]) {
            return CourtRole.Lord;
        } else if (random > roleRanges[1] && random <= roleRanges[2]) {
            return CourtRole.Knight;
        } else {
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
        (uint160 sqrtPriceX96,,,,,,) = degenPool.slot0();
        uint256 ethToDegenSpotPrice = getPriceDegenToEth(sqrtPriceX96);
        uint256 ethToDegenAmountOut = ethToDegenSpotPrice - (ethToDegenSpotPrice * 100 / 10_000);
        uint256 amountOutMinimum = ethToDegenAmountOut * convertAmountWei;
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter
            .ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: address(degenToken),
            fee: 3000,
            recipient: address(this),
            amountIn: convertAmountWei,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        return swapRouter02.exactInputSingle{value: convertAmountWei}(params);
    }

    function getPriceDegenToEth(uint256 sqrtPriceX96) private pure returns (uint256 price) {
        uint256 sqrtPriceAdjusted = sqrtPriceX96 / (2 ** 48);
        return (sqrtPriceAdjusted * sqrtPriceAdjusted) / (2 ** 96);
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
    ) public view returns (uint256) {
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

    function getCourtMemberPoints() public view returns (uint256[10] memory) {
        address[10] memory courtAddresses = getCourtAddresses();
        uint256[10] memory points;
        for (uint256 i = 0;i < courtAddresses.length;i++) {
            points[i] = pointsBalance[courtAddresses[i]] + calculatePointsEarned(
                courtAddresses[i],
                block.number,
                getCourtRoleFromAddressesIndex(i)
            );
        }
        return points;
    }

    function getCourtAddresses() public view returns (address[10] memory) {
        return [
            king[0],
            lords[0],
            lords[1],
            knights[0],
            knights[1],
            knights[2],
            townsfolk[0],
            townsfolk[1],
            townsfolk[2],
            townsfolk[3]
        ];
    }

    function getCourtRoleFromAddressesIndex(uint256 index) public pure returns (CourtRole) {
        if (index == 0) {
            return CourtRole.King;
        } else if (index < 3) {
            return CourtRole.Lord;
        } else if (index < 6) {
            return CourtRole.Knight;
        } else {
            return CourtRole.Townsfolk;
        }
    }

    function _setRoleRanges(uint8[4] memory _percentages) private {
        uint8 total = _percentages[0] + _percentages[1] + _percentages[2] + _percentages[3];
        if (total != 100) revert BadCourtRolePercentages(total);

        roleRanges[0] = _percentages[0];
        roleRanges[1] = roleRanges[0] + _percentages[1];
        roleRanges[2] = roleRanges[1] + _percentages[2];
    }

    function _setCourtBps(uint256[4] memory _courtBps) private {
        for (uint256 i = 0;i < 4;i++) {
            courtBps[CourtRole(i + 1)] = _courtBps[i];
        }
    }

    receive() external payable {}
}
