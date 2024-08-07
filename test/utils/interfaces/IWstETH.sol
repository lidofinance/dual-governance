// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IWstETH as IWstETHBase} from "contracts/interfaces/IWstETH.sol";

interface IWstETH is IWstETHBase {
/// @dev event though in the tests there is no need in additional methods of the WstETH token,
/// it's kept for consistency
}
