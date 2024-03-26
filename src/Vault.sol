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
import {Dice} from "./lib/Dice.sol";

contract Vault is ERC4626, Owned {
    using SuperTokenV1Library for ISuperToken;
    ISuperToken public immutable superToken;
    uint256 public immutable minStormPrice;
    mapping(address => uint256) public stormBlock;
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
        King,
        Lord,
        Knight,
        Townsfolk
    }
    // Events
    event StormTheCastle(address indexed accountAddress, uint8 indexed courtRole, uint256 indexed amountSent);
    // Custom Errors
    error BadAddress(address badAddress);
    error GameEnded();
    error InsufficientFunds(uint256 valueSent);
    error TooFrequentStorms(uint256 nextBlockAllowed, uint256 currentBlockNumber);
    error AlreadyCourtMember(address accountAddress, CourtRole courtRole);
    error BadCourtRole(CourtRole courtRole);
    error TooMuchFlow(uint256 kingFlowrate);
    error SwitchFlowRateError(address oldAddress, address newAddress, int96 flowRate);

    constructor(address _asset, address _superTokenFactoryAddress, uint256 _gameDurationDays, uint256 _totalMint, uint256 _minStormPrice) Owned(msg.sender) ERC4626(ERC20(_asset), 'King Token', 'KING') {
        minStormPrice = _minStormPrice;
        _mint(address(this), _totalMint);
        superToken = ISuperTokenFactory(_superTokenFactoryAddress).createERC20Wrapper(IERC20Metadata(address(this)), asset.decimals(), ISuperTokenFactory.Upgradability.FULL_UPGRADABLE, 'Super King Token', 'KINGx');
        // Flow rates
        uint256 _totalFlowRate = _totalMint / (_gameDurationDays * 24 * 60 * 60);
        uint256 _kingRate = calculatePercentage(_totalFlowRate, 3300);
        if (_kingRate > uint256(uint96(type(int96).max))) revert TooMuchFlow(_kingRate);
        flowRates[CourtRole.King] = int96(uint96(_kingRate));
        flowRates[CourtRole.Lord] = int96(uint96(calculatePercentage(_totalFlowRate, 1400)));
        flowRates[CourtRole.Knight] = int96(uint96(calculatePercentage(_totalFlowRate, 700)));
        flowRates[CourtRole.Townsfolk] = int96(uint96(calculatePercentage(_totalFlowRate, 450)));
    }

    function initGame() public onlyOwner {
        this.approve(address(superToken), this.totalSupply());
        superToken.upgrade(this.totalSupply());
    }

    function stormTheCastle() public payable {
        if (msg.sender == address(0)) revert BadAddress(msg.sender);
        if (superToken.totalSupply() <= 0) revert GameEnded();
        if (msg.value < minStormPrice) revert InsufficientFunds(msg.value);
        if (stormBlock[msg.sender] + 1800 >= block.number) revert TooFrequentStorms(stormBlock[msg.sender] + 1800, block.number);
        if (courtRoles[msg.sender] != CourtRole.None) revert AlreadyCourtMember(msg.sender, courtRoles[msg.sender]);
        storms++;
        stormBlock[msg.sender] = block.number;
        // Determine courtRole
        //CourtRole courtRole = rollForRole();
        CourtRole courtRole = CourtRole.Townsfolk;
        confirmTheStorm(msg.sender, courtRole);
        // Deposit to wETH
        SafeTransferLib.safeTransferETH(address(asset), msg.value - 1e14);
        emit StormTheCastle(msg.sender, uint8(courtRole), msg.value);
    }

    function rollForRole() private view returns (CourtRole) {
        uint256 random = Dice.rollDiceSet(1, 100, randomSeed());
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

    function randomSeed() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            tx.origin,
            blockhash(block.number - 1),
            block.timestamp
        )));
    }

    function confirmTheStorm(address accountAddress, CourtRole courtRole) private {
        // Switch flows
        if (courtRole == CourtRole.King) {
            switchFlows(king, accountAddress, flowRates[CourtRole.King]);
            king = accountAddress;
        } else if (courtRole == CourtRole.Lord) {
            switchFlows(lords[0], accountAddress, flowRates[CourtRole.Lord]);
            lords[0] = lords[1];
            lords[1] = accountAddress;
        } else if (courtRole == CourtRole.Knight) {
            switchFlows(knights[0], accountAddress, flowRates[CourtRole.Knight]);
            knights[0] = knights[1];
            knights[1] = knights[2];
            knights[2] = accountAddress;
        } else {
            switchFlows(townsfolk[0], accountAddress, flowRates[CourtRole.Townsfolk]);
            townsfolk[0] = townsfolk[1];
            townsfolk[1] = townsfolk[2];
            townsfolk[2] = townsfolk[3];
            townsfolk[3] = accountAddress;
        }
        courtRoles[accountAddress] = courtRole;
    }

    function switchFlows(address oldFlow, address newFlow, int96 flowRate) private {
        bool deleteResult = true;
        if (readFlowRate(oldFlow) > 0) {
            deleteResult = superToken.deleteFlow(address(this), oldFlow);
        }
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

    function readFlowRate(address accountAddress) public view returns (int96) {
        return superToken.getFlowRate(address(this), accountAddress);
    }

    receive() external payable {}
}
