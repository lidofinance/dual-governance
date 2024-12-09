// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";

/* solhint-disable custom-errors, reason-string */
contract WstETHMock is ERC20, IWstETH {
    IStETH public stETH;

    constructor(IStETH _stETH) ERC20("WstETHMock", "MWst") {
        stETH = _stETH;
    }

    function wrap(uint256 stETHAmount) external returns (uint256) {
        require(stETHAmount > 0, "wstETH: can't wrap zero stETH");
        uint256 wstETHAmount = stETH.getSharesByPooledEth(stETHAmount);
        _mint(msg.sender, wstETHAmount);
        stETH.transferFrom(msg.sender, address(this), stETHAmount);
        return wstETHAmount;
    }

    function unwrap(uint256 wstETHAmount) external returns (uint256) {
        require(wstETHAmount > 0, "wstETH: zero amount unwrap not allowed");
        uint256 stETHAmount = stETH.getPooledEthByShares(wstETHAmount);
        _burn(msg.sender, wstETHAmount);
        stETH.transfer(msg.sender, stETHAmount);
        return stETHAmount;
    }

    function getStETHByWstETH(uint256 wstethAmount) external view returns (uint256) {
        return stETH.getPooledEthByShares(wstethAmount);
    }
}
