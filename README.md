## King of the Castle Game

### Court Roles
```solidity
enum CourtRole {
        None,
        King,
        Lord,
        Knight,
        Townsfolk
    }
```
Returns as a uint8, so King = 1, Townsfolk = 4, etc.

Use: 
```solidity
function determineCourtRole(address accountAddress, uint256 _randomSeed) public pure returns (CourtRole)`
```
to get the CourtRole making sure the `accountAddress` is the address that will be submitting the transaction.
* `_randomSeed` should be generated in the frame once and same number should be passed to both `determineCourtRole()` & `stormTheCastle()`
### Storm
To play the game: `stormTheCastle(uint256 _randomSeed, uint256 _fid)` - Costs ~825k gas

Total number of players can be pulled from blockchain by calling `storms()` which `returns (uint256)`

### Event
```solidity
event StormTheCastle(address indexed accountAddress, uint8 indexed courtRole, uint256 indexed amountSent, uint256 fid);
```
is emitted on successful storm.

Hash: `0xd1611e3a49d370878089b825553ec2e240770ea33b54c67ebbf637fc567be8df`
