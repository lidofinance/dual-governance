// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DualGovernanceConfig} from "../libraries/DualGovernanceConfig.sol";

interface IDualGovernanceConfigProvider {
    function getDualGovernanceConfig() external view returns (DualGovernanceConfig.Context memory config);
}
