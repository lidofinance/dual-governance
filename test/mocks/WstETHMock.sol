// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";

/* solhint-disable no-unused-vars,custom-errors */
contract WstETHMock is ERC20Mock, IWstETH {
    function wrap(uint256 stETHAmount) external returns (uint256) {
        revert("Not Implemented");
    }

    function unwrap(uint256 wstETHAmount) external returns (uint256) {
        revert("Not Implemented");
    }

    function getStETHByWstETH(uint256 wstethAmount) external view returns (uint256) {
        revert("Not Implemented");
    }
}
