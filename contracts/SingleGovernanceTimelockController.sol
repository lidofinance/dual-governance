// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IConfiguration} from "./interfaces/IConfiguration.sol";
import {ITimelockController} from "./interfaces/ITimelock.sol";

contract SingleGovernanceTimelockController is ITimelockController {
    error NotDao();
    error NotTimelock(address account);
    error ConfigAlreadySet();

    IConfiguration internal _config;
    address public immutable DAO;

    constructor(address dao) {
        DAO = dao;
    }

    function handleProposalCreation(address sender) external view returns (address executor) {
        _checkDao(sender);
        executor = _config.ADMIN_EXECUTOR();
    }

    function handleProposalAdoption(address) external view {
        // anyone can schedule the proposal
    }

    function handleProposalsRevocation(address sender) external view {
        _checkDao(sender);
    }

    function isProposalsAdoptionAllowed() external pure returns (bool) {
        return true;
    }

    // TODO: make config immutable and set on the deployment phase
    function setConfig(address config) external {
        if (address(_config) != address(0)) {
            revert ConfigAlreadySet();
        }
        _config = IConfiguration(config);
    }

    // ---
    // Internal Helper Methods
    // ---

    function _checkDao(address account) internal view {
        if (account != address(DAO)) {
            revert NotDao();
        }
    }
}
