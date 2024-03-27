// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ISuperfluid, ISuperToken} from "superfluid-contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperTokenFactory} from "superfluid-contracts/interfaces/superfluid/ISuperTokenFactory.sol";
import {SuperTokenV1Library} from "superfluid-contracts/apps/SuperTokenV1Library.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Dice} from "./lib/Dice.sol";

contract KingOfTheCastle is ERC4626, Owned {
    using SuperTokenV1Library for ISuperToken;
    ISuperToken public immutable superToken;
    uint256 public immutable minPlayAmount;
    uint256 public immutable protocolFee;
    uint256 public immutable totalFlowRate;
    mapping(CourtRole => uint256) public courtBps;
    mapping(address => uint256) public stormBlock;
    mapping(address => CourtRole) public courtRoles;
    uint256 public storms;
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
    // Events
    event StormTheCastle(address indexed accountAddress, uint8 indexed courtRole, uint256 indexed amountSent, uint256 fid);
    // Custom Errors
    error BadAddress(address badAddress);
    error GameEnded();
    error InsufficientFunds(uint256 valueSent);
    error TooFrequentStorms(uint256 nextBlockAllowed, uint256 currentBlockNumber);
    error AlreadyCourtMember(address accountAddress, CourtRole courtRole);
    error BadCourtRole(CourtRole courtRole);
    error TooMuchFlow(uint256 totalFlowrate);
    error SwitchFlowRateError(address oldAddress, address newAddress, int96 flowRate);

    constructor(
        address _asset,
        address _superTokenFactoryAddress,
        uint256 _gameDurationDays,
        uint256 _totalSupply,
        uint256 _minPlayAmount,
        uint256 _protocolFee,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256[4] memory _courtBps
    ) Owned(msg.sender) ERC4626(ERC20(_asset), _tokenName, _tokenSymbol) {
        minPlayAmount = _minPlayAmount;
        protocolFee = _protocolFee;
        _mint(address(this), _totalSupply);
        superToken = ISuperTokenFactory(_superTokenFactoryAddress).createERC20Wrapper(
            IERC20Metadata(address(this)),
            asset.decimals(),
            ISuperTokenFactory.Upgradability.FULL_UPGRADABLE,
            string.concat('Super ', _tokenName),
            string.concat(_tokenSymbol, 'x')
        );
        // Flow rates
        totalFlowRate = _totalSupply / (_gameDurationDays * 24 * 60 * 60);
        if (totalFlowRate > uint256(uint96(type(int96).max))) revert TooMuchFlow(totalFlowRate);
        // Court Bps
        for (uint256 i = 0;i < 4;i++) {
            courtBps[CourtRole(i + 1)] = _courtBps[i];
        }
    }

    function initGame(
        address[1] calldata _king,
        address[2] calldata _lords,
        address[3] calldata _knights,
        address[4] calldata _townsfolk
    ) public onlyOwner {
        this.approve(address(superToken), this.totalSupply());
        superToken.upgrade(this.totalSupply());
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
    }

    function stormTheCastle(uint256 _randomSeed, uint256 _fid) public payable {
        if (msg.sender == address(0)) revert BadAddress(msg.sender);
        if (superToken.totalSupply() <= 0) revert GameEnded();
        if (msg.value < minPlayAmount) revert InsufficientFunds(msg.value);
        if (stormBlock[msg.sender] + 1800 >= block.number) revert TooFrequentStorms(stormBlock[msg.sender] + 1800, block.number);
        if (courtRoles[msg.sender] != CourtRole.None) revert AlreadyCourtMember(msg.sender, courtRoles[msg.sender]);
        storms++;
        stormBlock[msg.sender] = block.number;
        // Determine courtRole
        CourtRole courtRole = determineCourtRole(msg.sender, _randomSeed);
        confirmTheStorm(msg.sender, courtRole);
        // Deposit to wETH
        SafeTransferLib.safeTransferETH(address(asset), msg.value - 1e14);
        emit StormTheCastle(msg.sender, uint8(courtRole), msg.value, _fid);
    }

    function determineCourtRole(address accountAddress, uint256 _randomSeed) public pure returns (CourtRole) {
        uint256 random = Dice.rollDiceSet(1, 100, uint256(keccak256(abi.encodePacked(accountAddress, _randomSeed))));
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

    function confirmTheStorm(address accountAddress, CourtRole courtRole) private {
        // Switch flows
        if (courtRole == CourtRole.King) {
            switchFlows(king[0], accountAddress, getCourtRoleFlowRate(CourtRole.King));
            king[0] = accountAddress;
        } else if (courtRole == CourtRole.Lord) {
            switchFlows(lords[0], accountAddress,getCourtRoleFlowRate(CourtRole.Lord));
            lords[0] = lords[1];
            lords[1] = accountAddress;
        } else if (courtRole == CourtRole.Knight) {
            switchFlows(knights[0], accountAddress, getCourtRoleFlowRate(CourtRole.Knight));
            knights[0] = knights[1];
            knights[1] = knights[2];
            knights[2] = accountAddress;
        } else {
            switchFlows(townsfolk[0], accountAddress, getCourtRoleFlowRate(CourtRole.Townsfolk));
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

    function totalAssets() public view virtual override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function readFlowRate(address accountAddress) public view returns (int96) {
        return superToken.getFlowRate(address(this), accountAddress);
    }

    function getCourtRoleFlowRate(CourtRole courtRole) public view returns (int96) {
        uint256 bps = courtBps[courtRole];
        uint256 _totalFlowRate = totalFlowRate;
        if ((_totalFlowRate * bps) < 10_000) revert();
        return int96(uint96(_totalFlowRate * bps / 10_000));
    }

    receive() external payable {}
}
