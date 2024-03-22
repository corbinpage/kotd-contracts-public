// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ISuperfluid, ISuperToken} from "superfluid-contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperTokenV1Library} from "superfluid-contracts/apps/SuperTokenV1Library.sol";
import {ISuperTokenFactory} from "superfluid-contracts/interfaces/superfluid/ISuperTokenFactory.sol";
import {SuperTokenV1Library} from "superfluid-contracts/apps/SuperTokenV1Library.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Vault is ERC4626, Owned {
    using SuperTokenV1Library for ISuperToken;
    ISuperToken public immutable superToken;
    uint256 public immutable minStormPrice;
    mapping(address => uint256) public stormBlock;
    mapping(address => bool) public storming;
    mapping(address => CourtRole) public courtRoles;
    mapping(CourtRole => int96) public flowRates;
    uint256 public storms;
    // Court
    address public king;
    address[2] public lords;
    address[3] public knights;
    address[4] public townsfolk;
    // Role
    enum CourtRole {
        None,
        Townsfolk,
        Knight,
        Lord,
        King
    }
    // Events
    event StormTheCastle(address indexed stormAddress, uint256 indexed amountSent);
    // Custom Errors
    error BadAddress(address badAddress);
    error GameEnded();
    error InsufficientFunds(uint256 valueSent);
    error TooFrequentStorms(uint256 nextBlockAllowed, uint256 currentBlockNumber, bool currentlyStorming);
    error AlreadyCourtMember(address accountAddress, CourtRole courtRole);
    error BadCourtRole(CourtRole courtRole);
    error TooMuchFlow(uint256 kingFlowrate);
    error SwitchFlowRateError(address oldAddress, address newAddress, int96 flowRate);

    constructor(address _asset, address _superTokenFactoryAddress, uint256 _gameDurationDays, uint256 _totalMint, uint256 _minStormPrice) Owned(msg.sender) ERC4626(ERC20(_asset), 'Vault Token', 'VAULT') {
        minStormPrice = _minStormPrice;
        _mint(address(this), _totalMint);
        superToken = ISuperTokenFactory(_superTokenFactoryAddress).createERC20Wrapper(IERC20Metadata(address(this)), asset.decimals(), ISuperTokenFactory.Upgradability.FULL_UPGRADABLE, 'Super Vault Token', 'VAULTx');
        // Flow rates
        uint256 _totalFlowRate = _totalMint / (_gameDurationDays * 24 * 60 * 60);
        uint256 _kingRate = calculatePercentage(_totalFlowRate, 3333);
        if (_kingRate > uint256(uint96(type(int96).max))) revert TooMuchFlow(_kingRate);
        flowRates[CourtRole.King] = int96(uint96(_kingRate));

    }

    function initGame() public onlyOwner {
        this.approve(address(superToken), this.totalSupply());
        superToken.upgrade(this.totalSupply());
    }

    function stormTheCastle() public payable {
        if (msg.sender == address(0)) revert BadAddress(msg.sender);
        if (totalSupply <= 0) revert GameEnded();
        if (msg.value < minStormPrice) revert InsufficientFunds(msg.value);
        if (storming[msg.sender] || stormBlock[msg.sender] + 1800 >= block.number) revert TooFrequentStorms(stormBlock[msg.sender] + 1800, block.number, storming[msg.sender]);
        if (courtRoles[msg.sender] != CourtRole.None) revert AlreadyCourtMember(msg.sender, courtRoles[msg.sender]);
        storming[msg.sender] = true;
        storms++;
        // Deposit to wETH
        SafeTransferLib.safeTransferETH(address(asset), msg.value - 1e14);
        emit StormTheCastle(msg.sender, msg.value);
    }

    function confirmTheStorm(address accountAddress, CourtRole courtRole) public onlyOwner {
        if (courtRole == CourtRole.None) revert BadCourtRole(courtRole);
        if (courtRoles[accountAddress] != CourtRole.None) revert AlreadyCourtMember(accountAddress, courtRole);
        // Switch flows
        if (courtRole == CourtRole.King) {
            switchFlows(king, accountAddress, flowRates[courtRole]);
            king = accountAddress;
        }
        storming[accountAddress] = false;
    }

    function switchFlows(address oldFlow, address newFlow, int96 flowRate) private {
        bool deleteResult = superToken.deleteFlow(address(this), oldFlow);
        bool createResult = superToken.createFlow(newFlow, flowRate);
        if (!(deleteResult && createResult)) revert SwitchFlowRateError(oldFlow, newFlow, flowRate);
    }

    function calculatePercentage(uint256 amount, uint256 bps) private pure returns (uint256) {
        if ((amount * bps) < 10_000) revert();
        return amount * bps / 10_000;
    }

    function totalAssets() public view virtual override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    receive() external payable {}
}
