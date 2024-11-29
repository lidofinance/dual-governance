// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";

/* solhint-disable no-unused-vars,custom-errors */
contract StETHMock is ERC20Mock, IStETH {
    uint256 public __shareRate = 1 gwei;

    constructor() {
        /// @dev the total supply of the stETH always > 0
        _mint(address(this), 100 wei);
    }

    function __setShareRate(uint256 newShareRate) public {
        __shareRate = newShareRate;
    }

    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256) {
        return ethAmount / __shareRate;
    }

    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256) {
        return __shareRate * sharesAmount;
    }

    function transferShares(address to, uint256 sharesAmount) external returns (uint256 tokensAmount) {
        tokensAmount = sharesAmount * __shareRate;
        transfer(to, sharesAmount * __shareRate);
    }

    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256 tokensAmount) {
        tokensAmount = _sharesAmount * __shareRate;
        transferFrom(_sender, _recipient, tokensAmount);
    }
}
