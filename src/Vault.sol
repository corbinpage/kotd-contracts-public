// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/tokens/ERC4626.sol";
import "solmate/auth/Owned.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import {ISuperfluid, ISuperToken} from "superfluid-contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperTokenFactory} from "superfluid-contracts/interfaces/superfluid/ISuperTokenFactory.sol";
import {SuperTokenV1Library} from "superfluid-contracts/apps/SuperTokenV1Library.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Vault is ERC4626, Owned {
    ISuperToken public superToken;
    mapping(address => uint256) public stormBlock;
    mapping(address => bool) public storming;
    mapping(address => Court) public court;

    enum Court {
        None,
        Townsfolk,
        Knight,
        Lord,
        King
    }
    event StormTheCastle(address indexed stromAddress);

    constructor(address _asset, address _superTokenFactoryAddress) Owned(msg.sender) ERC4626(ERC20(_asset), 'Vault Token', 'VAULT') {
        _mint(address(this), 1e11);
        ISuperTokenFactory superTokenFactory = ISuperTokenFactory(_superTokenFactoryAddress);
        superToken = superTokenFactory.createERC20Wrapper(IERC20Metadata(address(this)), asset.decimals(), ISuperTokenFactory.Upgradability.FULL_UPGRADABLE, 'Super Vault Token', 'VAULTx');
    }

    function stormTheCastle() public payable {
        require(msg.value == 1e15, 'Must send .001 ETH to storm the castle');
        require(storming[msg.sender] || stormBlock[msg.sender] + 1800 >= block.number, 'Can only storm the castle once an hour');
        require(court[msg.sender] == Court.None, 'You are already a member of the court');
        // Deposit to wETH
        uint256 depositAmount = 9e14;
        storming[msg.sender] = true;
        SafeTransferLib.safeTransferETH(address(asset), depositAmount);
        emit StormTheCastle(msg.sender);
    }

    function confirmTheStorm() public onlyOwner {
        // Delete the removed user stream
        // Add new user stream
        // Remove new user from storming mapping
    }

    function totalAssets() public view virtual override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    receive() external payable {}
}
