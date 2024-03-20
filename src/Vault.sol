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
    // Events
    event StormTheCastle(address indexed stormAddress, uint256 indexed amountSent);
    // Custom Errors
    error BadAddress(address badAddress);
    error GameEnded();
    error InsufficientFunds(uint256 valueSent);
    error TooFrequentStorms(uint256 nextBlockAllowed, uint256 currentBlockNumber);
    error TooMuchFlow(uint256 totalFlowRate);

    constructor(address _asset, address _superTokenFactoryAddress, uint256 _gameDurationDays, uint256 _totalMint, uint256 _minStormPrice) Owned(msg.sender) ERC4626(ERC20(_asset), 'Vault Token', 'VAULT') {
        minStormPrice = _minStormPrice;
        _mint(address(this), _totalMint);
        superToken = ISuperTokenFactory(_superTokenFactoryAddress).createERC20Wrapper(IERC20Metadata(address(this)), asset.decimals(), ISuperTokenFactory.Upgradability.FULL_UPGRADABLE, 'Super Vault Token', 'VAULTx');
    }

    function initGame(address _king, address[2] memory _lords, address[3] memory _knights, address[4] memory _townsfolk) public onlyOwner {
        this.approve(address(superToken), this.totalSupply());
        superToken.upgrade(this.totalSupply());
    }

    function stormTheCastle() public payable {
        if (msg.sender == address(0)) revert BadAddress(msg.sender);
        if (totalSupply <= 0) revert GameEnded();
        if (msg.value < minStormPrice) revert InsufficientFunds(msg.value);
        if (stormBlock[msg.sender] + 1800 >= block.number) revert TooFrequentStorms(stormBlock[msg.sender] + 1800, block.number);
        // Deposit to wETH
        SafeTransferLib.safeTransferETH(address(asset), msg.value - 1e14);
        emit StormTheCastle(msg.sender, msg.value);
    }

    function totalAssets() public view virtual override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    receive() external payable {}
}
