// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {KingOfTheDegen} from "../src/KingOfTheDegen.sol";

contract KingOfTheDegenTest is Test {
    KingOfTheDegen public kingOfTheDegen;
    address public immutable userAddress = address(12345);
    uint256 public immutable userAddressKingSeed = 23;
    address public immutable altUserAddress = address(123456789);
    uint256 public immutable altUserAddressKingSeed = 2;
    bytes32 public immutable stormEventHash = keccak256("StormTheCastle(address,uint8,uint256,uint256)");
    bytes32 public immutable redeemEventHash = keccak256("Redeemed(address,uint256,uint256)");

    // Settings
    uint256 public immutable gameDurationBlocks = 42300;
    uint256 public immutable minPlayAmount = 1e15;
    uint256 public immutable protocolFee = 1e14;
    uint256 public immutable stormFrequencyBlocks = 1800;
    uint256 public immutable redeemAfterGameEndedBlocks = 2592000;
    uint256[4] public courtBps = [3300, 1400, 700, 450];
    // Starting Court
    address[1] public king = [address(1)];
    address[2] public lords = [address(2), address(3)];
    address[3] public knights = [address(4), address(5), address(6)];
    address[4] public townsfolk = [address(7), address(8), address(9), address(10)];

    struct StormResults {
        address accountAddress;
        KingOfTheDegen.CourtRole courtRole;
        uint256 amountSent;
        uint256 fid;
    }

    struct RedeemResults {
        address accountAddress;
        uint256 amountRedeemed;
        uint256 pointsRedeemed;
    }

    function setUp() public {
        // Deploy
        kingOfTheDegen = new KingOfTheDegen(
            gameDurationBlocks,
            minPlayAmount,
            protocolFee,
            stormFrequencyBlocks,
            redeemAfterGameEndedBlocks,
            courtBps
        );
        // Init
        kingOfTheDegen.startGame(
            king,
            lords,
            knights,
            townsfolk
        );
    }

    function test_GameStatus() public {
        uint256 origBlockNumber = block.number;
        // Start at block 1
        vm.roll(1);
        assertEq(kingOfTheDegen.isGameStarted(), false);
        assertEq(kingOfTheDegen.isGameActive(), false);
        // Increment block.number to current
        vm.roll(origBlockNumber);
        assertEq(kingOfTheDegen.isGameStarted(), true);
        assertEq(kingOfTheDegen.isGameEnded(), false);
        // Increment block.number + 10 blocks
        vm.roll(origBlockNumber + 10);
        assertEq(kingOfTheDegen.isGameActive(), true);
        // Increment block.number to last active block
        uint256 expectedLastGameBlock = origBlockNumber + (gameDurationBlocks - 1);
        vm.roll(expectedLastGameBlock);
        assertEq(kingOfTheDegen.isGameActive(), true);
        assertEq(expectedLastGameBlock, kingOfTheDegen.gameLastBlock());
        // Increment block.number to game end
        uint256 expectedEndGameBlock = origBlockNumber + gameDurationBlocks;
        vm.roll(expectedEndGameBlock);
        assertEq(kingOfTheDegen.isGameEnded(), true);
        assertEq(kingOfTheDegen.isGameActive(), false);
        assertEq(expectedEndGameBlock, kingOfTheDegen.gameEndBlock());
    }

    function test_StormTheCastleEvent() public {
        hoax(userAddress);
        StormResults memory stormResults = doStorm();
        // User Address
        assertEq(stormResults.accountAddress, userAddress);
        // Court Role
        uint8 courtRole = uint8(uint256(stormResults.courtRole));
        assertGe(courtRole, 0);
        assertLe(courtRole, 5);
        // Amount Sent
        assertEq(stormResults.amountSent, minPlayAmount);
        // FID
        assertEq(stormResults.fid, 0);
    }

    function test_ProtocolFees() public {
        hoax(userAddress);
        doStorm();
        // Check protocol fee as native
        assertEq(kingOfTheDegen.protocolFeeBalance(), protocolFee);
        // Fast forward to end of game
        vm.roll(block.number + gameDurationBlocks);
        // Collect protocol fees
        uint256 ownerBalanceBeforeProtocol = address(this).balance;
        kingOfTheDegen.collectProtocolFees();
        assertEq(address(this).balance, ownerBalanceBeforeProtocol + protocolFee);
        assertEq(kingOfTheDegen.protocolFeeBalance(), 0);
        // Fast forward to end of redeem
        vm.roll(block.number + redeemAfterGameEndedBlocks);
        // Protocol redeem
        uint256 ownerBalanceBeforeRedeem = address(this).balance;
        uint256 gameBalance = address(kingOfTheDegen).balance;
        kingOfTheDegen.protocolRedeem();
        assertEq(address(kingOfTheDegen).balance, 0);
        assertEq(address(this).balance, ownerBalanceBeforeRedeem + gameBalance);
    }

    function test_FlowRates() public {
        hoax(userAddress);
        StormResults memory stormResults = doStorm(random(), 0);
        uint256 expectedAmount = getPercentageFromCourtRole(
            kingOfTheDegen.totalAssets(),
            stormResults.courtRole
        );
        // Fast forward to end of game
        vm.roll(kingOfTheDegen.gameEndBlock());
        assertEq(kingOfTheDegen.isGameEnded(), true);
        uint256 balanceBefore = userAddress.balance;
        doRedeem(userAddress);
        assertEq(balanceBefore + expectedAmount, userAddress.balance);
    }

    function test_King() public {
        hoax(userAddress);
        uint256 origBlockNumber = block.number;
        StormResults memory stormResults = doStorm(userAddressKingSeed, 0);
        uint256 userBalanceBefore = userAddress.balance;
        uint256 expectedUserPoints = kingOfTheDegen.getPointsPerBlock(stormResults.courtRole) * (gameDurationBlocks);
        // Fast forward 10_000 blocks
//        vm.roll(block.number + 10000);
//        hoax(altUserAddress);
//        StormResults memory altStormResults = doStorm(altUserAddressKingSeed, 0);
//        console.log(kingOfTheDegen.totalAssets());
//        uint256 altUserBalanceBefore = altUserAddress.balance;
//        uint256 expectedAltUserPoints =
//            kingOfTheDegen.getPointsPerBlock(altStormResults.courtRole) * (gameDurationBlocks - 1001);
        // Fast forward to end of game
        vm.roll(kingOfTheDegen.gameEndBlock());
//        assertEq(kingOfTheDegen.king(0), altUserAddress);
        RedeemResults memory redeemResults = doRedeem(userAddress);
        console.logUint(expectedUserPoints);
        console.logUint(redeemResults.pointsRedeemed);
        console.logUint(kingOfTheDegen.convertPointsToNative(expectedUserPoints));
        console.logUint(redeemResults.amountRedeemed);
        //console.logUint(userAddress.balance - (userBalanceBefore + kingOfTheDegen.convertPointsToNative(expectedUserPoints)));
//        assertEq(
//            userBalanceBefore + kingOfTheDegen.convertPointsToNative(expectedUserPoints),
//            userAddress.balance
//        );
//        assertEq(
//            altUserBalanceBefore + kingOfTheDegen.convertPointsToNative(expectedAltUserPoints),
//            userAddress.balance
//        );
    }

    function doRedeem(address accountAddress) private returns (RedeemResults memory) {
        vm.recordLogs();
        vm.prank(accountAddress);
        kingOfTheDegen.redeem();
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

    function doStorm(uint256 randomSeed, uint256 fid) private returns (StormResults memory) {
        vm.recordLogs();
        // Storm the castle
        kingOfTheDegen.stormTheCastle{value: minPlayAmount}(randomSeed, fid);
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
            KingOfTheDegen.CourtRole(uint8(uint256(entries[stormTopic].topics[2]))),
            uint256(entries[stormTopic].topics[3]),
            abi.decode(entries[stormTopic].data, (uint256))
        );
    }

    function doStorm() private returns (StormResults memory) {
        return doStorm(0, 0);
    }

    function random() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            tx.origin,
            blockhash(block.number - 1),
            block.timestamp
        )));
    }

    function getPercentageFromCourtRole(
        uint256 amount,
        KingOfTheDegen.CourtRole courtRole
    ) public view returns (uint256) {
        uint256 bps = kingOfTheDegen.courtBps(courtRole);
        return (amount * bps) / 10_000;
    }

    receive() external payable {}
}
