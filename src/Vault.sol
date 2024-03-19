// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "solmate/tokens/ERC4626.sol";
import "solmate/auth/Owned.sol";

contract Vault is ERC4626, Owned {

    constructor(address _asset, address _owner) Owned(_owner) ERC4626(ERC20(_asset), 'Vault Token', 'VAULT') {
        _mint(address(this), 1000000000);
    }

    function claimStakingRewards() public onlyOwner {
        // Do owner things
    }

    function totalAssets() public view virtual override returns (uint256) {
        return asset.balanceOf(address(this));
    }

}
