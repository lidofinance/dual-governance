// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IConfiguration} from "./interfaces/IConfiguration.sol";
import {ITimelockController} from "./interfaces/ITimelock.sol";

contract SingleGovernanceTimelockController is ITimelockController {
    error NotDao();
    error NotTimelock(address account);
    error ConfigAlreadySet();

    address public immutable EXECUTOR;
    address public immutable GOVERNANCE;

    constructor(address governance, address executor) {
        EXECUTOR = executor;
        GOVERNANCE = governance;
    }

    // only dao can
    function handleProposalCreation(address sender) external view returns (address executor) {
        _checkGovernance(sender);
        return EXECUTOR;
    }

    // anyone can schedule the proposal
    function handleProposalAdoption(address) external view {}

    // only governance can cancel proposals
    function handleProposalsRevocation(address sender) external view {
        _checkGovernance(sender);
    }

    function isProposalsAdoptionAllowed() external pure returns (bool) {
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
