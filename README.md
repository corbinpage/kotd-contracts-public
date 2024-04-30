## King of the Degens Contract
1. ERC20 Token: Takes in stormFee as native and converts to DEGEN before adding to treasury `(src/KingOfTheDegens.sol)`
2. Native: Takes in stormFee as native and stores treasury in native. Meant to be deployed to DEGEN chain or testnets without a DEGEN market. `(src/KingOfTheDegensNative.sol)`
### Play the Game

#### stormTheCastle
- `stormTheCastle(TrustusPacket calldata packet)`
- `packet.payload` => `abi.encode(uint256 randomSeed, uint256 fid)`
- This will add the `msg.sender` to a stormable Court Role based on chance. Primary game method.

#### runCourtRoleAction
- `runCourtRoleAction(TrustusPacket calldata packet)`
- `packet.payload` => `abi.encode(uint256 fid, address replaceAddress, uint256 courtIndex)`
- Use this method to swap `replaceAddress` with address in `court` at the `courtIndex` position. (eg. king[0] = 0, lords[0] = 1, lords[1] = 2, etc.)

#### runGameStateAction
- `runGameStateAction(TrustusPacket calldata packet)`
- `packet.payload` => `abi.encode(uint256 fid, uint256[4] allData, string actionType)`
- Use this method to modify Game States defined below. Make sure that you pass data in a uint256[4] array, even if only first item is relevant (ie. `[newStormFee, 0, 0, 0]`)
- `stormFee` => allData: `[stormFee, 0, 0, 0]`
- `stormFrequency` => allData: `[stormFrequencyBlocks, 0, 0, 0]`
- `kingProtection` => allData: `[kingProtectionBlocks, 0, 0, 0]`
- `pointAllocation` => allData: `[indexOfNewPointAllocationTemplate, 0, 0, 0]`
- `courtRoleOdds` => allData: `[1000, 2000, 3000, 4000]`
- `attackKing` => allData: `[0, 0, 0, 0]`
- `anyString` => allData `[0, 0, 0, 0]` // Will act as a pass thru, depositing to treasury but not changing any state

#### redeem

- `redeem()`
- Used by players to collect portion of treasury based on pointsBalance.

### Court Roles
#### Roles Numbered by Index (_Italics_ are stormable)
0. None
1. _King_
2. _Lord_ (x2)
3. _Knight_ (x3)
4. _Townsfolk_ (x4)
5. Custom1
6. Custom2
7. Custom3

#### Court State View Methods

- `fullCourt() returns (address[13])`
- `king() returns (address[1])`
- `lords() returns (address[2])`
- `knights() returns (address[3])`
- `townsfolk() returns (address[4])`
- `custom1() returns (address[1])`
- `custom2() returns (address[1])`
- `custom3() returns (address[1])`
- `court(uint256 courtIndex) returns (address)`

#### Court Query View Methods

- `determineCourtRole(address accountAddress, uint256 _randomSeed) returns (CourtRole)`
- `getCourtRoleFromCourtIndex(uint256 index) returns (CourtRole)`
- `getCourtRoleIndexes(CourtRole courtRole) returns (uint256 start, uint256 end)`
- `indexOfAddressInRole(CourtRole courtRole, address accountAddress) returns (uint256)`
- `getIndexOfAddressInCourt(address accountAddress) returns (int256)`
- `findCourtRole(address accountAddress, CourtRole desiredCourtRole) returns (uint256)`

### Points

#### Point Allocation Templates Numbered by Index (10_000 bps: eg. 3100 = 31%)

0. Custom => `[3100, 1400 (x2), 600 (x3), 350 (x4), 300, 300, 300]`
1. Greedy => `[4900, 1300 (x2), 500 (x3), 250 (x4), 0, 0, 0]`
2. Military => `[3100, 1400 (x2), 900 (x3), 350 (x4), 0, 0, 0]`
3. Peoples => `[2400, 1500 (x2), 800 (x3), 550 (x4), 0, 0, 0]`
4. Dead => `[0, 1400 (x2), 1900 (x3), 375 (x4), 0, 0, 0]`


#### Point Query Methods

- `pointsBalance(address) returns (uint256)` // Points since last court refresh
- `getPoints(address accountAddress) returns (uint256)` // Realtime points
- `getCourtMemberPoints() returns (uint256[13] memory)` // Realtime points for entire court
- `calculatePointsEarned(CourtRole courtRole, uint256 startBlock) returns (uint256)`
- `convertPointsToAssets(uint256 points) returns (uint256)`
- `getPointsPerBlock(CourtRole courtRole) returns (uint256)`
- `totalPoints() returns (uint256)`
- `activePointAllocationTemplate() returns (PointAllocationTemplate)`
- `pointAllocationTemplates(PointAllocationTemplate) returns (uint256[7])`
- `getCourtRolePointAllocation(CourtRole courtRole, PointAllocationTemplate pointAllocationTemplate) returns (uint256)`
- `getActiveCourtRolePointAllocation(CourtRole courtRole) returns (uint256)`

### Events

#### StormTheCastle
```solidity
    event StormTheCastle(
        address indexed accountAddress,
        uint8 indexed courtRole,
        address indexed outAddress,
        uint256 fid
    );
```
#### Game State Action
```solidity
    event GameStateAction(
        address indexed accountAddress,
        uint256 indexed fid,
        string actionType
    );
```
#### Court Role Action
```solidity
    event CourtRoleAction(
        address indexed accountAddress,
        address indexed inAddress,
        address indexed outAddress,
        uint256 fid
    );
```

### Add to Treasury

- Send ETH to the contract and it will convert and deposit to treasury (10% protocol fee taken)
- Send DEGEN ERC20 token (0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed) directly to treasury with: `depositDegenToGameAssets(uint256 degenAmountWei)` method. Make sure you `approve` the `degenAmountWei` of degens tokens to the kingOfTheDegens contract address first. (No protocol fee is taken)

### OnlyOwner Methods

#### Protocol Fees
- `collectProtocolFees()`
- `protocolRedeem()`

#### Game State
- `setStormFrequency(uint256 blocks)`
- `setStormFee(uint256 _stormFee)`
- `setKingProtectionBlocks(uint256 _kingProtectionBlocks)`
- `setCourtRoleOdds(uint256[4] memory _courtRoleOdds)`
- `setActivePointAllocationTemplate(PointAllocationTemplate _pointAllocationTemplate)`

#### Court Members
- `swapCourtMember(address accountAddress, uint256 courtIndex)`
- `rotateInCourtMember(address accountAddress, CourtRole courtRole)`

#### Game Settings
- `setProtocolFeePercent(uint256 _protocolFeePercent)` // 10_000 bps eg. 1000 = 10%
- `setPointAllocationTemplates(uint256[7][5] _pointAllocationTemplates)`
- `setIsTrusted(address trustedAddress, bool isTrusted)`
- `togglePause()`

#### Risky Game State - Avoid These - Only Use to Sync with Offchain State
- `setGameDurationBlocks(uint256 blocks)`
- `setGameAssets(uint256 _gameAssets)`
- `setTotalPointsPerBlock(uint256 _totalPointsPerBlock)`
- `setPointsBalance(address accountAddress, uint256 points)`
- `setRoleStartBlock(address accountAddress, uint256 blockNumber)`
- `setStormBlock(address accountAddress, uint256 blockNumber)`