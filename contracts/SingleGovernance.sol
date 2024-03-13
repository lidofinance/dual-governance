// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IGovernance} from "./interfaces/ITimelock.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";
import {ExecutorCall} from "./libraries/Proposals.sol";

interface ITimelock {
    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId);
    function execute(uint256 proposalId) external;
    function cancelAll() external;

    function canExecute(uint256 proposalId) external view returns (bool);
}

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

    function execute(uint256 proposalId) external {
        TIMELOCK.execute(proposalId);
    }

    function canExecute(uint256 proposalId) external view returns (bool) {
        return TIMELOCK.canExecute(proposalId);
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
