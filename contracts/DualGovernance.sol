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
import {State, DualGovernanceStateMachine} from "./libraries/DualGovernanceStateMachine.sol";

import {Escrow} from "./Escrow.sol";

/// @title Dual Governance
/// @notice Main contract for the Dual Governance system, serving as the central interface for proposal submission
///     and scheduling. The contract is organized as a state machine, managing transitions between governance states
///     and coordinating interactions between the Signalling Escrow and Rage Quit Escrow. It enables stETH, wstETH,
///     and unstETH holders to participate in the governance process and influence dynamic timelock mechanisms based
///     on their locked assets.
contract DualGovernance is IDualGovernance {
    using Proposers for Proposers.Context;
    using Tiebreaker for Tiebreaker.Context;
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
    error InvalidResealCommittee(address resealCommittee);

    // ---
    // Events
    // ---

    event CancelAllPendingProposalsSkipped();
    event CancelAllPendingProposalsExecuted();
    event EscrowMasterCopyDeployed(IEscrow escrowMasterCopy);
    event ResealCommitteeSet(address resealCommittee);

    // ---
    // Sanity Check Parameters & Immutables
    // ---

    /// @notice The parameters for the sanity checks.
    /// @param minWithdrawalsBatchSize The minimum number of withdrawal requests allowed to create during a single call of
    ///     the `Escrow.requestNextWithdrawalsBatch(batchSize)` method.
    /// @param minTiebreakerActivationTimeout The lower bound for the time the Dual Governance must spend in the "locked" state
    ///     before the tiebreaker committee is allowed to schedule proposals.
    /// @param maxTiebreakerActivationTimeout The upper bound for the time the Dual Governance must spend in the "locked" state
    ///     before the tiebreaker committee is allowed to schedule proposals.
    /// @param maxSealableWithdrawalBlockersCount The upper bound for the number of sealable withdrawal blockers allowed to be
    ///     registered in the Dual Governance. This parameter prevents filling the sealable withdrawal blockers
    ///     with so many items that tiebreaker calls would revert due to out-of-gas errors.
    struct SanityCheckParams {
        uint256 minWithdrawalsBatchSize;
        Duration minTiebreakerActivationTimeout;
        Duration maxTiebreakerActivationTimeout;
        uint256 maxSealableWithdrawalBlockersCount;
    }

    /// @notice The lower bound for the time the Dual Governance must spend in the "locked" state
    ///     before the tiebreaker committee is allowed to schedule proposals.
    Duration public immutable MIN_TIEBREAKER_ACTIVATION_TIMEOUT;

    /// @notice The upper bound for the time the Dual Governance must spend in the "locked" state
    ///     before the tiebreaker committee is allowed to schedule proposals.
    Duration public immutable MAX_TIEBREAKER_ACTIVATION_TIMEOUT;

    /// @notice The upper bound for the number of sealable withdrawal blockers allowed to be
    ///     registered in the Dual Governance. This parameter prevents filling the sealable withdrawal blockers
    ///     with so many items that tiebreaker calls would revert due to out-of-gas errors.
    uint256 public immutable MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT;

    // ---
    // External Dependencies
    // ---

    /// @notice The external dependencies of the Dual Governance system.
    /// @param stETH The address of the stETH token.
    /// @param wstETH The address of the wstETH token.
    /// @param withdrawalQueue The address of Lido's Withdrawal Queue and the unstETH token.
    /// @param timelock The address of the Timelock contract.
    /// @param resealManager The address of the Reseal Manager.
    /// @param configProvider The address of the Dual Governance Config Provider.
    struct ExternalDependencies {
        IStETH stETH;
        IWstETH wstETH;
        IWithdrawalQueue withdrawalQueue;
        ITimelock timelock;
        IResealManager resealManager;
        IDualGovernanceConfigProvider configProvider;
    }

    /// @notice The address of the Timelock contract.
    ITimelock public immutable TIMELOCK;

    /// @notice The address of the Reseal Manager.
    IResealManager public immutable RESEAL_MANAGER;

    /// @notice The address of the Escrow contract used as the implementation for the Signalling and Rage Quit
    ///     instances of the Escrows managed by the DualGovernance contract.
    IEscrow public immutable ESCROW_MASTER_COPY;

    // ---
    // Aspects
    // ---

    /// @dev The functionality to manage the proposer -> executor pairs.
    Proposers.Context internal _proposers;

    /// @dev The functionality of the tiebreaker to handle "deadlocks" of the Dual Governance.
    Tiebreaker.Context internal _tiebreaker;

    /// @dev The state machine implementation controlling the state of the Dual Governance.
    DualGovernanceStateMachine.Context internal _stateMachine;

    // ---
    // Standalone State Variables
    // ---

    /// @dev The address of the Reseal Committee which is allowed to "reseal" sealables paused for a limited
    ///     period of time when the Dual Governance proposal adoption is blocked.
    address internal _resealCommittee;

    // ---
    // Constructor
    // ---

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

    /// @notice Allows a registered proposer to submit a proposal to the Dual Governance system. Proposals can only
    ///     be submitted if the system is not in the `VetoSignallingDeactivation` or `VetoCooldown` state.
    ///     Each proposal contains a list of external calls to be executed sequentially, and will revert if
    ///     any call fails during execution.
    /// @param calls An array of `ExternalCall` structs representing the actions to be executed sequentially when
    ///     the proposal is executed. Each call in the array will be executed one-by-one in the specified order.
    ///     If any call reverts, the entire proposal execution will revert.
    /// @param metadata A string containing additional context or information about the proposal. This can be used
    ///     to provide a description, rationale, or other details relevant to the proposal.
    /// @return proposalId The unique identifier of the submitted proposal. This ID can be used to reference the proposal
    ///     in future operations (scheduling and execution) with the proposal.
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

    /// @notice Schedules a previously submitted proposal for execution in the Dual Governance system.
    ///     The proposal can only be scheduled if the current state allows scheduling of the given proposal based on
    ///     the submission time, when the `Escrow.getAfterScheduleDelay()` has passed and proposal wasn't cancelled
    ///     or scheduled earlier.
    /// @param proposalId The unique identifier of the proposal to be scheduled. This ID is obtained when the proposal
    ///     is initially submitted to the timelock contract.
    function scheduleProposal(uint256 proposalId) external {
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
        Timestamp proposalSubmittedAt = TIMELOCK.getProposalDetails(proposalId).submittedAt;
        if (!_stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})) {
            revert ProposalSchedulingBlocked(proposalId);
        }
        TIMELOCK.schedule(proposalId);
    }

    /// @notice Allows a proposer associated with the admin executor to cancel all previously submitted or scheduled
    ///     but not yet executed proposals when the Dual Governance system is in the `VetoSignalling`
    ///     or `VetoSignallingDeactivation` state.
    /// @dev If the Dual Governance state is not `VetoSignalling` or `VetoSignallingDeactivation`, the function will
    ///     exit early, emitting the `CancelAllPendingProposalsSkipped` event without canceling any proposals.
    /// @return isProposalsCancelled A boolean indicating whether the proposals were successfully canceled (`true`)
    ///     or the cancellation was skipped due to an inappropriate state (`false`).
    function cancelAllPendingProposals() external returns (bool) {
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);

        Proposers.Proposer memory proposer = _proposers.getProposer(msg.sender);
        if (proposer.executor != TIMELOCK.getAdminExecutor()) {
            revert NotAdminProposer();
        }

        if (!_stateMachine.canCancelAllPendingProposals({useEffectiveState: false})) {
            /// @dev Some proposer contracts, like Aragon Voting, may not support canceling decisions that have already
            ///     reached consensus. This could lead to a situation where a proposer’s cancelAllPendingProposals() call
            ///     becomes unexecutable if the Dual Governance state changes. However, it might become executable again if
            ///     the system state shifts back to VetoSignalling or VetoSignallingDeactivation.
            ///     To avoid such a scenario, an early return is used instead of a revert when proposals cannot be canceled
            ///     due to an unsuitable Dual Governance state.
            emit CancelAllPendingProposalsSkipped();
            return false;
        }

        TIMELOCK.cancelAllNonExecutedProposals();
        emit CancelAllPendingProposalsExecuted();
        return true;
    }

    /// @notice Returns whether proposal submission is allowed based on the current `effective` state of the Dual Governance system.
    /// @dev Proposal submission is forbidden in the `VetoSignalling` and `VetoSignallingDeactivation` states.
    /// @return canSubmitProposal A boolean value indicating whether proposal submission is allowed (`true`) or not (`false`)
    ///     based on the current `effective` state of the Dual Governance system.
    function canSubmitProposal() external view returns (bool) {
        return _stateMachine.canSubmitProposal({useEffectiveState: true});
    }

    /// @notice Returns whether a previously submitted proposal can be scheduled for execution based on the `effective`
    ///     state of the Dual Governance system, the proposal's submission time, and its current status.
    /// @dev Proposal scheduling is allowed only if all the following conditions are met:
    ///     - The Dual Governance system is in the `Normal` or `VetoCooldown` state.
    ///     - If the system is in the `VetoCooldown` state, the proposal must have been submitted before the system
    ///         last entered the `VetoSignalling` state.
    ///     - The proposal has not already been scheduled, canceled, or executed.
    ///     - The required delay period, as defined by `Escrow.getAfterSubmitDelay()`, has elapsed since the proposal
    ///         was submitted.
    /// @param proposalId The unique identifier of the proposal to check.
    /// @return canScheduleProposal A boolean value indicating whether the proposal can be scheduled (`true`) or
    ///     not (`false`) based on the current `effective` state of the Dual Governance system and the proposal's status.
    function canScheduleProposal(uint256 proposalId) external view returns (bool) {
        Timestamp proposalSubmittedAt = TIMELOCK.getProposalDetails(proposalId).submittedAt;
        return _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
            && TIMELOCK.canSchedule(proposalId);
    }

    /// @notice Indicates whether the cancellation of all pending proposals is allowed based on the `effective` state
    ///     of the Dual Governance system, ensuring that the cancellation will not be skipped when calling the
    ///     `DualGovernance.cancelAllPendingProposals()` method.
    /// @dev Proposal cancellation is only allowed when the Dual Governance system is in the `VetoSignalling` or
    ///     `VetoSignallingDeactivation` states. In any other state, the cancellation will be skipped and no proposals
    ///     will be canceled.
    /// @return canCancelAllPendingProposals A boolean value indicating whether the pending proposals can be
    ///     canceled (`true`) or not (`false`) based on the current `effective` state of the Dual Governance system.
    function canCancelAllPendingProposals() external view returns (bool) {
        return _stateMachine.canCancelAllPendingProposals({useEffectiveState: true});
    }

    // ---
    // Dual Governance State
    // ---

    /// @notice Updates the state of the Dual Governance State Machine if a state transition is possible.
    /// @dev This function should be called when the `persisted` and `effective` states of the system are not equal.
    ///     If the states are already synchronized, the function will complete without making any changes to the system state.
    function activateNextState() external {
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
    }

    /// @notice Updates the address of the configuration provider for the Dual Governance system.
    /// @param newConfigProvider The address of the new configuration provider contract.
    function setConfigProvider(IDualGovernanceConfigProvider newConfigProvider) external {
        _checkCallerIsAdminExecutor();
        _stateMachine.setConfigProvider(newConfigProvider);
    }

    /// @notice Returns the current configuration provider address for the Dual Governance system.
    /// @return configProvider The address of the current configuration provider contract.
    function getConfigProvider() external view returns (IDualGovernanceConfigProvider) {
        return _stateMachine.configProvider;
    }

    /// @notice Returns the address of the veto signaling escrow contract.
    /// @return vetoSignallingEscrow The address of the veto signaling escrow contract.
    function getVetoSignallingEscrow() external view returns (address) {
        return address(_stateMachine.signallingEscrow);
    }

    /// @notice Returns the address of the rage quit escrow contract used in the most recent or ongoing rage quit.
    /// @dev The returned address will be the zero address if no rage quits have occurred in the system.
    /// @return rageQuitEscrow The address of the rage quit escrow contract.
    function getRageQuitEscrow() external view returns (address) {
        return address(_stateMachine.rageQuitEscrow);
    }

    /// @notice Returns the most recently stored (`persisted`) state of the Dual Governance State Machine.
    /// @return persistedState The current persisted state of the system.
    function getPersistedState() external view returns (State persistedState) {
        persistedState = _stateMachine.getPersistedState();
    }

    /// @notice Returns the current `effective` state of the Dual Governance State Machine.
    /// @dev The effective state represents the state the system would transition to upon calling `activateNextState()`.
    /// @return effectiveState The current effective state of the system.
    function getEffectiveState() external view returns (State effectiveState) {
        effectiveState = _stateMachine.getEffectiveState();
    }

    /// @notice Returns detailed information about the current state of the Dual Governance State Machine.
    /// @return stateDetails A struct containing comprehensive details about the current state of the system, including:
    ///     - `effectiveState`: The `effective` state of the Dual Governance system.
    ///     - `persistedState`: The `persisted` state of the Dual Governance system.
    ///     - `persistedStateEnteredAt`: The timestamp when the system entered the current `persisted` state.
    ///     - `vetoSignallingActivatedAt`: The timestamp when `VetoSignalling` was last activated.
    ///     - `vetoSignallingReactivationTime`: The timestamp of the last transition from `VetoSignallingDeactivation`
    ///            to `VetoSignalling`.
    ///     - `normalOrVetoCooldownExitedAt`: The timestamp of the last exit from either the `Normal` or `VetoCooldown` state.
    ///     - `rageQuitRound`: The current count of consecutive Rage Quit rounds, starting from 0.
    ///     - `vetoSignallingDuration`: The expected duration of the `VetoSignalling` state, based on the support for rage quit
    ///        in the veto signalling escrow contract.
    function getStateDetails() external view returns (StateDetails memory stateDetails) {
        return _stateMachine.getStateDetails();
    }

    // ---
    // Proposers & Executors Management
    // ---

    /// @notice Registers a new proposer with the associated executor in the system.
    /// @dev Multiple proposers can share the same executor contract, but each proposer must be unique.
    /// @param proposer The address of the proposer to register.
    /// @param executor The address of the executor contract associated with the proposer.
    function registerProposer(address proposer, address executor) external {
        _checkCallerIsAdminExecutor();
        _proposers.register(proposer, executor);
    }

    /// @notice Unregisters a proposer from the system.
    /// @dev There must always be at least one proposer associated with the admin executor. If an attempt is made to
    ///     remove the last proposer assigned to the admin executor, the function will revert.
    /// @param proposer The address of the proposer to unregister.
    function unregisterProposer(address proposer) external {
        _checkCallerIsAdminExecutor();
        _proposers.unregister(proposer);

        /// @dev after the removal of the proposer, check that admin executor still belongs to some proposer
        if (!_proposers.isExecutor(TIMELOCK.getAdminExecutor())) {
            revert UnownedAdminExecutor();
        }
    }

    /// @notice Checks whether the given `account` is a registered proposer.
    /// @param account The address to check.
    /// @return isProposer A boolean value indicating whether the `account` is a registered
    ///     proposer (`true`) or not (`false`).
    function isProposer(address account) external view returns (bool) {
        return _proposers.isProposer(account);
    }

    /// @notice Returns the proposer data if the given `account` is a registered proposer.
    /// @param account The address of the proposer to retrieve information for.
    /// @return proposer A Proposer struct containing the data of the registered proposer, including:
    ///     - `account`: The address of the registered proposer.
    ///     - `executor`: The address of the executor associated with the proposer.
    function getProposer(address account) external view returns (Proposers.Proposer memory proposer) {
        proposer = _proposers.getProposer(account);
    }

    /// @notice Returns the information about all registered proposers.
    /// @return proposers An array of `Proposer` structs containing the data of all registered proposers.
    function getProposers() external view returns (Proposers.Proposer[] memory proposers) {
        proposers = _proposers.getAllProposers();
    }

    /// @notice Checks whether the given `account` is associated with an executor contract in the system.
    /// @param account The address to check.
    /// @return isExecutor A boolean value indicating whether the `account` is a registered
    ///     executor (`true`) or not (`false`).
    function isExecutor(address account) external view returns (bool) {
        return _proposers.isExecutor(account);
    }

    // ---
    // Tiebreaker Protection
    // ---

    /// @notice Adds a unique address of a sealable contract that can be paused and may cause a Dual Governance tie (deadlock).
    /// @dev A tie may occur when user withdrawal requests cannot be processed due to the paused state of a registered sealable
    ///     withdrawal blocker while the Dual Governance system is in the RageQuit state.
    ///     The contract being added must implement the `ISealable` interface.
    /// @param sealableWithdrawalBlocker The address of the sealable contract to be added as a tiebreaker withdrawal blocker.
    function addTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.addSealableWithdrawalBlocker(sealableWithdrawalBlocker, MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT);
    }

    /// @notice Removes a previously registered sealable contract from the system.
    /// @param sealableWithdrawalBlocker The address of the sealable contract to be removed.
    function removeTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.removeSealableWithdrawalBlocker(sealableWithdrawalBlocker);
    }

    /// @notice Sets the new address of the tiebreaker committee in the system.
    /// @param tiebreakerCommittee The address of the new tiebreaker committee.
    function setTiebreakerCommittee(address tiebreakerCommittee) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.setTiebreakerCommittee(tiebreakerCommittee);
    }

    /// @notice Sets the new value for the tiebreaker activation timeout.
    /// @dev If the Dual Governance system remains out of the `Normal` or `VetoCooldown` state for longer than
    ///     the `tiebreakerActivationTimeout` duration, the tiebreaker committee is allowed to schedule
    ///     submitted proposals.
    /// @param tiebreakerActivationTimeout The new duration for the tiebreaker activation timeout.
    function setTiebreakerActivationTimeout(Duration tiebreakerActivationTimeout) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.setTiebreakerActivationTimeout(
            MIN_TIEBREAKER_ACTIVATION_TIMEOUT, tiebreakerActivationTimeout, MAX_TIEBREAKER_ACTIVATION_TIMEOUT
        );
    }

    /// @notice Allows the tiebreaker committee to resume a paused sealable contract when the system is in a tie state.
    /// @param sealable The address of the sealable contract to be resumed.
    function tiebreakerResumeSealable(address sealable) external {
        _tiebreaker.checkCallerIsTiebreakerCommittee();
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
        _tiebreaker.checkTie(_stateMachine.getPersistedState(), _stateMachine.normalOrVetoCooldownExitedAt);
        RESEAL_MANAGER.resume(sealable);
    }

    /// @notice Allows the tiebreaker committee to schedule for execution a submitted proposal when
    ///     the system is in a tie state.
    /// @param proposalId The unique identifier of the proposal to be scheduled.
    function tiebreakerScheduleProposal(uint256 proposalId) external {
        _tiebreaker.checkCallerIsTiebreakerCommittee();
        _stateMachine.activateNextState(ESCROW_MASTER_COPY);
        _tiebreaker.checkTie(_stateMachine.getPersistedState(), _stateMachine.normalOrVetoCooldownExitedAt);
        TIMELOCK.schedule(proposalId);
    }

    /// @notice Returns detailed information about the current tiebreaker state based on the `effective` state of the system.
    /// @return tiebreakerState A struct containing detailed information about the current state of the tiebreaker system, including:
    ///     - `isTie`: Indicates whether the system is in a tie state, allowing the tiebreaker committee to schedule proposals
    ///             or resume sealable contracts.
    ///     - `tiebreakerCommittee`: The address of the current tiebreaker committee.
    ///     - `tiebreakerActivationTimeout`: The required duration the system must remain in a "locked" state
    ///             (not in `Normal` or `VetoCooldown` state) before the tiebreaker committee is permitted to take actions.
    ///     - `sealableWithdrawalBlockers`: An array of sealable contracts registered in the system as withdrawal blockers.
    function getTiebreakerDetails() external view returns (ITiebreaker.TiebreakerDetails memory tiebreakerState) {
        return _tiebreaker.getTiebreakerDetails(_stateMachine.getStateDetails());
    }

    // ---
    // Sealables Resealing
    // ---

    /// @notice Allows the reseal committee to "reseal" (pause indefinitely) an instance of a sealable contract through
    ///     the ResealManager contract.
    /// @param sealable The address of the sealable contract to be resealed.
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

    /// @notice Sets the address of the reseal committee.
    /// @param resealCommittee The address of the new reseal committee.
    function setResealCommittee(address resealCommittee) external {
        _checkCallerIsAdminExecutor();

        if (resealCommittee == _resealCommittee) {
            revert InvalidResealCommittee(resealCommittee);
        }
        _resealCommittee = resealCommittee;

        emit ResealCommitteeSet(resealCommittee);
    }

    // ---
    // Internal methods
    // ---

    function _checkCallerIsAdminExecutor() internal view {
        if (TIMELOCK.getAdminExecutor() != msg.sender) {
            revert CallerIsNotAdminExecutor(msg.sender);
        }
    }
}
