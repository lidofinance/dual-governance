// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITimelock} from "./interfaces/ITimelock.sol";

import {ExecutorCall} from "./libraries/ScheduledCalls.sol";
import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {Proposals, Proposal} from "./libraries/Proposals.sol";

import {Configuration} from "./Configuration.sol";
import {GovernanceState} from "./GovernanceState.sol";

interface IProxyAdmin {
    function upgradeAndCall(address proxy, address impl, bytes memory data) external;
}

contract DualGovernance {
    using Proposers for Proposers.State;
    using Proposals for Proposals.State;

    event ConfigSet(address config);

    error ProposalSubmissionNotAllowed();
    error ExecutionForbidden();
    error Unauthorized();

    Configuration public immutable CONFIG;

    IProxyAdmin internal immutable CONFIG_ADMIN;
    GovernanceState internal immutable GOV_STATE;

    ITimelock public immutable TIMELOCK;

    Proposers.State internal _proposers;
    Proposals.State internal _proposals;

    constructor(address config, address initialConfigImpl, address configAdmin, address escrowImpl, address timelock) {
        CONFIG = Configuration(config);
        CONFIG_ADMIN = IProxyAdmin(configAdmin);
        TIMELOCK = ITimelock(timelock);
        GOV_STATE = new GovernanceState(address(CONFIG), address(this), escrowImpl);
        emit ConfigSet(initialConfigImpl);
        _proposers.register(CONFIG.adminProposer(), TIMELOCK.ADMIN_EXECUTOR());
    }

    function signallingEscrow() external returns (address) {
        return GOV_STATE.signallingEscrow();
    }

    function rageQuitEscrow() external returns (address) {
        return GOV_STATE.rageQuitEscrow();
    }

    function currentState() external returns (GovernanceState.State) {
        return GOV_STATE.currentState();
    }

    function activateNextState() external returns (GovernanceState.State) {
        return GOV_STATE.activateNextState();
    }

    function updateConfig(address newConfig) external onlyAdminExecutor {
        CONFIG_ADMIN.upgradeAndCall(address(CONFIG), newConfig, new bytes(0));
        emit ConfigSet(newConfig);
    }

    function hasProposer(address proposer) external view returns (bool) {
        return _proposers.isProposer(proposer);
    }

    function getProposers() external view returns (Proposer[] memory proposers) {
        proposers = _proposers.all();
    }

    function registerProposer(address proposer, address executor) external onlyAdminExecutor {
        return _proposers.register(proposer, executor);
    }

    function unregisterProposer(address proposer) external onlyAdminExecutor {
        _proposers.unregister(proposer);
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        return _proposals.get(proposalId);
    }

    function getProposalsCount() external view returns (uint256 proposalsCount) {
        proposalsCount = _proposals.count();
    }

    function killAllPendingProposals() external {
        GOV_STATE.activateNextState();
        if (msg.sender != CONFIG.adminProposer()) {
            revert Unauthorized();
        }
        _proposals.cancelAll();
    }

    function propose(ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        GOV_STATE.activateNextState();
        if (!GOV_STATE.isProposalSubmissionAllowed()) {
            revert ProposalSubmissionNotAllowed();
        }
        Proposer memory proposer = _proposers.get(msg.sender);
        newProposalId = _proposals.create(proposer.account, proposer.executor, calls);
    }

    function relay(uint256 proposalId) external {
        Proposal memory proposal = _adopt(proposalId);
        TIMELOCK.relay(proposal.executor, proposal.calls);
    }

    function schedule(uint256 proposalId) external {
        Proposal memory proposal = _adopt(proposalId);
        TIMELOCK.schedule(proposalId, proposal.executor, proposal.calls);
    }

    function _adopt(uint256 proposalId) internal returns (Proposal memory proposal) {
        GOV_STATE.activateNextState();
        if (!GOV_STATE.isExecutionEnabled()) {
            revert ExecutionForbidden();
        }
        proposal = _proposals.adopt(proposalId, CONFIG.minProposalExecutionTimelock());
    }

    modifier onlyAdminExecutor() {
        if (msg.sender != TIMELOCK.ADMIN_EXECUTOR()) {
            revert Unauthorized();
        }
        _;
    }
}
