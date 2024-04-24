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
    uint256 public gameDurationBlocks;
    uint256 public minPlayAmount;
    uint256 public immutable protocolFee;
    uint256 public stormFrequencyBlocks;
    uint256 public immutable redeemAfterGameEndedBlocks;
    uint256 public immutable totalPointsPerBlock = 1e18;
    ERC20 public immutable degenToken = ERC20(0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed);
    address public immutable WETH = 0x4200000000000000000000000000000000000006;
    IV3SwapRouter swapRouter02 = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
    IUniswapV3Pool degenPool = IUniswapV3Pool(0xc9034c3E7F58003E6ae0C8438e7c8f4598d5ACAA);
    mapping(CourtRole => uint256) public courtRolePointAllocation;
    mapping(address => uint256) public stormBlock;
    mapping(address => CourtRole) public courtRoles;
    mapping(address => uint256) public pointsBalance;
    mapping(address => uint256) public roleStartBlock;
    uint256 public storms;
    uint256 public gameStartBlock;
    uint256 public gameAssets;
    // Court
    address[1] public king;
    address[2] public lords;
    address[3] public knights;
    address[4] public townsfolk;
    address[3] public custom;
    // Role
    enum CourtRole {
        None,
        King,
        Lord,
        Knight,
        Townsfolk,
        Custom
    }
    uint256[3] public courtRoleOddsCeilings;
    // Events
    event StormTheCastle(
        address indexed accountAddress,
        uint8 indexed courtRole,
        address indexed outAddress,
        uint256 fid
    );
    event Action(
        address indexed accountAddress,
        address indexed outAddress,
        uint256 indexed fid,
        string actionType
    );
    event Redeemed(address indexed accountAddress, uint256 indexed amountRedeemed, uint256 indexed pointsRedeemed);
    // Custom Errors
    error BadZeroAddress();
    error GameNotActive(uint256 gameStartBlock, uint256 gameEndBlock, uint256 currentBlock);
    error GameIsActive();
    error RedeemStillActive();
    error RedeemEnded();
    error InsufficientFunds(uint256 valueSent);
    error TooFrequentStorms(uint256 nextBlockAllowed, uint256 currentBlockNumber);
    error AlreadyCourtMember(address accountAddress, CourtRole courtRole);
    error BadCourtRole(CourtRole courtRole);
    error InsufficientBalance();
    error CourtRoleMismatch(address accountAddress, CourtRole courtRole, CourtRole expectedCourtRole);
    error BadCourtRoleOdds(uint256 percentageTotal);
    error RequiresCourtRole(CourtRole courtRole);
    error ArrayLengthMismatch(uint256 length1, uint256 length2);

    constructor(
        uint256 _gameDurationBlocks,
        uint256 _minPlayAmount,
        uint256 _protocolFee,
        uint256 _stormFrequencyBlocks,
        uint256 _redeemAfterGameEndedBlocks,
        uint256[5] memory _courtRolePointAllocation,
        uint256[4] memory _courtRoleOdds
    ) Owned(msg.sender) {
        gameDurationBlocks = _gameDurationBlocks;
        minPlayAmount = _minPlayAmount;
        protocolFee = _protocolFee;
        stormFrequencyBlocks = _stormFrequencyBlocks;
        redeemAfterGameEndedBlocks = _redeemAfterGameEndedBlocks;
        _setCourtRolePointAllocation(_courtRolePointAllocation);
        _setCourtRoleOddsCeilings(_courtRoleOdds);
    }

    // Public Game Methods

    function stormTheCastle(
        TrustusPacket calldata packet
    ) public payable verifyPacket(keccak256(abi.encodePacked("stormTheCastle(TrustusPacket)")), packet) whenNotPaused() {
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
        // Determine courtRole
        CourtRole courtRole = determineCourtRole(msg.sender, randomSeed);
        address outAddress = replaceRole(msg.sender, courtRole);
        depositToTreasury(msg.value);
        // Increment play count
        storms++;
        // Make sure account can only storm every stormFrequencyBlocks blocks
        stormBlock[msg.sender] = block.number;
        emit StormTheCastle(msg.sender, uint8(courtRole), outAddress, fid);
    }

    function redeem() public whenNotPaused {
        if (isGameActive()) revert GameIsActive();
        if (_hasRedeemEnded()) revert RedeemEnded();
        if (degenToken.balanceOf(address(this)) == 0) revert RedeemEnded();
        // Close out stream if this user still in court
        if (courtRoles[msg.sender] != CourtRole.None && roleStartBlock[msg.sender] < gameEndBlock()) {
            updatePointsBalance(msg.sender);
        }
        if (pointsBalance[msg.sender] == 0) revert InsufficientBalance();
        uint256 degenToSend = convertPointsToAssets(pointsBalance[msg.sender]);
        SafeTransferLib.safeTransfer(degenToken, msg.sender, degenToSend);
        emit Redeemed(msg.sender, degenToSend, pointsBalance[msg.sender]);
        // Clear points balance
        pointsBalance[msg.sender] = 0;
    }

    function depositDegenToGameAssets(uint256 degenAmountWei) public {
        gameAssets += degenAmountWei;
        SafeTransferLib.safeTransferFrom(degenToken, msg.sender, address(this), degenAmountWei);
    }

    // Court Role Specific Public Methods

    function setJesterRole(
        TrustusPacket calldata packet
    ) public payable verifyPacket(keccak256(abi.encodePacked("setJesterRole(TrustusPacket)")), packet) whenNotPaused() {
        if (msg.sender != king[0]) revert RequiresCourtRole(CourtRole.King);
        if (msg.value < minPlayAmount) revert InsufficientFunds(msg.value);
        address newJester;
        uint256 fid;
        (newJester, fid) = abi.decode(packet.payload, (address,uint256));
        address outAddress;
        if (courtRoles[newJester] != CourtRole.None) {
            outAddress = custom[0];
            updatePointsBalance(newJester);
            updatePointsBalance(outAddress);
            _addToCourt(outAddress, courtRoles[newJester]);
            _addToCourt(newJester, CourtRole.Custom);
        } else {
            outAddress = replaceRole(newJester, CourtRole.Custom);
        }
        depositToTreasury(msg.value);
        emit Action(msg.sender, outAddress, fid, "jester");
    }

    // View Methods

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

    function totalPoints() public view returns (uint256) {
        return gameDurationBlocks * totalPointsPerBlock;
    }

    function getPointsPerBlock(CourtRole courtRole) public view returns (uint256) {
        uint256 pointAllocation = courtRolePointAllocation[courtRole];
        return (totalPointsPerBlock * pointAllocation / 10_000);
    }

    function determineCourtRole(address accountAddress, uint256 _randomSeed) public view returns (CourtRole) {
        uint256 random = Dice.rollDiceSet(
            1,
            10_000,
            uint256(keccak256(abi.encodePacked(accountAddress, _randomSeed)))
        );
        uint256 kingRange = getKingRange();
        if (random >= 1 && random <= kingRange) {
            return CourtRole.King;
        } else if (random > kingRange && random <= courtRoleOddsCeilings[1]) {
            return CourtRole.Lord;
        } else if (random > courtRoleOddsCeilings[1] && random <= courtRoleOddsCeilings[2]) {
            return CourtRole.Knight;
        } else {
            return CourtRole.Townsfolk;
        }
    }

    function getKingRange() public view returns (uint256) {
        uint256 kingProtectionBlocks = 10800;
        uint256 kingBlock = roleStartBlock[king[0]];
        uint256 endBlock = kingBlock + kingProtectionBlocks;
        uint256 startValue = 100;
        uint256 endValue = courtRoleOddsCeilings[0];
        if (block.number >= endBlock) {
            return endValue;
        } else if (block.number <= kingBlock) {
            return startValue;
        } else {
            return uint256(startValue + ((endValue - startValue) * (block.number - kingBlock)) / kingProtectionBlocks);
        }
    }

    function calculatePointsEarned(address accountAddress) public view returns (uint256) {
        uint256 endBlockNumber = block.number > gameEndBlock() ? gameEndBlock() : block.number;
        if (endBlockNumber <= roleStartBlock[accountAddress]) return 0;
        return (endBlockNumber - roleStartBlock[accountAddress]) * getPointsPerBlock(courtRoles[accountAddress]);
    }

    function convertPointsToAssets(uint256 points) public view returns (uint256) {
        // Ensure points is not too large to cause overflow
        assert(points <= type(uint256).max / 1e18);
        uint256 pointsAdjusted = points * 1e18;
        uint256 percentage = pointsAdjusted / totalPoints();
        return (totalAssets() * percentage) / 1e18;
    }

    function getPoints(address accountAddress) public view returns (uint256) {
        if (courtRoles[accountAddress] == CourtRole.None) {
            return pointsBalance[accountAddress];
        }
        // Court Member - Calculate realtime
        return pointsBalance[accountAddress] + calculatePointsEarned(accountAddress);
    }

    function getCourtMemberPoints() public view returns (uint256[13] memory) {
        address[13] memory courtAddresses = getCourtAddresses();
        uint256[13] memory points;
        for (uint256 i = 0;i < courtAddresses.length;i++) {
            points[i] = getPoints(courtAddresses[i]);
        }
        return points;
    }

    function getCourtAddresses() public view returns (address[13] memory) {
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
            townsfolk[3],
            custom[0],
            custom[1],
            custom[2]
        ];
    }

    function findCourtRole(
        address accountAddress,
        KingOfTheDegens.CourtRole desiredCourtRole
    ) public view returns (uint256) {
        for (uint256 i = 1;i <= 30_000;i++) {
            CourtRole rolledRole = determineCourtRole(accountAddress, i);
            if (rolledRole == desiredCourtRole) {
                return i;
            }
        }
        return 0;
    }

    // Private Methods

    function depositToTreasury(uint256 nativeIn) private {
        uint256 degenAmount = convertEthToDegen(nativeIn - protocolFee);
        gameAssets += degenAmount;
    }

    function replaceRole(address accountAddress, CourtRole courtRole) private returns(address) {
        updateRoleStartBlock(accountAddress);
        address outAddress = _addToCourt(accountAddress, courtRole);
        if (outAddress != address(0)) {
            updatePointsBalance(outAddress);
            updateCourtRole(outAddress, CourtRole.None);
        }
        return outAddress;
    }

    function restartCourtStreams() private {
        address[13] memory courtAddresses = getCourtAddresses();
        for (uint256 i = 0;i < courtAddresses.length;i++) {
            updatePointsBalance(courtAddresses[i]);
        }
    }

    function updateRoleStartBlock(address accountAddress) private {
        roleStartBlock[accountAddress] = block.number;
    }

    function updatePointsBalance(address accountAddress) private {
        pointsBalance[accountAddress] += calculatePointsEarned(accountAddress);
        updateRoleStartBlock(accountAddress);
    }

    function updateCourtRole(address accountAddress, CourtRole courtRole) private {
        courtRoles[accountAddress] = courtRole;
    }

    function convertEthToDegen(uint256 convertAmountWei) private returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = degenPool.slot0();
        uint256 sqrtPriceAdjusted = sqrtPriceX96 / (2 ** 48);
        uint256 ethToDegenSpotPrice = (sqrtPriceAdjusted * sqrtPriceAdjusted) / (2 ** 96);
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

    function _setCourtRoleOddsCeilings(uint256[4] memory _courtRoleOdds) private {
        uint256 total = _courtRoleOdds[0] + _courtRoleOdds[1] + _courtRoleOdds[2] + _courtRoleOdds[3];
        if (total != 10_000) revert BadCourtRoleOdds(total);

        courtRoleOddsCeilings[0] = _courtRoleOdds[0];
        courtRoleOddsCeilings[1] = courtRoleOddsCeilings[0] + _courtRoleOdds[1];
        courtRoleOddsCeilings[2] = courtRoleOddsCeilings[1] + _courtRoleOdds[2];
    }

    function _setCourtRolePointAllocation(uint256[5] memory _courtRolePointAllocation) private {
        for (uint256 i = 0;i < _courtRolePointAllocation.length;i++) {
            courtRolePointAllocation[CourtRole(i + 1)] = _courtRolePointAllocation[i];
        }
    }

    function _hasRedeemEnded() private view returns (bool) {
        uint256 redeemEndedBlock = gameEndBlock() + redeemAfterGameEndedBlocks;
        return block.number >= redeemEndedBlock;
    }

    function _addToCourt(address accountAddress, CourtRole courtRole) private returns (address) {
        address outAddress;
        // Switch flows
        if (courtRole == CourtRole.King) {
            outAddress = king[0];
            king[0] = accountAddress;
        } else if (courtRole == CourtRole.Lord) {
            outAddress = lords[0];
            lords[0] = lords[1];
            lords[1] = accountAddress;
        } else if (courtRole == CourtRole.Knight) {
            outAddress = knights[0];
            knights[0] = knights[1];
            knights[1] = knights[2];
            knights[2] = accountAddress;
        } else if (courtRole == CourtRole.Townsfolk) {
            outAddress = townsfolk[0];
            townsfolk[0] = townsfolk[1];
            townsfolk[1] = townsfolk[2];
            townsfolk[2] = townsfolk[3];
            townsfolk[3] = accountAddress;
        } else {
            // Jester for now
            outAddress = custom[0];
            custom[0] = accountAddress;
        }
        updateCourtRole(accountAddress, courtRole);
        return outAddress;
    }

    // Only Owner

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
        replaceRole(_king[0], CourtRole.King);
        replaceRole(_lords[0], CourtRole.Lord);
        replaceRole(_lords[1], CourtRole.Lord);
        replaceRole(_knights[0], CourtRole.Knight);
        replaceRole(_knights[1], CourtRole.Knight);
        replaceRole(_knights[2], CourtRole.Knight);
        replaceRole(_townsfolk[0], CourtRole.Townsfolk);
        replaceRole(_townsfolk[1], CourtRole.Townsfolk);
        replaceRole(_townsfolk[2], CourtRole.Townsfolk);
        replaceRole(_townsfolk[3], CourtRole.Townsfolk);
        // Set starting block
        gameStartBlock = _startBlock > 0 ? _startBlock : block.number;
    }

    function collectProtocolFees() public onlyOwner {
        if (address(this).balance == 0) revert InsufficientBalance();
        if (!isGameEnded()) revert GameIsActive();
        SafeTransferLib.safeTransferETH(msg.sender, address(this).balance);
    }

    function protocolRedeem() public onlyOwner {
        if (!_hasRedeemEnded()) revert RedeemStillActive();
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

    function setCourtRoleOdds(uint256[4] memory _courtRoleOdds) public onlyOwner {
        _setCourtRoleOddsCeilings(_courtRoleOdds);
    }

    function setCourtRolePointAllocation(uint256[5] memory _courtRolePointAllocation) public onlyOwner {
        _setCourtRolePointAllocation(_courtRolePointAllocation);
    }

    receive() external payable {}
}
