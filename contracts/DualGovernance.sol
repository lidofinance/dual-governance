// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";
import {IEscrow} from "./interfaces/IEscrow.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";
import {ITiebreaker} from "./interfaces/ITiebreaker.sol";
import {IDualGovernance} from "./interfaces/IDualGovernance.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";
import {IDualGovernanceConfigProvider} from "./interfaces/IDualGovernanceConfigProvider.sol";

import {Proposers} from "./libraries/Proposers.sol";
import {Tiebreaker} from "./libraries/Tiebreaker.sol";
import {ExternalCall} from "./libraries/ExternalCalls.sol";
import {DualGovernanceConfig} from "./libraries/DualGovernanceConfig.sol";
import {State, DualGovernanceStateMachine} from "./libraries/DualGovernanceStateMachine.sol";

import {Escrow} from "./Escrow.sol";

contract DualGovernance is IDualGovernance {
    using Proposers for Proposers.Context;
    using Tiebreaker for Tiebreaker.Context;
    using DualGovernanceConfig for DualGovernanceConfig.Context;
    using DualGovernanceStateMachine for DualGovernanceStateMachine.Context;

    // ---
    // Errors
    // ---

    error NotAdminProposer();
    error UnownedAdminExecutor();
    error CallerIsNotResealCommittee(address caller);
    error CallerIsNotAdminExecutor(address caller);
    error ProposalSubmissionBlocked();
    error ProposalSchedulingBlocked(uint256 proposalId);
    error ResealIsNotAllowedInNormalState();

    // ---
    // Events
    // ---

    event CancelAllPendingProposalsSkipped();
    event CancelAllPendingProposalsExecuted();
    event EscrowMasterCopyDeployed(IEscrow escrowMasterCopy);
    event ResealCommitteeSet(address resealCommittee);

    // ---
    // Tiebreaker Sanity Check Param Immutables
    // ---

    struct SanityCheckParams {
        uint256 minWithdrawalsBatchSize;
        Duration minTiebreakerActivationTimeout;
        Duration maxTiebreakerActivationTimeout;
        uint256 maxSealableWithdrawalBlockersCount;
    }

    Duration public immutable MIN_TIEBREAKER_ACTIVATION_TIMEOUT;
    Duration public immutable MAX_TIEBREAKER_ACTIVATION_TIMEOUT;
    uint256 public immutable MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT;

    // ---
    // External Parts Immutables

    struct ExternalDependencies {
        IStETH stETH;
        IWstETH wstETH;
        IWithdrawalQueue withdrawalQueue;
        ITimelock timelock;
        IResealManager resealManager;
        IDualGovernanceConfigProvider configProvider;
    }

    ITimelock public immutable TIMELOCK;
    IResealManager public immutable RESEAL_MANAGER;
    IEscrow public immutable ESCROW_MASTER_COPY;

    // ---
    // Aspects
    // ---

    Proposers.Context internal _proposers;
    Tiebreaker.Context internal _tiebreaker;
    DualGovernanceStateMachine.Context internal _stateMachine;

    // ---
    // Standalone State Variables
    // ---
    address internal _resealCommittee;

    constructor(ExternalDependencies memory dependencies, SanityCheckParams memory sanityCheckParams) {
        TIMELOCK = dependencies.timelock;
        RESEAL_MANAGER = dependencies.resealManager;

        MIN_TIEBREAKER_ACTIVATION_TIMEOUT = sanityCheckParams.minTiebreakerActivationTimeout;
        MAX_TIEBREAKER_ACTIVATION_TIMEOUT = sanityCheckParams.maxTiebreakerActivationTimeout;
        MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = sanityCheckParams.maxSealableWithdrawalBlockersCount;

        ESCROW_MASTER_COPY = new Escrow({
            dualGovernance: this,
            stETH: dependencies.stETH,
            wstETH: dependencies.wstETH,
            withdrawalQueue: dependencies.withdrawalQueue,
            minWithdrawalsBatchSize: sanityCheckParams.minWithdrawalsBatchSize
        });

        emit EscrowMasterCopyDeployed(ESCROW_MASTER_COPY);

        _stateMachine.initialize(dependencies.configProvider, ESCROW_MASTER_COPY);
    }

    // ---
    // Proposals Flow
    // ---

    function submitProposal(
        ExternalCall[] calldata calls,
        string calldata metadata
    ) external returns (uint256 proposalId) {
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
        if (!_stateMachine.canSubmitProposal({useEffectiveState: false})) {
            revert ProposalSubmissionBlocked();
        }
        Proposers.Proposer memory proposer = _proposers.getProposer(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls, metadata);
    }

    function scheduleProposal(uint256 proposalId) external {
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
        Timestamp proposalSubmittedAt = TIMELOCK.getProposalDetails(proposalId).submittedAt;
        if (!_stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})) {
            revert ProposalSchedulingBlocked(proposalId);
        }
        TIMELOCK.schedule(proposalId);
    }

    function cancelAllPendingProposals() external {
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);

        Proposers.Proposer memory proposer = _proposers.getProposer(msg.sender);
        if (proposer.executor != TIMELOCK.getAdminExecutor()) {
            revert NotAdminProposer();
        }

        State persistedState = _stateMachine.getPersistedState();
        if (persistedState != State.VetoSignalling && persistedState != State.VetoSignallingDeactivation) {
            /// @dev Some proposer contracts, like Aragon Voting, may not support canceling decisions that have already
            /// reached consensus. This could lead to a situation where a proposer’s cancelAllPendingProposals() call
            /// becomes unexecutable if the Dual Governance state changes. However, it might become executable again if
            /// the system state shifts back to VetoSignalling or VetoSignallingDeactivation.
            /// To avoid such a scenario, an early return is used instead of a revert when proposals cannot be canceled
            /// due to an unsuitable Dual Governance state.
            emit CancelAllPendingProposalsSkipped();
            return;
        }

        TIMELOCK.cancelAllNonExecutedProposals();
        emit CancelAllPendingProposalsExecuted();
    }

    function canSubmitProposal() public view returns (bool) {
        return _stateMachine.canSubmitProposal({useEffectiveState: true});
    }

    function canScheduleProposal(uint256 proposalId) external view returns (bool) {
        Timestamp proposalSubmittedAt = TIMELOCK.getProposalDetails(proposalId).submittedAt;
        return _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
            && TIMELOCK.canSchedule(proposalId);
    }

    // ---
    // Dual Governance State
    // ---

    function activateNextState() external {
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
    }

    function setConfigProvider(IDualGovernanceConfigProvider newConfigProvider) external {
        _checkCallerIsAdminExecutor();
        _stateMachine.setConfigProvider(newConfigProvider);
    }

    function getConfigProvider() external view returns (IDualGovernanceConfigProvider) {
        return _stateMachine.configProvider;
    }

    function getVetoSignallingEscrow() external view returns (address) {
        return address(_stateMachine.signallingEscrow);
    }

    function getRageQuitEscrow() external view returns (address) {
        return address(_stateMachine.rageQuitEscrow);
    }

    function getPersistedState() external view returns (State state) {
        state = _stateMachine.getPersistedState();
    }

    function getEffectiveState() external view returns (State state) {
        state = _stateMachine.getEffectiveState();
    }

    function getStateDetails() external view returns (IDualGovernance.StateDetails memory stateDetails) {
        return _stateMachine.getStateDetails();
    }

    // ---
    // Proposers & Executors Management
    // ---

    function registerProposer(address proposer, address executor) external {
        _checkCallerIsAdminExecutor();
        _proposers.register(proposer, executor);
    }

    function unregisterProposer(address proposer) external {
        _checkCallerIsAdminExecutor();
        _proposers.unregister(proposer);

        /// @dev after the removal of the proposer, check that admin executor still belongs to some proposer
        if (!_proposers.isExecutor(TIMELOCK.getAdminExecutor())) {
            revert UnownedAdminExecutor();
        }
    }

    function isProposer(address account) external view returns (bool) {
        return _proposers.isProposer(account);
    }

    function getProposer(address account) external view returns (Proposers.Proposer memory proposer) {
        proposer = _proposers.getProposer(account);
    }

    function getProposers() external view returns (Proposers.Proposer[] memory proposers) {
        proposers = _proposers.getAllProposers();
    }

    function isExecutor(address account) external view returns (bool) {
        return _proposers.isExecutor(account);
    }

    // ---
    // Tiebreaker Protection
    // ---

    function addTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.addSealableWithdrawalBlocker(sealableWithdrawalBlocker, MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT);
    }

    function removeTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.removeSealableWithdrawalBlocker(sealableWithdrawalBlocker);
    }

    function setTiebreakerCommittee(address tiebreakerCommittee) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.setTiebreakerCommittee(tiebreakerCommittee);
    }

    function setTiebreakerActivationTimeout(Duration tiebreakerActivationTimeout) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.setTiebreakerActivationTimeout(
            MIN_TIEBREAKER_ACTIVATION_TIMEOUT, tiebreakerActivationTimeout, MAX_TIEBREAKER_ACTIVATION_TIMEOUT
        );
    }

    function tiebreakerResumeSealable(address sealable) external {
        _tiebreaker.checkCallerIsTiebreakerCommittee();
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
        _tiebreaker.checkTie(_stateMachine.getPersistedState(), _stateMachine.getNormalOrVetoCooldownStateExitedAt());
        RESEAL_MANAGER.resume(sealable);
    }

    function tiebreakerScheduleProposal(uint256 proposalId) external {
        _tiebreaker.checkCallerIsTiebreakerCommittee();
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
        _tiebreaker.checkTie(_stateMachine.getPersistedState(), _stateMachine.getNormalOrVetoCooldownStateExitedAt());
        TIMELOCK.schedule(proposalId);
    }

    function getTiebreakerDetails() external view returns (ITiebreaker.TiebreakerDetails memory tiebreakerState) {
        return _tiebreaker.getTiebreakerDetails(
            /// @dev Calling getEffectiveState() doesn't update the normalOrVetoCooldownStateExitedAt value,
            /// but this does not distort the result of getTiebreakerDetails()
            _stateMachine.getEffectiveState(),
            _stateMachine.getNormalOrVetoCooldownStateExitedAt()
        );
    }

    // ---
    // Reseal executor
    // ---

    function resealSealable(address sealable) external {
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
        if (msg.sender != _resealCommittee) {
            revert CallerIsNotResealCommittee(msg.sender);
        }
        if (_stateMachine.getPersistedState() == State.Normal) {
            revert ResealIsNotAllowedInNormalState();
        }
        RESEAL_MANAGER.reseal(sealable);
    }

    function setResealCommittee(address resealCommittee) external {
        _checkCallerIsAdminExecutor();
        _resealCommittee = resealCommittee;

        emit ResealCommitteeSet(resealCommittee);
    }

    // ---
    // Private methods
    // ---

    function _checkCallerIsAdminExecutor() internal view {
        if (TIMELOCK.getAdminExecutor() != msg.sender) {
            revert CallerIsNotAdminExecutor(msg.sender);
        }
    }
}
