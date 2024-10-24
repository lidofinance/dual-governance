// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {PercentD16, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";

/* solhint-disable no-unused-vars,custom-errors */
contract StETHMock is ERC20, IStETH {
    uint256 public totalPooledEther;

    constructor() ERC20("StETHMock", "MStETH") {
        /// @dev the total supply of the stETH always > 0
        _mint(address(this), 100 wei);
        totalPooledEther = 100 wei;
    }

    function rebaseTotalPooledEther(PercentD16 rebaseFactor) public {
        totalPooledEther = PercentD16.unwrap(rebaseFactor) * totalPooledEther / HUNDRED_PERCENT_D16;
    }

    function setTotalPooledEther(uint256 ethAmount) public {
        totalPooledEther = ethAmount;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
        totalPooledEther = totalPooledEther + amount;
    }

    function burn(address account, uint256 ethAmount) external {
        uint256 sharesToBurn = this.getSharesByPooledEth(ethAmount);
        _burn(account, sharesToBurn);
        totalPooledEther = totalPooledEther - ethAmount;
    }

    function totalSupply() public view override(IERC20, ERC20) returns (uint256) {
        return totalPooledEther;
    }

    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256) {
        return (ethAmount * super.totalSupply()) / totalPooledEther;
    }

    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256) {
        return (sharesAmount * totalPooledEther) / super.totalSupply();
    }

    function balanceOf(address _account) public view override(IERC20, ERC20) returns (uint256) {
        return this.getPooledEthByShares(super.balanceOf(_account));
    }

    function transfer(address _recipient, uint256 _amount) public override(IERC20, ERC20) returns (bool) {
        uint256 _sharesToTransfer = this.getSharesByPooledEth(_amount);
        super.transfer(_recipient, _sharesToTransfer);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) public override(IERC20, ERC20) returns (bool) {
        uint256 _sharesToTransfer = this.getSharesByPooledEth(_amount);
        _spendAllowance(_sender, msg.sender, _amount);
        super._transfer(_sender, _recipient, _sharesToTransfer);
        return true;
    }

    function transferShares(address to, uint256 sharesAmount) external {
        super.transfer(to, sharesAmount);
    }

    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        uint256 tokensAmount = this.getPooledEthByShares(_sharesAmount);
        _spendAllowance(_sender, msg.sender, tokensAmount);
        super._transfer(_sender, _recipient, _sharesAmount);
        return _sharesAmount;
    }
}
