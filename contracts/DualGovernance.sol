// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";
import {IEscrowBase} from "./interfaces/IEscrowBase.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";
import {ITiebreaker} from "./interfaces/ITiebreaker.sol";
import {IDualGovernance} from "./interfaces/IDualGovernance.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";
import {IDualGovernanceConfigProvider} from "./interfaces/IDualGovernanceConfigProvider.sol";

import {Proposers} from "./libraries/Proposers.sol";
import {Tiebreaker} from "./libraries/Tiebreaker.sol";
import {ExternalCall} from "./libraries/ExternalCalls.sol";
import {Resealer} from "./libraries/Resealer.sol";
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
    using Resealer for Resealer.Context;

    // ---
    // Errors
    // ---

    error CallerIsNotAdminExecutor(address caller);
    error CallerIsNotProposalsCanceller(address caller);
    error InvalidProposalsCanceller(address canceller);
    error ProposalSubmissionBlocked();
    error ProposalSchedulingBlocked(uint256 proposalId);
    error ResealIsNotAllowedInNormalState();
    error InvalidTiebreakerActivationTimeoutBounds(
        Duration minTiebreakerActivationTimeout, Duration maxTiebreakerActivationTimeout
    );

    // ---
    // Events
    // ---

    event CancelAllPendingProposalsSkipped();
    event CancelAllPendingProposalsExecuted();
    event ProposalsCancellerSet(address proposalsCanceller);
    event EscrowMasterCopyDeployed(IEscrowBase escrowMasterCopy);

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
    /// @param maxMinAssetsLockDuration The upper bound for the minimum duration of assets lock in the Escrow.
    struct SanityCheckParams {
        uint256 minWithdrawalsBatchSize;
        Duration minTiebreakerActivationTimeout;
        Duration maxTiebreakerActivationTimeout;
        uint256 maxSealableWithdrawalBlockersCount;
        Duration maxMinAssetsLockDuration;
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

    /// @notice Token addresses that used in the Dual Governance as signalling tokens.
    /// @param stETH The address of the stETH token.
    /// @param wstETH The address of the wstETH token.
    /// @param withdrawalQueue The address of Lido's Withdrawal Queue and the unstETH token.
    struct SignallingTokens {
        IStETH stETH;
        IWstETH wstETH;
        IWithdrawalQueue withdrawalQueue;
    }

    /// @notice Dependencies required by the Dual Governance contract.
    /// @param timelock The address of the Timelock contract.
    /// @param resealManager The address of the Reseal Manager.
    /// @param configProvider The address of the Dual Governance Config Provider.
    struct DualGovernanceComponents {
        ITimelock timelock;
        IResealManager resealManager;
        IDualGovernanceConfigProvider configProvider;
    }

    /// @notice The address of the Timelock contract.
    ITimelock public immutable TIMELOCK;

    // ---
    // Aspects
    // ---

    /// @dev The functionality to manage the proposer -> executor pairs.
    Proposers.Context internal _proposers;

    /// @dev The functionality of the tiebreaker to handle "deadlocks" of the Dual Governance.
    Tiebreaker.Context internal _tiebreaker;

    /// @dev The state machine implementation controlling the state of the Dual Governance.
    DualGovernanceStateMachine.Context internal _stateMachine;

    /// @dev The functionality for sealing/resuming critical components of Lido protocol.
    Resealer.Context internal _resealer;

    /// @dev The address authorized to call `cancelAllPendingProposals()`, allowing it to cancel all proposals that are
    ///     submitted or scheduled but not yet executed.
    address internal _proposalsCanceller;

    // ---
    // Constructor
    // ---

    constructor(
        DualGovernanceComponents memory components,
        SignallingTokens memory signallingTokens,
        SanityCheckParams memory sanityCheckParams
    ) {
        if (sanityCheckParams.minTiebreakerActivationTimeout > sanityCheckParams.maxTiebreakerActivationTimeout) {
            revert InvalidTiebreakerActivationTimeoutBounds(
                sanityCheckParams.minTiebreakerActivationTimeout, sanityCheckParams.maxTiebreakerActivationTimeout
            );
        }

        TIMELOCK = components.timelock;

        MIN_TIEBREAKER_ACTIVATION_TIMEOUT = sanityCheckParams.minTiebreakerActivationTimeout;
        MAX_TIEBREAKER_ACTIVATION_TIMEOUT = sanityCheckParams.maxTiebreakerActivationTimeout;
        MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = sanityCheckParams.maxSealableWithdrawalBlockersCount;

        IEscrowBase escrowMasterCopy = new Escrow({
            dualGovernance: this,
            stETH: signallingTokens.stETH,
            wstETH: signallingTokens.wstETH,
            withdrawalQueue: signallingTokens.withdrawalQueue,
            minWithdrawalsBatchSize: sanityCheckParams.minWithdrawalsBatchSize,
            maxMinAssetsLockDuration: sanityCheckParams.maxMinAssetsLockDuration
        });

        emit EscrowMasterCopyDeployed(escrowMasterCopy);

        _stateMachine.initialize(components.configProvider, escrowMasterCopy);
        _resealer.setResealManager(components.resealManager);
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
        _stateMachine.activateNextState();
        if (!_stateMachine.canSubmitProposal({useEffectiveState: false})) {
            revert ProposalSubmissionBlocked();
        }
        Proposers.Proposer memory proposer = _proposers.getProposer(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);

        emit ProposalSubmitted(proposer.account, proposalId, metadata);
    }

    /// @notice Schedules a previously submitted proposal for execution in the Dual Governance system.
    ///     The proposal can only be scheduled if the current state allows scheduling of the given proposal based on
    ///     the submission time, when the `ITimelock.getAfterSubmitDelay()` has passed and proposal wasn't cancelled
    ///     or scheduled earlier.
    /// @param proposalId The unique identifier of the proposal to be scheduled. This ID is obtained when the proposal
    ///     is initially submitted to the Dual Governance system.
    function scheduleProposal(uint256 proposalId) external {
        _stateMachine.activateNextState();
        Timestamp proposalSubmittedAt = TIMELOCK.getProposalDetails(proposalId).submittedAt;
        if (!_stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})) {
            revert ProposalSchedulingBlocked(proposalId);
        }
        TIMELOCK.schedule(proposalId);
    }

    /// @notice Allows authorized proposer to cancel all previously submitted or scheduled
    ///     but not yet executed proposals when the Dual Governance system is in the `VetoSignalling`
    ///     or `VetoSignallingDeactivation` state.
    /// @dev If the Dual Governance state is not `VetoSignalling` or `VetoSignallingDeactivation`, the function will
    ///     exit early, emitting the `CancelAllPendingProposalsSkipped` event without canceling any proposals.
    /// @return isProposalsCancelled A boolean indicating whether the proposals were successfully cancelled (`true`)
    ///     or the cancellation was skipped due to an inappropriate state (`false`).
    function cancelAllPendingProposals() external returns (bool) {
        _stateMachine.activateNextState();

        if (msg.sender != _proposalsCanceller) {
            revert CallerIsNotProposalsCanceller(msg.sender);
        }

        if (!_stateMachine.canCancelAllPendingProposals({useEffectiveState: false})) {
            /// @dev Some proposer contracts, like Aragon Voting, may not support canceling decisions that have already
            ///     reached consensus. This could lead to a situation where a cancelAllPendingProposals() call
            ///     becomes unexecutable if the Dual Governance state changes. However, it might become executable again if
            ///     the system state shifts back to VetoSignalling or VetoSignallingDeactivation.
            ///     To avoid such a scenario, an early return is used instead of a revert when proposals cannot be cancelled
            ///     due to an unsuitable Dual Governance state.
            emit CancelAllPendingProposalsSkipped();
            return false;
        }

        TIMELOCK.cancelAllNonExecutedProposals();
        emit CancelAllPendingProposalsExecuted();
        return true;
    }

    /// @notice Returns whether proposal submission is allowed based on the current `effective` state of the Dual Governance system.
    /// @dev Proposal submission is forbidden in the `VetoCooldown` and `VetoSignallingDeactivation` states.
    /// @return canSubmitProposal A boolean value indicating whether proposal submission is allowed (`true`) or not (`false`)
    ///     based on the current `effective` state of the Dual Governance system.
    function canSubmitProposal() external view returns (bool) {
        return _stateMachine.canSubmitProposal({useEffectiveState: true});
    }

    /// @notice Returns whether a previously submitted proposal can be scheduled for execution based on the `effective`
    ///     state of the Dual Governance system, the proposal's submission time, and its current status.
    /// @dev Proposal scheduling is allowed only if all the following conditions are met:
    ///     - The Dual Governance system is in the `Normal` or `VetoCooldown` state.
    ///     - If the system is in the `VetoCooldown` state, the proposal must have been submitted no later than
    ///         when the system last entered the `VetoSignalling` state.
    ///     - The proposal has not already been scheduled, cancelled, or executed.
    ///     - The required delay period, as defined by `ITimelock.getAfterSubmitDelay()`, has elapsed since the proposal
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
    ///     will be cancelled.
    /// @return canCancelAllPendingProposals A boolean value indicating whether the pending proposals can be
    ///     cancelled (`true`) or not (`false`) based on the current `effective` state of the Dual Governance system.
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
        _stateMachine.activateNextState();
    }

    /// @notice Sets the configuration provider for the Dual Governance system.
    /// @param newConfigProvider The contract implementing the `IDualGovernanceConfigProvider` interface.
    function setConfigProvider(IDualGovernanceConfigProvider newConfigProvider) external {
        _checkCallerIsAdminExecutor();
        _stateMachine.setConfigProvider(newConfigProvider);
    }

    /// @notice Sets the address of the proposals canceller authorized to cancel pending proposals.
    /// @param newProposalsCanceller The address of the new proposals canceller.
    function setProposalsCanceller(address newProposalsCanceller) external {
        _checkCallerIsAdminExecutor();

        if (newProposalsCanceller == address(0) || newProposalsCanceller == _proposalsCanceller) {
            revert InvalidProposalsCanceller(newProposalsCanceller);
        }

        _proposalsCanceller = newProposalsCanceller;
        emit ProposalsCancellerSet(newProposalsCanceller);
    }

    /// @notice Returns the current proposals canceller address.
    /// @return address The address of the current proposals canceller.
    function getProposalsCanceller() external view returns (address) {
        return _proposalsCanceller;
    }

    /// @notice Returns the current configuration provider for the Dual Governance system.
    /// @return configProvider The contract implementing the `IDualGovernanceConfigProvider` interface.
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
    /// @param proposerAccount The address of the proposer to register.
    /// @param executor The address of the executor contract associated with the proposer.
    function registerProposer(address proposerAccount, address executor) external {
        _checkCallerIsAdminExecutor();
        _proposers.register(proposerAccount, executor);
    }

    /// @notice Updates the executor associated with a specified proposer.
    /// @dev Ensures that at least one proposer remains assigned to the `adminExecutor` following the update.
    ///     Reverts if updating the proposer’s executor would leave the `adminExecutor` without any associated proposer.
    /// @param proposerAccount The address of the proposer whose executor is being updated.
    /// @param newExecutor The new executor address to assign to the proposer.
    function setProposerExecutor(address proposerAccount, address newExecutor) external {
        _checkCallerIsAdminExecutor();
        _proposers.setProposerExecutor(proposerAccount, newExecutor);

        /// @dev after update of the proposer, check that admin executor still belongs to some proposer
        _proposers.checkRegisteredExecutor(msg.sender);
    }

    /// @notice Unregisters a proposer from the system.
    /// @dev Ensures that at least one proposer remains associated with the `adminExecutor`. If an attempt is made to
    ///     remove the last proposer assigned to the `adminExecutor`, the function will revert.
    /// @param proposerAccount The address of the proposer to unregister.
    function unregisterProposer(address proposerAccount) external {
        _checkCallerIsAdminExecutor();
        _proposers.unregister(proposerAccount);

        /// @dev after the removal of the proposer, check that admin executor still belongs to some proposer
        _proposers.checkRegisteredExecutor(msg.sender);
    }

    /// @notice Returns the proposer data if the given `proposerAccount` is a registered proposer.
    /// @param proposerAccount The address of the proposer to return information for.
    /// @return proposer A Proposer struct containing the data of the registered proposer, including:
    ///     - `account`: The address of the registered proposer.
    ///     - `executor`: The address of the executor associated with the proposer.
    function getProposer(address proposerAccount) external view returns (Proposers.Proposer memory proposer) {
        proposer = _proposers.getProposer(proposerAccount);
    }

    /// @notice Returns the information about all registered proposers.
    /// @return proposers An array of `Proposer` structs containing the data of all registered proposers.
    function getProposers() external view returns (Proposers.Proposer[] memory proposers) {
        proposers = _proposers.getAllProposers();
    }

    /// @notice Returns whether the given `proposerAccount` is a registered proposer.
    /// @param proposerAccount The address to check.
    /// @return isProposer A boolean value indicating whether the `proposerAccount` is a registered
    ///     proposer (`true`) or not (`false`).
    function isProposer(address proposerAccount) external view returns (bool) {
        return _proposers.isRegisteredProposer(proposerAccount);
    }

    /// @notice Returns whether the given `executor` address is associated with an executor contract in the system.
    /// @param executor The address to check.
    /// @return isExecutor A boolean value indicating whether the `executor` is a registered
    ///     executor (`true`) or not (`false`).
    function isExecutor(address executor) external view returns (bool) {
        return _proposers.isRegisteredExecutor(executor);
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
    /// @param newTiebreakerCommittee The address of the new tiebreaker committee.
    function setTiebreakerCommittee(address newTiebreakerCommittee) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.setTiebreakerCommittee(newTiebreakerCommittee);
    }

    /// @notice Sets the new value for the tiebreaker activation timeout.
    /// @dev If the Dual Governance system remains out of the `Normal` or `VetoCooldown` state for longer than
    ///     the `tiebreakerActivationTimeout` duration, the tiebreaker committee is allowed to schedule
    ///     submitted proposals.
    /// @param newTiebreakerActivationTimeout The new duration for the tiebreaker activation timeout.
    function setTiebreakerActivationTimeout(Duration newTiebreakerActivationTimeout) external {
        _checkCallerIsAdminExecutor();
        _tiebreaker.setTiebreakerActivationTimeout(
            MIN_TIEBREAKER_ACTIVATION_TIMEOUT, newTiebreakerActivationTimeout, MAX_TIEBREAKER_ACTIVATION_TIMEOUT
        );
    }

    /// @notice Allows the tiebreaker committee to resume a paused sealable contract when the system is in a tie state.
    /// @param sealable The address of the sealable contract to be resumed.
    function tiebreakerResumeSealable(address sealable) external {
        _tiebreaker.checkCallerIsTiebreakerCommittee();
        _stateMachine.activateNextState();
        _tiebreaker.checkTie(_stateMachine.getPersistedState(), _stateMachine.normalOrVetoCooldownExitedAt);
        _resealer.resealManager.resume(sealable);
    }

    /// @notice Allows the tiebreaker committee to schedule for execution a submitted proposal when
    ///     the system is in a tie state.
    /// @param proposalId The unique identifier of the proposal to be scheduled.
    function tiebreakerScheduleProposal(uint256 proposalId) external {
        _tiebreaker.checkCallerIsTiebreakerCommittee();
        _stateMachine.activateNextState();
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
        _stateMachine.activateNextState();
        if (_stateMachine.getPersistedState() == State.Normal) {
            revert ResealIsNotAllowedInNormalState();
        }
        _resealer.checkCallerIsResealCommittee();
        _resealer.resealManager.reseal(sealable);
    }

    /// @notice Sets the address of the reseal committee.
    /// @param newResealCommittee The address of the new reseal committee.
    function setResealCommittee(address newResealCommittee) external {
        _checkCallerIsAdminExecutor();
        _resealer.setResealCommittee(newResealCommittee);
    }

    /// @notice Sets the address of the Reseal Manager contract.
    /// @param newResealManager The contract implementing the `IResealManager` interface.
    function setResealManager(IResealManager newResealManager) external {
        _checkCallerIsAdminExecutor();
        _resealer.setResealManager(newResealManager);
    }

    /// @notice Returns the address of the Reseal Manager contract.
    /// @return resealManager The contract implementing the `IResealManager` interface.
    function getResealManager() external view returns (IResealManager) {
        return _resealer.resealManager;
    }

    /// @notice Returns the address of the reseal committee.
    /// @return resealCommittee The address of the reseal committee.
    function getResealCommittee() external view returns (address) {
        return _resealer.resealCommittee;
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
