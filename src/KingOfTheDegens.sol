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
    uint256 public protocolFee;
    uint256 public stormFrequencyBlocks;
    uint256 public immutable redeemAfterGameEndedBlocks;
    uint256 public immutable totalPointsPerBlock = 1e18;
    ERC20 public immutable degenToken = ERC20(0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed);
    address public immutable WETH = 0x4200000000000000000000000000000000000006;
    IV3SwapRouter swapRouter02 = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
    IUniswapV3Pool degenPool = IUniswapV3Pool(0xc9034c3E7F58003E6ae0C8438e7c8f4598d5ACAA);
    mapping(PointAllocationTemplate => uint256[5]) public pointAllocationTemplates;
    PointAllocationTemplate public activePointAllocationTemplate;
    mapping(address => uint256) public stormBlock;
    mapping(address => CourtRole) public courtRoles;
    mapping(address => uint256) public pointsBalance;
    mapping(address => uint256) public roleStartBlock;
    mapping (CourtRole => uint256) public roleIndexCeiling;
    mapping (CourtRole => uint256) public roleCounts;
    uint256 public storms;
    uint256 public gameStartBlock;
    uint256 public gameAssets;
    uint256 public kingProtectionBlocks = 10800;
    // Court
    address[11] public court;
    // Role
    enum CourtRole {
        None,
        King,
        Lord,
        Knight,
        Townsfolk,
        Jester
    }
    enum PointAllocationTemplate {
        Custom,
        Greedy,
        Military,
        Peoples,
        Dead
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
        uint256 indexed outData,
        string actionType
    );
    event Redeemed(address indexed accountAddress, uint256 indexed amountRedeemed, uint256 indexed pointsRedeemed);
    // Custom Errors
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
    error InvalidPercentage(uint256 percentageTotal);
    error MinPlayAmountOutOfRange(uint256 minPlayAmount);
    error RequiresCourtRole(CourtRole courtRole, CourtRole actualCourtRole);
    error InvalidPointAllocationTemplate(PointAllocationTemplate pointAllocationTemplate);

    constructor(
        uint256 _gameDurationBlocks,
        uint256 _minPlayAmount,
        uint256 _protocolFee,
        uint256 _stormFrequencyBlocks,
        uint256 _redeemAfterGameEndedBlocks,
        uint256[4] memory _courtRoleOdds,
        uint256[5] memory _roleCounts,
        uint256[5][5] memory _pointAllocationTemplates
    ) Owned(msg.sender) {
        gameDurationBlocks = _gameDurationBlocks;
        minPlayAmount = _minPlayAmount;
        protocolFee = _protocolFee;
        stormFrequencyBlocks = _stormFrequencyBlocks;
        redeemAfterGameEndedBlocks = _redeemAfterGameEndedBlocks;
        _setPointAllocationTemplates(_pointAllocationTemplates);
        _setCourtRoleOddsCeilings(_courtRoleOdds);
        // Calculate roleIndexCeiling and roleCounts based on _roleCounts
        uint256 _total;
        for (uint i = 1; i <= _roleCounts.length; i++) {
            roleCounts[CourtRole(i)] = _roleCounts[i-1];
            _total += _roleCounts[i-1];
            roleIndexCeiling[CourtRole(i)] = _total - 1;
        }
    }

    // Public Game Methods

    function stormTheCastle(
        TrustusPacket calldata packet
    ) public payable verifyPacket(keccak256(abi.encodePacked("stormTheCastle(TrustusPacket)")), packet) whenNotPaused() {
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
        address outAddress = replaceCourtMember(msg.sender, courtRole);
        depositToTreasury(msg.value);
        // Increment play count
        storms++;
        // Make sure account can only storm every stormFrequencyBlocks blocks
        stormBlock[msg.sender] = block.number;
        emit StormTheCastle(msg.sender, uint8(courtRole), outAddress, fid);
    }

    function redeem() public virtual whenNotPaused {
        if (isGameActive()) revert GameIsActive();
        if (_hasRedeemEnded()) revert RedeemEnded();
        if (degenToken.balanceOf(address(this)) == 0) revert RedeemEnded();
        // Close out stream if this user still in court
        if (courtRoles[msg.sender] != CourtRole.None && roleStartBlock[msg.sender] < gameEndBlock()) {
            updatePointsBalance(msg.sender, courtRoles[msg.sender]);
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

    // KING
    function setJesterRole(
        TrustusPacket calldata packet
    ) public payable verifyPacket(keccak256(abi.encodePacked("setJesterRole(TrustusPacket)")), packet) whenNotPaused() {
        if (courtRoles[msg.sender] != CourtRole.King) revert RequiresCourtRole(CourtRole.King, courtRoles[msg.sender]);
        if (msg.value < minPlayAmount) revert InsufficientFunds(msg.value);
        address newJester;
        uint256 fid;
        (newJester, fid) = abi.decode(packet.payload, (address,uint256));
        address outAddress;
        if (courtRoles[newJester] != CourtRole.None) {
            address oldJester = jester()[0];
            outAddress = oldJester;
            swapCourtMember(newJester, oldJester);
        } else {
            outAddress = replaceCourtMember(newJester, CourtRole.Jester);
        }
        depositToTreasury(msg.value);
        emit Action(msg.sender, outAddress, fid, "setJesterRole");
    }

    function setPointStrategy(
        TrustusPacket calldata packet
    ) public payable verifyPacket(keccak256(abi.encodePacked("setPointStrategy(TrustusPacket)")), packet) whenNotPaused() {
        if (courtRoles[msg.sender] != CourtRole.King) revert RequiresCourtRole(CourtRole.King, courtRoles[msg.sender]);
        if (msg.value < minPlayAmount) revert InsufficientFunds(msg.value);
        uint8 _pointAllocationTemplate;
        _pointAllocationTemplate = abi.decode(packet.payload, (uint8));
        PointAllocationTemplate pointAllocationTemplate = PointAllocationTemplate(_pointAllocationTemplate);
        if (
            pointAllocationTemplate != PointAllocationTemplate.Greedy &&
            pointAllocationTemplate != PointAllocationTemplate.Military &&
            pointAllocationTemplate != PointAllocationTemplate.Peoples
        ) {
            revert InvalidPointAllocationTemplate(pointAllocationTemplate);
        }
        _setActivePointAllocationTemplate(pointAllocationTemplate);
        depositToTreasury(msg.value);
        emit Action(msg.sender, address(0), _pointAllocationTemplate, "setPointsStrategy");
    }

    // LORD
    function setStormFee(
        TrustusPacket calldata packet
    ) public payable verifyPacket(keccak256(abi.encodePacked("setStormFee(TrustusPacket)")), packet) whenNotPaused() {
        if (courtRoles[msg.sender] != CourtRole.Lord) revert RequiresCourtRole(CourtRole.Lord, courtRoles[msg.sender]);
        if (msg.value < minPlayAmount) revert InsufficientFunds(msg.value);
        uint256 _minPlayAmount;
        _minPlayAmount = abi.decode(packet.payload, (uint256));
        if (_minPlayAmount != 1e15 && _minPlayAmount != 2e15) revert MinPlayAmountOutOfRange(_minPlayAmount);
        depositToTreasury(msg.value);
        minPlayAmount = _minPlayAmount;
        protocolFee = _minPlayAmount == 1e15 ? 1e14 : 2e14;
        emit Action(msg.sender, address(0), _minPlayAmount, "setStormFee");
    }

    // KNIGHT
    function attackKing(
        TrustusPacket calldata packet
    ) public payable verifyPacket(keccak256(abi.encodePacked("attackKing(TrustusPacket)")), packet) whenNotPaused() {
        if (courtRoles[msg.sender] != CourtRole.Knight) revert RequiresCourtRole(CourtRole.Knight, courtRoles[msg.sender]);
        if (msg.value < minPlayAmount) revert InsufficientFunds(msg.value);
        bool _kingIsDead;
        _kingIsDead = abi.decode(packet.payload, (bool));
        depositToTreasury(msg.value);
        address outAddress;
        if (_kingIsDead) {
            _setActivePointAllocationTemplate(PointAllocationTemplate.Dead);
            outAddress = king()[0];
        }
        emit Action(msg.sender, outAddress, _kingIsDead ? 1 : 0, "attackKing");
    }

    // Public View Helper Methods

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

    function getActiveCourtRolePointAllocation(CourtRole courtRole) public view returns (uint256) {
        return getCourtRolePointAllocation(courtRole, activePointAllocationTemplate);
    }

    function getCourtRolePointAllocation(
        CourtRole courtRole,
        PointAllocationTemplate pointAllocationTemplate
    ) public view returns (uint256) {
        if (courtRole == CourtRole.None) return 0;
        return pointAllocationTemplates[pointAllocationTemplate][uint8(courtRole) - 1];
    }

    function getPointsPerBlock(CourtRole courtRole) public view returns (uint256) {
        return (totalPointsPerBlock * getActiveCourtRolePointAllocation(courtRole) / 10_000);
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
        uint256 kingBlock = roleStartBlock[king()[0]];
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

    function calculatePointsEarned(
        CourtRole courtRole,
        uint256 startBlock
    ) public view returns (uint256) {
        uint256 endBlockNumber = block.number > gameEndBlock() ? gameEndBlock() : block.number;
        if (endBlockNumber <= startBlock) return 0;
        return (endBlockNumber - startBlock) * getPointsPerBlock(courtRole);
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
        return pointsBalance[accountAddress] + calculatePointsEarned(
            courtRoles[accountAddress],
            roleStartBlock[accountAddress]
        );
    }

    function getCourtMemberPoints() public view returns (uint256[11] memory) {
        uint256[11] memory points;
        for (uint256 i = 0;i < court.length;i++) {
            points[i] = getPoints(court[i]);
        }
        return points;
    }

    function king() public view returns (address[1] memory) {
        (uint256 start, ) = getCourtRoleIndexes(CourtRole.King);
        return [court[start]];
    }

    function lords() public view returns (address[2] memory) {
        address[2] memory addresses;
        (uint256 start, uint256 end) = getCourtRoleIndexes(CourtRole.Lord);

        for(uint i = start; i <= end; i++) {
            addresses[i - start] = court[i];
        }
        return addresses;
    }

    function knights() public view returns (address[3] memory) {
        address[3] memory addresses;
        (uint256 start, uint256 end) = getCourtRoleIndexes(CourtRole.Knight);

        for(uint i = start; i <= end; i++) {
            addresses[i - start] = court[i];
        }
        return addresses;
    }

    function townsfolk() public view returns (address[4] memory) {
        address[4] memory addresses;
        (uint256 start, uint256 end) = getCourtRoleIndexes(CourtRole.Townsfolk);

        for(uint i = start; i <= end; i++) {
            addresses[i - start] = court[i];
        }
        return addresses;
    }

    function jester() public view returns (address[1] memory) {
        (uint256 start, ) = getCourtRoleIndexes(CourtRole.Jester);
        return [court[start]];
    }

    function getCourtRoleFromAddressesIndex(uint256 index) public view returns (CourtRole) {
        if (index <= roleIndexCeiling[CourtRole.King]) {
            return CourtRole.King;
        } else if (index <= roleIndexCeiling[CourtRole.Lord]) {
            return CourtRole.Lord;
        } else if (index <= roleIndexCeiling[CourtRole.Knight]) {
            return CourtRole.Knight;
        } else if (index <= roleIndexCeiling[CourtRole.Townsfolk]) {
            return CourtRole.Townsfolk;
        } else if (index <= roleIndexCeiling[CourtRole.Jester]) {
            return CourtRole.Jester;
        }
        return CourtRole.None;
    }

    function getCourtRoleIndexes(CourtRole courtRole) public view returns (uint256 start, uint256 end) {
        if (courtRole == CourtRole.King){
            return (0, 0);
        }

        start = roleIndexCeiling[CourtRole(uint(courtRole)-1)] + 1;
        end = start + roleCounts[courtRole] - 1;

        return (start, end);
    }

    function indexOfAddressInRole(CourtRole courtRole, address accountAddress) public view returns (uint256) {
        (uint256 start, uint256 end) = getCourtRoleIndexes(courtRole);
        uint256 returnIndex;
        for (uint256 i = start; i <= end; i++) {
            if (court[i] == accountAddress) {
                return returnIndex;
            }
            returnIndex++;
        }

        return end;  // returns the end index if the address wasn't found in the range
    }

    function findCourtRole(
        address accountAddress,
        CourtRole desiredCourtRole
    ) public view returns (uint256) {
        for (uint256 i = 1;i <= 30_000;i++) {
            CourtRole rolledRole = determineCourtRole(accountAddress, i);
            if (rolledRole == desiredCourtRole) {
                return i;
            }
        }
        return 0;
    }

    // Internal Methods

    function replaceCourtMember(address accountAddress, CourtRole courtRole) internal returns(address) {
        // Rotate In
        (uint256 start, uint256 end) = getCourtRoleIndexes(courtRole);
        address outAddress = court[start];
        for(uint i = start; i < end; i++) {
            court[i] = court[i+1];
        }
        court[end] = accountAddress;
        // Set Court Roles
        updateCourtRole(accountAddress, courtRole);
        updateCourtRole(outAddress, CourtRole.None);
        // Update Points Balance outAddress
        updatePointsBalance(outAddress, courtRole);
        // Update Role Start Block for accountAddress
        updateRoleStartBlock(accountAddress);
        return outAddress;
    }

    function swapCourtMember(address address1, address address2) internal {
        CourtRole courtRole1 = courtRoles[address1];
        CourtRole courtRole2 = courtRoles[address2];
        // Update Points Balance on both addresses to close out old role
        updatePointsBalance(address1, courtRole1);
        updatePointsBalance(address2, courtRole2);
        // Find index
        uint256 index1 = indexOfAddressInRole(courtRole1, address1);
        uint256 index2 = indexOfAddressInRole(courtRole2, address2);
        (uint256 start1,) = getCourtRoleIndexes(courtRole1);
        (uint256 start2,) = getCourtRoleIndexes(courtRole2);
        // Swap roles
        court[start1 + index1] = address2;
        court[start2 + index2] = address1;
        // Update court role mapping
        updateCourtRole(address1, courtRole2);
        updateCourtRole(address2, courtRole1);
    }

    function restartCourtStreams() internal {
        for (uint256 i = 0;i < court.length;i++) {
            updatePointsBalance(court[i], getCourtRoleFromAddressesIndex(i));
        }
    }

    function depositToTreasury(uint256 nativeIn) internal virtual {
        uint256 degenAmount = convertEthToDegen(nativeIn - protocolFee);
        gameAssets += degenAmount;
    }

    function convertEthToDegen(uint256 convertAmountWei) internal returns (uint256) {
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

    // Internal helpers

    function updateRoleStartBlock(address accountAddress) internal {
        roleStartBlock[accountAddress] = block.number;
    }

    function updatePointsBalance(address accountAddress, CourtRole courtRole) internal {
        pointsBalance[accountAddress] += calculatePointsEarned(
            courtRole,
            roleStartBlock[accountAddress]
        );
        updateRoleStartBlock(accountAddress);
    }

    function updateCourtRole(address accountAddress, CourtRole courtRole) internal {
        courtRoles[accountAddress] = courtRole;
    }

    function _setCourtRoleOddsCeilings(uint256[4] memory _courtRoleOdds) internal {
        uint256 total = _courtRoleOdds[0] + _courtRoleOdds[1] + _courtRoleOdds[2] + _courtRoleOdds[3];
        if (total != 10_000) revert InvalidPercentage(total);

        courtRoleOddsCeilings[0] = _courtRoleOdds[0];
        courtRoleOddsCeilings[1] = courtRoleOddsCeilings[0] + _courtRoleOdds[1];
        courtRoleOddsCeilings[2] = courtRoleOddsCeilings[1] + _courtRoleOdds[2];
    }

    function _setPointAllocationTemplates(uint256[5][5] memory _pointAllocationTemplates) internal {
        for (uint8 i = 0;i < _pointAllocationTemplates.length;i++) {
            uint256 total = _pointAllocationTemplates[i][0] +
                            (_pointAllocationTemplates[i][1] * 2) +
                            (_pointAllocationTemplates[i][2] * 3) +
                            (_pointAllocationTemplates[i][3] * 4) +
                            _pointAllocationTemplates[i][4];
            if (total != 10_000) revert InvalidPercentage(total);
            pointAllocationTemplates[PointAllocationTemplate(i)] = _pointAllocationTemplates[i];
        }
    }

    function _setActivePointAllocationTemplate(PointAllocationTemplate _pointAllocationTemplate) internal {
        activePointAllocationTemplate = _pointAllocationTemplate;
        if (isGameStarted()) {
            // Need to restart streams for existing court members
            restartCourtStreams();
        }
    }

    function _hasRedeemEnded() internal view returns (bool) {
        uint256 redeemEndedBlock = gameEndBlock() + redeemAfterGameEndedBlocks;
        return block.number >= redeemEndedBlock;
    }

    // Only Owner

    function startGame(
        address[1] calldata _king,
        address[2] calldata _lords,
        address[3] calldata _knights,
        address[4] calldata _townsfolk,
        uint256 _startBlock
    ) public onlyOwner {
        // Starting court
        replaceCourtMember(_king[0], CourtRole.King);
        replaceCourtMember(_lords[0], CourtRole.Lord);
        replaceCourtMember(_lords[1], CourtRole.Lord);
        replaceCourtMember(_knights[0], CourtRole.Knight);
        replaceCourtMember(_knights[1], CourtRole.Knight);
        replaceCourtMember(_knights[2], CourtRole.Knight);
        replaceCourtMember(_townsfolk[0], CourtRole.Townsfolk);
        replaceCourtMember(_townsfolk[1], CourtRole.Townsfolk);
        replaceCourtMember(_townsfolk[2], CourtRole.Townsfolk);
        replaceCourtMember(_townsfolk[3], CourtRole.Townsfolk);
        // Set starting block
        gameStartBlock = _startBlock > 0 ? _startBlock : block.number;
    }

    function collectProtocolFees() public virtual onlyOwner {
        if (address(this).balance == 0) revert InsufficientBalance();
        if (!isGameEnded()) revert GameIsActive();
        SafeTransferLib.safeTransferETH(msg.sender, address(this).balance);
    }

    function protocolRedeem() public virtual onlyOwner {
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

    function setMinPlayAmount(uint256 _minPlayAmount) public onlyOwner {
        minPlayAmount = _minPlayAmount;
    }

    function setProtocolFee(uint256 _protocolFee) public onlyOwner {
        protocolFee = _protocolFee;
    }

    function setKingProtectionBlocks(uint256 _kingProtectionBlocks) public onlyOwner {
        kingProtectionBlocks = _kingProtectionBlocks;
    }

    function setCourtRoleOdds(uint256[4] memory _courtRoleOdds) public onlyOwner {
        _setCourtRoleOddsCeilings(_courtRoleOdds);
    }

    function setGameDurationBlocks(uint256 blocks) public onlyOwner {
        gameDurationBlocks = blocks;
    }

    function setPointAllocationTemplates(uint256[5][5] memory _pointAllocationTemplates) public onlyOwner {
        _setPointAllocationTemplates(_pointAllocationTemplates);
    }

    function setActivePointAllocationTemplate(PointAllocationTemplate _pointAllocationTemplate) public onlyOwner {
        _setActivePointAllocationTemplate(_pointAllocationTemplate);
    }

    receive() external payable {
        depositToTreasury(msg.value);
    }
}
