// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {Trustus} from "trustus/Trustus.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract KingOfTheDegensTest is Test {
    KingOfTheDegens public kingOfTheDegens;
    address public immutable userAddress = address(12345);
    uint256 public immutable userAddressKingSeed = 4;
    uint256 public immutable userAddressLordSeed = 8;
    uint256 public immutable userAddressKnightSeed = 5;
    uint256 public immutable userAddressTownsfolkSeed = 1;
    address public immutable altUserAddress = address(123456789);
    uint256 public immutable altUserAddressKingSeed = 610;
    uint256 public trustedSignerPrivateKey = vm.envUint("TRUSTUS_SIGNER_PRIVATE_KEY");
    address public trustedSignerAddress = vm.addr(trustedSignerPrivateKey);
    // Settings
    uint256 public immutable gameDurationBlocks = 42300;
    uint256 public immutable protocolFeePercentage = 1000;
    uint256 public immutable stormFrequencyBlocks = 1800;
    uint256 public immutable redeemAfterGameEndedBlocks = 2592000;
    uint256[7][5] public pointAllocationTemplates = [
        [3100, 1400, 600, 350, 300, 300, 300],
        [4900, 1300, 500, 250, 0, 0, 0],
        [3100, 1400, 900, 350, 0, 0, 0],
        [2400, 1500, 800, 550, 0, 0, 0],
        [0, 1400, 1900, 375, 0, 0, 0]
    ];
    uint256[4] public courtRoleOdds = [500, 1000, 2500, 6000];
    uint256[7] public roleCounts = [1, 2, 3, 4, 1, 1, 1];
    // Starting Court
    address[1] public king = [address(1)];
    address[2] public lords = [address(2), address(3)];
    address[3] public knights = [address(4), address(5), address(6)];
    address[4] public townsfolk = [address(7), address(8), address(9), address(10)];

    struct StormResults {
        address accountAddress;
        KingOfTheDegens.CourtRole courtRole;
        address outAddress;
        uint256 fid;
    }

    struct ActionResults {
        address accountAddress;
        address outAddress;
        uint256 outData;
        string actionType;
    }

    struct RedeemResults {
        address accountAddress;
        uint256 amountRedeemed;
        uint256 pointsRedeemed;
    }

    function setUp() public virtual {
        // Deploy
        kingOfTheDegens = new KingOfTheDegens(
            gameDurationBlocks,
            1e15,
            protocolFeePercentage,
            stormFrequencyBlocks,
            redeemAfterGameEndedBlocks,
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
            0
        );
        // Set Trustus address
        kingOfTheDegens.setIsTrusted(trustedSignerAddress, true);
    }

    function test_GameStatus() public {
        uint256 origBlockNumber = block.number;
        // Start at block 1
        vm.roll(1);
        assertEq(kingOfTheDegens.isGameStarted(), false);
        assertEq(kingOfTheDegens.isGameActive(), false);
        // Increment block.number to current
        vm.roll(origBlockNumber);
        assertEq(kingOfTheDegens.isGameStarted(), true);
        assertEq(kingOfTheDegens.isGameEnded(), false);
        // Increment block.number + 10 blocks
        vm.roll(origBlockNumber + 10);
        assertEq(kingOfTheDegens.isGameActive(), true);
        // Increment block.number to last active block
        uint256 expectedLastGameBlock = origBlockNumber + (gameDurationBlocks - 1);
        vm.roll(expectedLastGameBlock);
        assertEq(kingOfTheDegens.isGameActive(), true);
        assertEq(expectedLastGameBlock, kingOfTheDegens.gameLastBlock());
        // Increment block.number to game end
        uint256 expectedEndGameBlock = origBlockNumber + gameDurationBlocks;
        vm.roll(expectedEndGameBlock);
        assertEq(kingOfTheDegens.isGameEnded(), true);
        assertEq(kingOfTheDegens.isGameActive(), false);
        assertEq(expectedEndGameBlock, kingOfTheDegens.gameEndBlock());
    }

    function test_StormTheCastleEvent() public {
        StormResults memory stormResults = doStorm(userAddress);
        // User Address
        assertEq(stormResults.accountAddress, userAddress);
        // Court Role
        uint8 courtRole = uint8(uint256(stormResults.courtRole));
        assertGe(courtRole, 0);
        assertLe(courtRole, 5);
        // Out Address
        assertEq(stormResults.outAddress, address(7));
        // FID
        assertEq(stormResults.fid, 0);
    }

    function test_ProtocolFees() public {
        doStorm(userAddress);
        // Check protocol fee as native
        assertEq(getProtocolFeeBalance(), getProtocolFee(kingOfTheDegens.stormFee()));
        // Fast forward to end of game
        vm.roll(block.number + gameDurationBlocks);
        // Collect protocol fees
        uint256 ownerBalanceBeforeProtocol = address(this).balance;
        kingOfTheDegens.collectProtocolFees();
        assertEq(address(this).balance, ownerBalanceBeforeProtocol + getProtocolFee(kingOfTheDegens.stormFee()));
        assertEq(getProtocolFeeBalance(), 0);
        // Fast forward to end of redeem
        vm.roll(block.number + redeemAfterGameEndedBlocks);
        // Protocol redeem
        uint256 ownerBalanceBeforeRedeem = address(this).balance;
        uint256 gameBalance = address(kingOfTheDegens).balance;
        kingOfTheDegens.protocolRedeem();
        assertEq(address(kingOfTheDegens).balance, 0);
        assertEq(address(this).balance, ownerBalanceBeforeRedeem + gameBalance);
    }

    function test_DepositDegen() public virtual {
        uint256 totalAssetsBefore = kingOfTheDegens.totalAssets();
        deal(address(kingOfTheDegens.degenToken()), userAddress, 10_000 ether);
        vm.startPrank(userAddress);
        kingOfTheDegens.degenToken().approve(address(kingOfTheDegens), 10_000 ether);
        kingOfTheDegens.depositDegenToGameAssets(10_000 ether);
        vm.stopPrank();
        assertEq(kingOfTheDegens.totalAssets(), totalAssetsBefore + 10_000 ether);
    }

    function test_FlowRates() public {
        StormResults memory stormResults = doStorm(userAddress, random(), 0);
        uint256 expectedUserAssets = kingOfTheDegens.convertPointsToAssets(
            kingOfTheDegens.getPointsPerBlock(stormResults.courtRole) * gameDurationBlocks
        );
        // Fast forward to end of game
        vm.roll(kingOfTheDegens.gameEndBlock());
        assertEq(kingOfTheDegens.isGameEnded(), true);
        uint256 balanceBefore = getAddressBalance(userAddress);
        doRedeem(userAddress);
        assertEq(balanceBefore + expectedUserAssets, getAddressBalance(userAddress));
    }

    function test_King() public {
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        StormResults memory stormResults = doStorm(userAddress, userAddressKingSeed, 0);
        uint256 userBalanceBefore = getAddressBalance(userAddress);
        assertEq(kingOfTheDegens.court(0), userAddress);
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        StormResults memory altStormResults = doStorm(altUserAddress, altUserAddressKingSeed, 0);
        uint256 altUserBalanceBefore = getAddressBalance(altUserAddress);
        assertEq(kingOfTheDegens.court(0), altUserAddress);
        // Fast forward to end of game
        vm.roll(kingOfTheDegens.gameEndBlock());
        uint256 expectedUserAssets = kingOfTheDegens.convertPointsToAssets(
            kingOfTheDegens.getPointsPerBlock(stormResults.courtRole) * kingOfTheDegens.kingProtectionBlocks()
        );
        doRedeem(userAddress);
        assertEq(userBalanceBefore + expectedUserAssets, getAddressBalance(userAddress));
        uint256 expectedAltUserAssets = kingOfTheDegens.convertPointsToAssets(
            kingOfTheDegens.getPointsPerBlock(altStormResults.courtRole) * (gameDurationBlocks - (kingOfTheDegens.kingProtectionBlocks() * 2))
        );
        doRedeem(altUserAddress);
        assertEq(altUserBalanceBefore + expectedAltUserAssets, getAddressBalance(altUserAddress));
    }

    // ACTIONS
    function test_SetJester() public {
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        doStorm(userAddress, userAddressKingSeed, 0);
        assertEq(uint8(kingOfTheDegens.courtRoles(userAddress)), uint8(KingOfTheDegens.CourtRole.King));
        // Add new Jester (not in game)
        vm.roll(block.number + 100);
        ActionResults memory actionResults = doJester(userAddress, address(55555), 0);
        assertEq(actionResults.outAddress, address(0));
        assertEq(address(55555), kingOfTheDegens.custom1()[0]);
        // Swap court member with jester
        vm.roll(block.number + 100);
        ActionResults memory actionResults2 = doJester(userAddress, address(2), 0);
        assertEq(actionResults2.outAddress, address(55555));
        assertEq(address(55555), kingOfTheDegens.lords()[0]);
        assertEq(address(2), kingOfTheDegens.custom1()[0]);
    }

    function test_SetPointStrategy() public {
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        doStorm(userAddress, userAddressKingSeed, 0);
        assertEq(uint8(kingOfTheDegens.courtRoles(userAddress)), uint8(KingOfTheDegens.CourtRole.King));
        ActionResults memory actionResults = doPointStrategy(userAddress, uint8(KingOfTheDegens.PointAllocationTemplate.Military));
        assertEq(actionResults.outAddress, address(0));
        comparePointAllocation(KingOfTheDegens.CourtRole.King, KingOfTheDegens.PointAllocationTemplate.Military);
        comparePointAllocation(KingOfTheDegens.CourtRole.Lord, KingOfTheDegens.PointAllocationTemplate.Military);
        comparePointAllocation(KingOfTheDegens.CourtRole.Knight, KingOfTheDegens.PointAllocationTemplate.Military);
        comparePointAllocation(KingOfTheDegens.CourtRole.Townsfolk, KingOfTheDegens.PointAllocationTemplate.Military);
        comparePointAllocation(KingOfTheDegens.CourtRole.Custom1, KingOfTheDegens.PointAllocationTemplate.Military);
        ActionResults memory actionResults2 = doPointStrategy(userAddress, uint8(KingOfTheDegens.PointAllocationTemplate.Peoples));
        assertEq(actionResults2.outAddress, address(0));
        comparePointAllocation(KingOfTheDegens.CourtRole.King, KingOfTheDegens.PointAllocationTemplate.Peoples);
        comparePointAllocation(KingOfTheDegens.CourtRole.Lord, KingOfTheDegens.PointAllocationTemplate.Peoples);
        comparePointAllocation(KingOfTheDegens.CourtRole.Knight, KingOfTheDegens.PointAllocationTemplate.Peoples);
        comparePointAllocation(KingOfTheDegens.CourtRole.Townsfolk, KingOfTheDegens.PointAllocationTemplate.Peoples);
        comparePointAllocation(KingOfTheDegens.CourtRole.Custom1, KingOfTheDegens.PointAllocationTemplate.Peoples);
    }

    function testFail_SetPointStrategy() public {
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        doStorm(userAddress, userAddressKingSeed, 0);
        assertEq(uint8(kingOfTheDegens.courtRoles(userAddress)), uint8(KingOfTheDegens.CourtRole.King));
        doPointStrategy(userAddress, uint8(21));
    }

    function test_SetStormFee() public {
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        StormResults memory stormResults = doStorm(userAddress, userAddressLordSeed, 0);
        assertEq(uint8(stormResults.courtRole), uint8(KingOfTheDegens.CourtRole.Lord));
        assertEq(uint8(kingOfTheDegens.courtRoles(userAddress)), uint8(KingOfTheDegens.CourtRole.Lord));
        assertEq(kingOfTheDegens.stormFee(), 1e15);
        doStormFee(userAddress, 2e15);
        assertEq(kingOfTheDegens.stormFee(), 2e15);
        assertEq(getProtocolFee(kingOfTheDegens.stormFee()), 2e14);
        vm.roll(block.number + 100);
        doStormFee(userAddress, 1e15);
        assertEq(kingOfTheDegens.stormFee(), 1e15);
        assertEq(getProtocolFee(kingOfTheDegens.stormFee()), 1e14);
    }

    function test_AttackKing() public {
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        StormResults memory stormResults = doStorm(userAddress, userAddressKnightSeed, 0);
        assertEq(uint8(stormResults.courtRole), uint8(KingOfTheDegens.CourtRole.Knight));
        ActionResults memory actionResults = doAttackKing(userAddress, false);
        assertEq(actionResults.outAddress, address(0));
        assertEq(actionResults.outData, 0);
        comparePointAllocation(KingOfTheDegens.CourtRole.King, kingOfTheDegens.activePointAllocationTemplate());
        ActionResults memory actionResults2 = doAttackKing(userAddress, true);
        assertEq(actionResults2.outAddress, kingOfTheDegens.king()[0]);
        assertEq(actionResults2.outData, 1);
        comparePointAllocation(KingOfTheDegens.CourtRole.King, KingOfTheDegens.PointAllocationTemplate.Dead);
    }

    function test_PointsHelper() public {
        doStorm(userAddress, userAddressKingSeed, 0);
        uint256[13] memory courtPoints = kingOfTheDegens.getCourtMemberPoints();
        assertEq(courtPoints[0], 0);
        vm.roll(block.number + 10_000);
        uint256[13] memory courtPointsAfter = kingOfTheDegens.getCourtMemberPoints();
        assertEq(courtPointsAfter[0], kingOfTheDegens.getPointsPerBlock(KingOfTheDegens.CourtRole.King) * 10_000);
    }

    function testFail_StormTheCastleBadPacket() public {
        doStorm(address(1010));
    }

    function testFail_PauseStorm() public {
        kingOfTheDegens.togglePause();
        doStorm(address(userAddress));
    }

    function testFail_PauseRedeem() public {
        doStorm(userAddress, userAddressKingSeed, 0);
        // Fast forward to end of game
        vm.roll(kingOfTheDegens.gameEndBlock());
        kingOfTheDegens.togglePause();
        doRedeem(userAddress);
    }

    function test_StormFrequency() public {
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        kingOfTheDegens.setStormFrequency(1);
        doStorm(userAddress, userAddressKingSeed, 0);
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        doStorm(altUserAddress, altUserAddressKingSeed, 0);
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        doStorm(userAddress, userAddressKingSeed, 0);
    }

    function testFail_StormFrequency() public {
        doStorm(userAddress, userAddressKingSeed, 0);
        vm.roll(block.number + 1);
        doStorm(altUserAddress, altUserAddressKingSeed, 0);
        vm.roll(block.number + 1);
        doStorm(userAddress, userAddressKingSeed, 0);
    }

    function test_KingProtection() public {
        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
        // Crown New King
        doStorm(userAddress, userAddressKingSeed, 0);
        assertEq(kingOfTheDegens.getKingRange(), 100);
        vm.roll(block.number + 1350);
        assertEq(kingOfTheDegens.getKingRange(), 150);
        vm.roll(block.number + 1350);
        assertEq(kingOfTheDegens.getKingRange(), 200);
        vm.roll(block.number + 1350);
        assertEq(kingOfTheDegens.getKingRange(), 250);
        vm.roll(block.number + 1350);
        assertEq(kingOfTheDegens.getKingRange(), 300);
        vm.roll(block.number + 1350);
        assertEq(kingOfTheDegens.getKingRange(), 350);
        vm.roll(block.number + 1350);
        assertEq(kingOfTheDegens.getKingRange(), 400);
        vm.roll(block.number + 1350);
        assertEq(kingOfTheDegens.getKingRange(), 450);
        vm.roll(block.number + 1350);
        assertEq(kingOfTheDegens.getKingRange(), 500);
    }

    function test_SetCourtRoleOdds() public {
        assertEq(kingOfTheDegens.courtRoleOddsCeilings(0), courtRoleOdds[0]);
        assertEq(kingOfTheDegens.courtRoleOddsCeilings(1), courtRoleOdds[0] + courtRoleOdds[1]);
        assertEq(kingOfTheDegens.courtRoleOddsCeilings(2), courtRoleOdds[0] + courtRoleOdds[1] + courtRoleOdds[2]);
        uint256[4] memory newOdds = [uint256(200),uint256(300),uint256(500),uint256(9000)];
        kingOfTheDegens.setCourtRoleOdds(newOdds);
        assertEq(kingOfTheDegens.courtRoleOddsCeilings(0), 200);
        assertEq(kingOfTheDegens.courtRoleOddsCeilings(1), 500);
        assertEq(kingOfTheDegens.courtRoleOddsCeilings(2), 1000);
    }

    function test_PointAllocation() public {
        comparePointAllocation(KingOfTheDegens.CourtRole.King, kingOfTheDegens.activePointAllocationTemplate());
        comparePointAllocation(KingOfTheDegens.CourtRole.Lord, kingOfTheDegens.activePointAllocationTemplate());
        comparePointAllocation(KingOfTheDegens.CourtRole.Knight, kingOfTheDegens.activePointAllocationTemplate());
        comparePointAllocation(KingOfTheDegens.CourtRole.Townsfolk, kingOfTheDegens.activePointAllocationTemplate());
        comparePointAllocation(KingOfTheDegens.CourtRole.Custom1, kingOfTheDegens.activePointAllocationTemplate());
        kingOfTheDegens.setActivePointAllocationTemplate(KingOfTheDegens.PointAllocationTemplate.Greedy);
        comparePointAllocation(KingOfTheDegens.CourtRole.King, KingOfTheDegens.PointAllocationTemplate.Greedy);
        comparePointAllocation(KingOfTheDegens.CourtRole.Lord, KingOfTheDegens.PointAllocationTemplate.Greedy);
        comparePointAllocation(KingOfTheDegens.CourtRole.Knight, KingOfTheDegens.PointAllocationTemplate.Greedy);
        comparePointAllocation(KingOfTheDegens.CourtRole.Townsfolk, KingOfTheDegens.PointAllocationTemplate.Greedy);
        comparePointAllocation(KingOfTheDegens.CourtRole.Custom1, KingOfTheDegens.PointAllocationTemplate.Greedy);
    }

    function comparePointAllocation(
        KingOfTheDegens.CourtRole courtRole,
        KingOfTheDegens.PointAllocationTemplate pointAllocationTemplate
    ) internal {
        assertEq(
            kingOfTheDegens.getActiveCourtRolePointAllocation(courtRole),
            kingOfTheDegens.getCourtRolePointAllocation(courtRole, pointAllocationTemplate)
        );
    }

    function test_SendETH() public virtual {
        address friendlyUser = address(123123123456);
        uint256 degenBalanceBefore = getAddressBalance(address(kingOfTheDegens));
        hoax(friendlyUser);
        uint256 protocolFeeBalanceBefore = address(kingOfTheDegens).balance;
        uint256 balanceBefore = address(friendlyUser).balance;
        SafeTransferLib.safeTransferETH(address(kingOfTheDegens), 1 ether);
        assertEq(balanceBefore, address(friendlyUser).balance + 1 ether);
        assertEq(protocolFeeBalanceBefore, address(kingOfTheDegens).balance - getProtocolFee(1 ether));
        assertGt(getAddressBalance(address(kingOfTheDegens)), degenBalanceBefore);
    }

//    function test_FindCourtRole() public {
//        vm.roll(block.number + kingOfTheDegens.kingProtectionBlocks());
//        uint256 randomSeed = kingOfTheDegens.findCourtRole(userAddress, KingOfTheDegens.CourtRole.King);
//        console.log(randomSeed);
//    }

    function doRedeem(address accountAddress) internal returns (RedeemResults memory) {
        vm.recordLogs();
        vm.prank(accountAddress);
        kingOfTheDegens.redeem();
        return processRedeemLogs();
    }

    function doStorm(address accountAddress) internal returns (StormResults memory) {
        return doStorm(accountAddress, 0, 0);
    }

    function doStorm(address accountAddress, uint256 randomSeed, uint256 fid) internal returns (StormResults memory) {
        Trustus.TrustusPacket memory trustusPacket = buildPacket(
            keccak256(abi.encodePacked("stormTheCastle(TrustusPacket)")),
            abi.encode(randomSeed, fid),
            accountAddress == address(1010)
        );
        uint256 playAmount = kingOfTheDegens.stormFee();
        vm.recordLogs();
        // Storm the castle
        hoax(accountAddress);
        kingOfTheDegens.stormTheCastle{value: playAmount}(trustusPacket);
        return processStormLogs();
    }

    function doJester(address accountAddress, address jesterAddress, uint256 fid) internal returns (ActionResults memory) {
        Trustus.TrustusPacket memory trustusPacket = buildPacket(
            keccak256(abi.encodePacked("setJesterRole(TrustusPacket)")),
            abi.encode(jesterAddress, fid),
            accountAddress == address(1010)
        );
        uint256 playAmount = kingOfTheDegens.stormFee();
        vm.recordLogs();
        hoax(accountAddress);
        kingOfTheDegens.setJesterRole{value: playAmount}(trustusPacket);
        return processActionLogs();
    }

    function doPointStrategy(address accountAddress, uint8 _pointAllocationTemplate) internal returns (ActionResults memory) {
        Trustus.TrustusPacket memory trustusPacket = buildPacket(
            keccak256(abi.encodePacked("setPointStrategy(TrustusPacket)")),
            abi.encode(_pointAllocationTemplate),
            accountAddress == address(1010)
        );
        uint256 playAmount = kingOfTheDegens.stormFee();
        vm.recordLogs();
        hoax(accountAddress);
        kingOfTheDegens.setPointStrategy{value: playAmount}(trustusPacket);
        return processActionLogs();
    }

    function doStormFee(address accountAddress, uint256 _stormFee) internal returns (ActionResults memory) {
        Trustus.TrustusPacket memory trustusPacket = buildPacket(
            keccak256(abi.encodePacked("setStormFee(TrustusPacket)")),
            abi.encode(_stormFee),
            accountAddress == address(1010)
        );
        uint256 playAmount = kingOfTheDegens.stormFee();
        vm.recordLogs();
        hoax(accountAddress);
        kingOfTheDegens.setStormFee{value: playAmount}(trustusPacket);
        return processActionLogs();
    }

    function doAttackKing(address accountAddress, bool isKingDead) internal returns (ActionResults memory) {
        Trustus.TrustusPacket memory trustusPacket = buildPacket(
            keccak256(abi.encodePacked("attackKing(TrustusPacket)")),
            abi.encode(isKingDead),
            accountAddress == address(1010)
        );
        uint256 playAmount = kingOfTheDegens.stormFee();
        vm.recordLogs();
        hoax(accountAddress);
        kingOfTheDegens.attackKing{value: playAmount}(trustusPacket);
        return processActionLogs();
    }

    function processActionLogs() internal returns (ActionResults memory) {
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 eventTopic = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Action(address,address,uint256,string)")) {
                eventTopic = i;
            }
        }

        return ActionResults(
            address(uint160(uint256(entries[eventTopic].topics[1]))),
            address(uint160(uint256(entries[eventTopic].topics[2]))),
            uint256(entries[eventTopic].topics[3]),
            abi.decode(entries[eventTopic].data, (string))
        );
    }

    function processStormLogs() internal returns (StormResults memory) {
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 stormTopic = 0;
        for (uint256 i = 0;i < entries.length;i++) {
            if (entries[i].topics[0] == keccak256("StormTheCastle(address,uint8,address,uint256)")) {
                stormTopic = i;
            }
        }

        return StormResults(
            address(uint160(uint256(entries[stormTopic].topics[1]))),
            KingOfTheDegens.CourtRole(uint8(uint256(entries[stormTopic].topics[2]))),
            address(uint160(uint256(entries[stormTopic].topics[3]))),
            abi.decode(entries[stormTopic].data, (uint256))
        );
    }

    function processRedeemLogs() internal returns (RedeemResults memory) {
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 redeemTopic = 0;
        for (uint256 i = 0;i < entries.length;i++) {
            if (entries[i].topics[0] == keccak256("Redeemed(address,uint256,uint256)")) {
                redeemTopic = i;
            }
        }
        return RedeemResults(
            address(uint160(uint256(entries[redeemTopic].topics[1]))),
            uint256(entries[redeemTopic].topics[2]),
            uint256(entries[redeemTopic].topics[3])
        );
    }

    function buildPacket(bytes32 requestName, bytes memory payload, bool badSigner) internal view returns (Trustus.TrustusPacket memory) {
        uint256 deadline = block.timestamp + 300; // 5 minutes
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                kingOfTheDegens.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "VerifyPacket(bytes32 request,uint256 deadline,bytes payload)"
                        ),
                        requestName,
                        deadline,
                        keccak256(payload)
                    )
                )
            )
        );

        uint256 pk = badSigner ? 1010 : trustedSignerPrivateKey;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        return Trustus.TrustusPacket({
            v: v,
            r: r,
            s: s,
            request: requestName,
            deadline: deadline,
            payload: payload
        });
    }

    function random() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            tx.origin,
            blockhash(block.number - 1),
            block.timestamp
        )));
    }

    function getProtocolFeeBalance() internal view virtual returns (uint256) {
        return address(kingOfTheDegens).balance;
    }

    function getAddressBalance(address accountAddress) internal view virtual returns (uint256) {
        return kingOfTheDegens.degenToken().balanceOf(accountAddress);
    }

    function getProtocolFee(uint256 amountIn) internal view returns (uint256) {
        return (amountIn * kingOfTheDegens.protocolFeePercent()) / 10_000;
    }
    
    receive() external payable {}
}
