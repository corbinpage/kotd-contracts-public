// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {KingOfTheDegens} from "../src/KingOfTheDegens.sol";
import {Trustus} from "trustus/Trustus.sol";

contract KingOfTheDegensTest is Test {
    KingOfTheDegens public kingOfTheDegens;
    address public immutable userAddress = address(12345);
    uint256 public immutable userAddressKingSeed = 23;
    address public immutable altUserAddress = address(123456789);
    uint256 public immutable altUserAddressKingSeed = 2;
    bytes32 public immutable stormEventHash = keccak256("StormTheCastle(address,uint8,address,uint256)");
    bytes32 public immutable redeemEventHash = keccak256("Redeemed(address,uint256,uint256)");
    uint256 public trustedSignerPrivateKey = vm.envUint("TRUSTUS_SIGNER_PRIVATE_KEY");
    address public trustedSignerAddress = vm.addr(trustedSignerPrivateKey);
    // Settings
    uint256 public immutable gameDurationBlocks = 42300;
    uint256 public immutable minPlayAmount = 1e15;
    uint256 public immutable protocolFee = 1e14;
    uint256 public immutable stormFrequencyBlocks = 1800;
    uint256 public immutable redeemAfterGameEndedBlocks = 2592000;
    uint256[4] public courtBps = [3300, 1400, 700, 450];
    uint8[4] public courtRolePercentages = [5, 10, 20, 65];
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

    struct RedeemResults {
        address accountAddress;
        uint256 amountRedeemed;
        uint256 pointsRedeemed;
    }

    function setUp() public {
        // Deploy
        kingOfTheDegens = new KingOfTheDegens(
            gameDurationBlocks,
            minPlayAmount,
            protocolFee,
            stormFrequencyBlocks,
            redeemAfterGameEndedBlocks,
            courtBps,
            courtRolePercentages
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
        assertEq(kingOfTheDegens.protocolFeeBalance(), protocolFee);
        // Fast forward to end of game
        vm.roll(block.number + gameDurationBlocks);
        // Collect protocol fees
        uint256 ownerBalanceBeforeProtocol = address(this).balance;
        kingOfTheDegens.collectProtocolFees();
        assertEq(address(this).balance, ownerBalanceBeforeProtocol + protocolFee);
        assertEq(kingOfTheDegens.protocolFeeBalance(), 0);
        // Fast forward to end of redeem
        vm.roll(block.number + redeemAfterGameEndedBlocks);
        // Protocol redeem
        uint256 ownerBalanceBeforeRedeem = address(this).balance;
        uint256 gameBalance = address(kingOfTheDegens).balance;
        kingOfTheDegens.protocolRedeem();
        assertEq(address(kingOfTheDegens).balance, 0);
        assertEq(address(this).balance, ownerBalanceBeforeRedeem + gameBalance);
    }

    function test_DepositDegen() public {
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
        uint256 expectedUserAssets = kingOfTheDegens.convertPoints(
            kingOfTheDegens.getPointsPerBlock(stormResults.courtRole) * gameDurationBlocks
        );
        // Fast forward to end of game
        vm.roll(kingOfTheDegens.gameEndBlock());
        assertEq(kingOfTheDegens.isGameEnded(), true);
        uint256 balanceBefore = kingOfTheDegens.degenToken().balanceOf(userAddress);
        doRedeem(userAddress);
        assertEq(balanceBefore + expectedUserAssets, kingOfTheDegens.degenToken().balanceOf(userAddress));
    }

    function test_King() public {
        // Fast forward 10800 blocks so king role is easier
        vm.roll(block.number + 10800);
        StormResults memory stormResults = doStorm(userAddress, userAddressKingSeed, 0);
        uint256 userBalanceBefore = kingOfTheDegens.degenToken().balanceOf(userAddress);
        assertEq(kingOfTheDegens.king(0), userAddress);
        // Fast forward 10_000 blocks
        vm.roll(block.number + 10800);
        StormResults memory altStormResults = doStorm(altUserAddress, altUserAddressKingSeed, 0);
        uint256 altUserBalanceBefore = kingOfTheDegens.degenToken().balanceOf(altUserAddress);
        assertEq(kingOfTheDegens.king(0), altUserAddress);
        // Fast forward to end of game
        vm.roll(kingOfTheDegens.gameEndBlock());
        uint256 expectedUserAssets = kingOfTheDegens.convertPoints(
            kingOfTheDegens.getPointsPerBlock(stormResults.courtRole) * 10800
        );
        doRedeem(userAddress);
        assertEq(userBalanceBefore + expectedUserAssets, kingOfTheDegens.degenToken().balanceOf(userAddress));
        uint256 expectedAltUserAssets = kingOfTheDegens.convertPoints(
            kingOfTheDegens.getPointsPerBlock(altStormResults.courtRole) * (gameDurationBlocks - (10800 * 2))
        );
        doRedeem(altUserAddress);
        assertEq(altUserBalanceBefore + expectedAltUserAssets, kingOfTheDegens.degenToken().balanceOf(altUserAddress));
    }

    function test_PointsHelper() public {
        doStorm(userAddress, userAddressKingSeed, 0);
        uint256[10] memory courtPoints = kingOfTheDegens.getCourtMemberPoints();
        assertEq(courtPoints[0], 0);
        vm.roll(block.number + 10_000);
        uint256[10] memory courtPointsAfter = kingOfTheDegens.getCourtMemberPoints();
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
        doStorm(userAddress, random(), 0);
        // Fast forward to end of game
        vm.roll(kingOfTheDegens.gameEndBlock());
        kingOfTheDegens.togglePause();
        doRedeem(userAddress);
    }

    function test_StormFrequency() public {
        // Fast forward 10800 blocks so king role is easier
        vm.roll(block.number + 10800);
        kingOfTheDegens.setStormFrequency(1);
        doStorm(userAddress, userAddressKingSeed, 0);
        vm.roll(block.number + 10800);
        doStorm(altUserAddress, altUserAddressKingSeed, 0);
        vm.roll(block.number + 10800);
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
        // Fast forward 10800 blocks so king role is easier
        vm.roll(block.number + 10800);
        // Crown New King
        doStorm(userAddress, userAddressKingSeed, 0);
        for (uint256 i = 1;i <= 5;i++) {
            assertEq(kingOfTheDegens.getKingRange(), i);
            vm.roll(block.number + 2700);
        }
    }

    function test_SetCourtRolePercentages() public {
        assertEq(kingOfTheDegens.roleRanges(0), courtRolePercentages[0]);
        assertEq(kingOfTheDegens.roleRanges(1), courtRolePercentages[0] + courtRolePercentages[1]);
        assertEq(kingOfTheDegens.roleRanges(2), courtRolePercentages[0] + courtRolePercentages[1] + courtRolePercentages[2]);
        uint8[4] memory percentages = [2,3,5,90];
        kingOfTheDegens.setCourtRolePercentages(percentages);
        assertEq(kingOfTheDegens.roleRanges(0), 2);
        assertEq(kingOfTheDegens.roleRanges(1), 5);
        assertEq(kingOfTheDegens.roleRanges(2), 10);
    }

    function test_CourtBps() public {
        assertEq(kingOfTheDegens.courtBps(KingOfTheDegens.CourtRole.King), courtBps[0]);
        assertEq(kingOfTheDegens.courtBps(KingOfTheDegens.CourtRole.Lord), courtBps[1]);
        assertEq(kingOfTheDegens.courtBps(KingOfTheDegens.CourtRole.Knight), courtBps[2]);
        assertEq(kingOfTheDegens.courtBps(KingOfTheDegens.CourtRole.Townsfolk), courtBps[3]);
        uint256[4] memory _courtBps = [uint256(2000), uint256(1500), uint256(1500), uint256(5000)];
        kingOfTheDegens.setCourtBps(_courtBps);
        assertEq(kingOfTheDegens.courtBps(KingOfTheDegens.CourtRole.King), 2000);
        assertEq(kingOfTheDegens.courtBps(KingOfTheDegens.CourtRole.Lord), 1500);
        assertEq(kingOfTheDegens.courtBps(KingOfTheDegens.CourtRole.Knight), 1500);
        assertEq(kingOfTheDegens.courtBps(KingOfTheDegens.CourtRole.Townsfolk), 5000);
    }

    function doRedeem(address accountAddress) private returns (RedeemResults memory) {
        vm.recordLogs();
        vm.prank(accountAddress);
        kingOfTheDegens.redeem();
        // Event
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 redeemTopic = 0;
        for (uint256 i = 0;i < entries.length;i++) {
            if (entries[i].topics[0] == redeemEventHash) {
                redeemTopic = i;
            }
        }
        return RedeemResults(
            address(uint160(uint256(entries[redeemTopic].topics[1]))),
            uint256(entries[redeemTopic].topics[2]),
            uint256(entries[redeemTopic].topics[3])
        );
    }

    function doStorm(address accountAddress, uint256 randomSeed, uint256 fid) private returns (StormResults memory) {
        Trustus.TrustusPacket memory trustusPacket = buildPacket(accountAddress, randomSeed, fid);
        vm.recordLogs();
        // Storm the castle
        hoax(accountAddress);
        kingOfTheDegens.stormTheCastle{value: minPlayAmount}(trustusPacket);
        // Event
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 stormTopic = 0;
        for (uint256 i = 0;i < entries.length;i++) {
            if (entries[i].topics[0] == stormEventHash) {
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

    function doStorm(address accountAddress) private returns (StormResults memory) {
        return doStorm(accountAddress, 0, 0);
    }

    function deployNewContract() public returns (KingOfTheDegens) {
        return new KingOfTheDegens(
            gameDurationBlocks,
            minPlayAmount,
            protocolFee,
            stormFrequencyBlocks,
            redeemAfterGameEndedBlocks,
            courtBps,
            courtRolePercentages
        );
    }

    function buildPacket(address accountAddress, uint256 randomSeed, uint256 fid) private view returns (Trustus.TrustusPacket memory) {
        uint256 deadline = block.timestamp + 300; // 5 minutes
        bytes memory payload = abi.encode(randomSeed, fid);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                kingOfTheDegens.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "VerifyPacket(bytes32 request,uint256 deadline,bytes payload)"
                        ),
                        kingOfTheDegens.TRUSTUS_STORM(),
                        deadline,
                        keccak256(payload)
                    )
                )
            )
        );
        uint256 pk = accountAddress == address(1010) ? 1010 : trustedSignerPrivateKey;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        return Trustus.TrustusPacket({
            v: v,
            r: r,
            s: s,
            request: kingOfTheDegens.TRUSTUS_STORM(),
            deadline: deadline,
            payload: payload
        });
    }

    function random() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            tx.origin,
            blockhash(block.number - 1),
            block.timestamp
        )));
    }

    receive() external payable {}
}
