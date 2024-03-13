// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IGovernance} from "./interfaces/ITimelock.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";
import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";
import {DualGovernanceState, Status as DualGovernanceStatus} from "./libraries/DualGovernanceState.sol";

interface ITimelock {
    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId);
    function execute(uint256 proposalId) external;
    function cancelAll() external;

    function isEmergencyProtectionEnabled() external view returns (bool);

    function isDelayPassed(uint256 proposalId) external view returns (bool);
    function isProposalSubmitted(uint256 proposalId) external view returns (bool);

    function getProposalsCount() external view returns (uint256 count);
    function canExecute(uint256 proposalId) external view returns (bool);

    function transferExecutorOwnership(address executor, address owner) external;
    function setGovernance(address governance) external;
    function getGovernance() external view returns (address);
}

contract DualGovernance is IGovernance, ConfigurationProvider {
    using Proposers for Proposers.State;
    using DualGovernanceState for DualGovernanceState.State;

    event TiebreakerSet(address tiebreakCommittee);
    event ProposalScheduled(uint256 proposalId);

    error ProposalNotReady();
    error ExecutionDisabled();
    error SchedulingDisabled();
    error ProposalNotScheduled();
    error ProposalsCreationSuspended();
    error ProposalsAdoptionSuspended();
    error ProposalNotSubmitted(uint256 proposalId);
    error ProposalNotExecutable(uint256 proposalId);
    error NotTiebreaker(address account, address tiebreakCommittee);

    ITimelock public immutable TIMELOCK;

    address internal _tiebreaker;

    Proposers.State internal _proposers;
    DualGovernanceState.State internal _dgState;
    EmergencyProtection.State internal _emergencyProtection;
    mapping(uint256 proposalId => uint256 executableAfter) internal _scheduledProposals;

    constructor(
        address config,
        address timelock,
        address escrowMasterCopy,
        address adminProposer
    ) ConfigurationProvider(config) {
        TIMELOCK = ITimelock(timelock);

        _dgState.initialize(escrowMasterCopy);
        _proposers.register(adminProposer, CONFIG.ADMIN_EXECUTOR());
    }

    function submit(ExecutorCall[] calldata calls) external returns (uint256 proposalId) {
        _dgState.activateNextState(CONFIG);
        _proposers.checkProposer(msg.sender);
        _dgState.checkProposalsCreationAllowed();
        _dgState.setLastProposalCreationTimestamp();
        Proposer memory proposer = _proposers.get(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function schedule(uint256 proposalId) external {
        _dgState.activateNextState(CONFIG);
        if (!TIMELOCK.isEmergencyProtectionEnabled()) {
            revert SchedulingDisabled();
        }
        if (!_dgState.isProposalsAdoptionAllowed()) {
            revert ProposalsAdoptionSuspended();
        }
        if (!TIMELOCK.isProposalSubmitted(proposalId)) {
            revert ProposalNotSubmitted(proposalId);
        }
        _scheduledProposals[proposalId] = block.timestamp + CONFIG.AFTER_SCHEDULE_DELAY();
        emit ProposalScheduled(proposalId);
    }

    function execute(uint256 proposalId) external {
        if (TIMELOCK.isEmergencyProtectionEnabled()) {
            _executeWhenSchedulingEnabled(proposalId);
        } else {
            _execute(proposalId);
        }
    }

    function cancelAll() external {
        _dgState.activateNextState(CONFIG);
        _proposers.checkAdminProposer(CONFIG, msg.sender);
        TIMELOCK.cancelAll();
    }

    function signallingEscrow() external view returns (address) {
        return address(_dgState.signallingEscrow);
    }

    function isScheduled(uint256 proposalId) external view returns (bool) {
        return _scheduledProposals[proposalId] != 0;
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        return TIMELOCK.isEmergencyProtectionEnabled() && TIMELOCK.isProposalSubmitted(proposalId)
            && _dgState.isProposalsAdoptionAllowed() && TIMELOCK.isDelayPassed(proposalId)
            && _scheduledProposals[proposalId] == 0;
    }

    function canExecute(uint256 proposalId) external view returns (bool) {
        if (!_dgState.isProposalsAdoptionAllowed()) return false;
        if (!TIMELOCK.canExecute(proposalId)) return false;
        if (TIMELOCK.isEmergencyProtectionEnabled()) {
            return _scheduledProposals[proposalId] != 0 && block.timestamp > _scheduledProposals[proposalId];
        }
        return true;
    }

    // ---
    // Dual Governance State
    // ---

    function activateNextState() external {
        _dgState.activateNextState(CONFIG);
    }

    function currentState() external view returns (DualGovernanceStatus) {
        return _dgState.currentState();
    }

    function getVetoSignallingState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt)
    {
        (isActive, duration, activatedAt, enteredAt) = _dgState.getVetoSignallingState(CONFIG);
    }

    function getVetoSignallingDeactivationState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 enteredAt)
    {
        (isActive, duration, enteredAt) = _dgState.getVetoSignallingDeactivationState(CONFIG);
    }

    function getVetoSignallingDuration() external view returns (uint256) {
        return _dgState.getVetoSignallingDuration(CONFIG);
    }

    // ---
    // Proposers & Executors Management
    // ---

    function registerProposer(address proposer, address executor) external {
        _checkAdminExecutor(msg.sender);
        _proposers.register(proposer, executor);
    }

    function unregisterProposer(address proposer) external {
        _checkAdminExecutor(msg.sender);
        _proposers.unregister(CONFIG, proposer);
    }

    function getProposer(address account) external view returns (Proposer memory proposer) {
        proposer = _proposers.get(account);
    }

    function getProposers() external view returns (Proposer[] memory proposers) {
        proposers = _proposers.all();
    }

    function isProposer(address account) external view returns (bool) {
        return _proposers.isProposer(account);
    }

    function isExecutor(address account) external view returns (bool) {
        return _proposers.isExecutor(account);
    }

    // ---
    // Tiebreaker Protection
    // ---

    function tiebreakerExecute(uint256 proposalId) external {
        _checkTiebreakerCommittee(msg.sender);
        _dgState.checkTiebreak(CONFIG);
        TIMELOCK.execute(proposalId);
    }

    function setTiebreakerProtection(address newTiebreaker) external {
        _checkAdminExecutor(msg.sender);
        address oldTiebreaker = _tiebreaker;
        if (newTiebreaker != oldTiebreaker) {
            _tiebreaker = newTiebreaker;
            emit TiebreakerSet(newTiebreaker);
        }
    }

    // ---
    // Internal Helper Methods
    // ---

    function _checkTiebreakerCommittee(address account) internal view {
        if (account != _tiebreaker) {
            revert NotTiebreaker(account, _tiebreaker);
        }
    }

    function _executeWhenSchedulingEnabled(uint256 proposalId) internal {
        if (_scheduledProposals[proposalId] == 0) {
            revert ProposalNotScheduled();
        }
        if (_scheduledProposals[proposalId] > block.timestamp) {
            revert ProposalNotReady();
        }
        TIMELOCK.execute(proposalId);
    }

    function _execute(uint256 proposalId) internal {
        _dgState.activateNextState(CONFIG);

        if (!_dgState.isProposalsAdoptionAllowed()) {
            revert ProposalsAdoptionSuspended();
        }
        TIMELOCK.execute(proposalId);
    }
}
