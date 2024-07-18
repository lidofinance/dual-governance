// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGovernance, ITimelock} from "./interfaces/ITimelock.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";
import {ExecutorCall} from "./libraries/Proposals.sol";

contract TimelockedGovernance is IGovernance, ConfigurationProvider {
    error NotGovernance(address account);

    address public immutable GOVERNANCE;
    ITimelock public immutable TIMELOCK;

    constructor(address config, address governance, address timelock) ConfigurationProvider(config) {
        GOVERNANCE = governance;
        TIMELOCK = ITimelock(timelock);
    }

    function submitProposal(ExecutorCall[] calldata calls) external returns (uint256 proposalId) {
        _checkGovernance(msg.sender);
        return TIMELOCK.submit(CONFIG.ADMIN_EXECUTOR(), calls);
    }

    function scheduleProposal(uint256 proposalId) external {
        TIMELOCK.schedule(proposalId);
    }

    function executeProposal(uint256 proposalId) external {
        TIMELOCK.execute(proposalId);
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        return TIMELOCK.canSchedule(proposalId);
    }

    function cancelAllPendingProposals() external {
        _checkGovernance(msg.sender);
        TIMELOCK.cancelAllNonExecutedProposals();
    }

    function _checkGovernance(address account) internal view {
        if (account != GOVERNANCE) {
            revert NotGovernance(account);
        }
    }
}
