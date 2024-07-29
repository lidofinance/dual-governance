// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGovernance, ITimelock} from "./interfaces/ITimelock.sol";

import {ExternalCall} from "./libraries/ExternalCalls.sol";

contract SingleGovernance is IGovernance {
    error NotGovernance(address account);

    address public immutable GOVERNANCE;
    ITimelock public immutable TIMELOCK;

    constructor(address governance, address timelock) {
        GOVERNANCE = governance;
        TIMELOCK = ITimelock(timelock);
    }

    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId) {
        _checkGovernance(msg.sender);
        return TIMELOCK.submit(TIMELOCK.getAdminExecutor(), calls);
    }

    function scheduleProposal(uint256 proposalId) external {
        TIMELOCK.schedule(proposalId);
    }

    function executeProposal(uint256 proposalId) external {
        TIMELOCK.execute(proposalId);
    }

    function canScheduleProposal(uint256 proposalId) external view returns (bool) {
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
