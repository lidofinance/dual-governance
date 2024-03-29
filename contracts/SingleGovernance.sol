// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IGovernance, ITimelock} from "./interfaces/ITimelock.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";
import {ExecutorCall} from "./libraries/Proposals.sol";

contract SingleGovernance is IGovernance, ConfigurationProvider {
    error NotGovernance(address account);

    address public immutable GOVERNANCE;
    ITimelock public immutable TIMELOCK;

    constructor(address config, address governance, address timelock) ConfigurationProvider(config) {
        GOVERNANCE = governance;
        TIMELOCK = ITimelock(timelock);
    }

    function submit(ExecutorCall[] calldata calls) external returns (uint256 proposalId) {
        _checkGovernance(msg.sender);
        return TIMELOCK.submit(CONFIG.ADMIN_EXECUTOR(), calls);
    }

    function schedule(uint256 proposalId) external {
        TIMELOCK.schedule(proposalId);
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        return TIMELOCK.canSchedule(proposalId);
    }

    function cancelAll() external {
        _checkGovernance(msg.sender);
        TIMELOCK.cancelAll();
    }

    function _checkGovernance(address account) internal view {
        if (account != GOVERNANCE) {
            revert NotGovernance(account);
        }
    }
}
