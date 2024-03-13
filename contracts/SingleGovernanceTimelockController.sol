// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITimelockController} from "./interfaces/ITimelock.sol";

contract SingleGovernanceTimelockController is ITimelockController {
    error NotDao();
    error NotTimelock(address account);
    error ConfigAlreadySet();

    address public immutable GOVERNANCE;

    constructor(address governance) {
        GOVERNANCE = governance;
    }

    // only dao can
    function onSubmitProposal(address sender, address /* executor */ ) external view {
        _checkGovernance(sender);
    }

    // anyone can schedule the proposal
    function onExecuteProposal(address, /* sender */ uint256 /* proposalId */ ) external view {}

    // only governance can cancel proposals
    function onCancelAllProposals(address sender) external view {
        _checkGovernance(sender);
    }

    function isProposalsSubmissionAllowed() external pure returns (bool) {
        return true;
    }

    function isProposalExecutionAllowed(uint256 /* proposalId */ ) external pure returns (bool) {
        return true;
    }

    // ---
    // Internal Helper Methods
    // ---

    function _checkGovernance(address account) internal view {
        if (account != GOVERNANCE) {
            revert NotDao();
        }
    }
}
