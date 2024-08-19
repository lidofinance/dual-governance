// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";

contract StETHMock is ERC20Mock, IStETH {
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256) {
        revert("Not Implemented");
    }

    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256) {
        revert("Not Implemented");
    }

    function transferShares(address to, uint256 amount) external {
        revert("Not Implemented");
    }

    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        revert("Not Implemented");
    }
}
