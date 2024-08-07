// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IDualGovernance} from "./interfaces/IDualGovernance.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";

import {Tiebreaker} from "./libraries/Tiebreaker.sol";
import {ExternalCall} from "./libraries/ExternalCalls.sol";
import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {State, DualGovernanceStateMachine} from "./libraries/DualGovernanceStateMachine.sol";
import {IDualGovernanceConfigProvider} from "./DualGovernanceConfigProvider.sol";

import {Escrow} from "./Escrow.sol";

contract DualGovernance is IDualGovernance {
    using Proposers for Proposers.State;
    using Tiebreaker for Tiebreaker.Context;
    using DualGovernanceStateMachine for DualGovernanceStateMachine.Context;

    // ---
    // Errors
    // ---

    error InvalidConfigProvider(IDualGovernanceConfigProvider configProvider);
    error NotResealCommittee(address account);
    error ProposalSubmissionBlocked();
    error InvalidAdminExecutor(address value);
    error ProposalSchedulingBlocked(uint256 proposalId);
    error ResealIsNotAllowedInNormalState();

    // ---
    // Events
    // ---

    event EscrowMasterCopyDeployed(address escrowMasterCopy);
    event ConfigProviderSet(IDualGovernanceConfigProvider newConfigProvider);

    // ---
    // Tiebreaker Sanity Check Param Immutables
    // ---

    struct SanityCheckParams {
        Duration minTiebreakerActivationTimeout;
        Duration maxTiebreakerActivationTimeout;
        uint256 maxSealableWithdrawalBlockersCount;
    }

    Duration public immutable MIN_TIEBREAKER_ACTIVATION_TIMEOUT;
    Duration public immutable MAX_TIEBREAKER_ACTIVATION_TIMEOUT;
    uint256 public immutable MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT;

    // ---
    // External Parts Immutables

    ITimelock public immutable TIMELOCK;
    IResealManager public immutable RESEAL_MANAGER;
    address public immutable ESCROW_MASTER_COPY;

    // ---
    // Aspects
    // ---

    Proposers.State internal _proposers;
    Tiebreaker.Context internal _tiebreaker;
    DualGovernanceStateMachine.Context internal _stateMachine;

    // ---
    // Standalone State Variables
    // ---
    IDualGovernanceConfigProvider internal _configProvider;
    address internal _resealCommittee;

    constructor(
        ITimelock timelock,
        IResealManager resealManager,
        IDualGovernanceConfigProvider configProvider,
        SanityCheckParams memory dualGovernanceSanityCheckParams,
        Escrow.SanityCheckParams memory escrowSanityCheckParams,
        Escrow.ProtocolDependencies memory escrowProtocolDependencies
    ) {
        TIMELOCK = timelock;
        RESEAL_MANAGER = resealManager;

        MIN_TIEBREAKER_ACTIVATION_TIMEOUT = dualGovernanceSanityCheckParams.minTiebreakerActivationTimeout;
        MAX_TIEBREAKER_ACTIVATION_TIMEOUT = dualGovernanceSanityCheckParams.maxTiebreakerActivationTimeout;
        MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = dualGovernanceSanityCheckParams.maxSealableWithdrawalBlockersCount;

        _setConfigProvider(configProvider);

        ESCROW_MASTER_COPY = address(new Escrow(this, escrowSanityCheckParams, escrowProtocolDependencies));
        emit EscrowMasterCopyDeployed(ESCROW_MASTER_COPY);

        _stateMachine.initialize(configProvider.getDualGovernanceConfig(), ESCROW_MASTER_COPY);
    }

    // ---
    // Proposals Flow
    // ---

    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId) {
        _stateMachine.activateNextState(_configProvider.getDualGovernanceConfig(), ESCROW_MASTER_COPY);
        _proposers.checkProposer(msg.sender);
        if (!_stateMachine.canSubmitProposal()) {
            revert ProposalSubmissionBlocked();
        }
        Proposer memory proposer = _proposers.get(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function scheduleProposal(uint256 proposalId) external {
        _stateMachine.activateNextState(_configProvider.getDualGovernanceConfig(), ESCROW_MASTER_COPY);
        ( /* id */ , /* status */, /* executor */, Timestamp submittedAt, /* scheduledAt */ ) =
            TIMELOCK.getProposalInfo(proposalId);
        if (!_stateMachine.canScheduleProposal(submittedAt)) {
            revert ProposalSchedulingBlocked(proposalId);
        }
        TIMELOCK.schedule(proposalId);
    }

    function cancelAllPendingProposals() external {
        _proposers.checkAdminProposer(TIMELOCK.getAdminExecutor(), msg.sender);
        TIMELOCK.cancelAllNonExecutedProposals();
    }

    function canSubmitProposal() public view returns (bool) {
        return _stateMachine.canSubmitProposal();
    }

    function canScheduleProposal(uint256 proposalId) external view returns (bool) {
        ( /* id */ , /* status */, /* executor */, Timestamp submittedAt, /* scheduledAt */ ) =
            TIMELOCK.getProposalInfo(proposalId);
        return _stateMachine.canScheduleProposal(submittedAt) && TIMELOCK.canSchedule(proposalId);
    }

    // ---
    // Dual Governance State
    // ---

    function activateNextState() external {
        _stateMachine.activateNextState(_configProvider.getDualGovernanceConfig(), ESCROW_MASTER_COPY);
    }

    function setConfigProvider(IDualGovernanceConfigProvider newConfigProvider) external {
        _checkAdminExecutor(msg.sender);
        _setConfigProvider(newConfigProvider);

        /// @dev the minAssetsLockDuration is kept as a storage variable in the signalling Escrow instance
        /// to sync the new value with current signalling escrow, it's value must be manually updated
        _stateMachine.signallingEscrow.setMinAssetsLockDuration(
            newConfigProvider.getDualGovernanceConfig().minAssetsLockDuration
        );
    }

    function getConfigProvider() external view returns (IDualGovernanceConfigProvider) {
        return _configProvider;
    }

    function getVetoSignallingEscrow() external view returns (address) {
        return address(_stateMachine.signallingEscrow);
    }

    function getRageQuitEscrow() external view returns (address) {
        return address(_stateMachine.rageQuitEscrow);
    }

    function getCurrentState() external view returns (State currentState) {
        currentState = _stateMachine.getCurrentState();
    }

    function getCurrentStateContext() external view returns (DualGovernanceStateMachine.Context memory) {
        return _stateMachine.getCurrentContext();
    }

    function getDynamicDelayDuration() external view returns (Duration) {
        return _stateMachine.getDynamicDelayDuration(_configProvider.getDualGovernanceConfig());
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
        _proposers.unregister(TIMELOCK.getAdminExecutor(), proposer);
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

    function addTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker) external {
        _checkAdminExecutor(msg.sender);
        _tiebreaker.addSealableWithdrawalBlocker(sealableWithdrawalBlocker, MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT);
    }

    function removeTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker) external {
        _checkAdminExecutor(msg.sender);
        _tiebreaker.removeSealableWithdrawalBlocker(sealableWithdrawalBlocker);
    }

    function setTiebreakerCommittee(address tiebreakerCommittee) external {
        _checkAdminExecutor(msg.sender);
        _tiebreaker.setTiebreakerCommittee(tiebreakerCommittee);
    }

    function setTiebreakerActivationTimeout(Duration tiebreakerActivationTimeout) external {
        _checkAdminExecutor(msg.sender);
        _tiebreaker.setTiebreakerActivationTimeout(
            MIN_TIEBREAKER_ACTIVATION_TIMEOUT, tiebreakerActivationTimeout, MAX_TIEBREAKER_ACTIVATION_TIMEOUT
        );
    }

    function tiebreakerResumeSealable(address sealable) external {
        _tiebreaker.checkTiebreakerCommittee(msg.sender);
        _tiebreaker.checkTie(_stateMachine.getCurrentState(), _stateMachine.getNormalOrVetoCooldownStateExitedAt());
        RESEAL_MANAGER.resume(sealable);
    }

    function tiebreakerScheduleProposal(uint256 proposalId) external {
        _tiebreaker.checkTiebreakerCommittee(msg.sender);
        _tiebreaker.checkTie(_stateMachine.getCurrentState(), _stateMachine.getNormalOrVetoCooldownStateExitedAt());
        TIMELOCK.schedule(proposalId);
    }

    struct TiebreakerState {
        address tiebreakerCommittee;
        Duration tiebreakerActivationTimeout;
        address[] sealableWithdrawalBlockers;
    }

    function getTiebreakerState() external view returns (TiebreakerState memory tiebreakerState) {
        (
            tiebreakerState.tiebreakerCommittee,
            tiebreakerState.tiebreakerActivationTimeout,
            tiebreakerState.sealableWithdrawalBlockers
        ) = _tiebreaker.getTiebreakerInfo();
    }

    // ---
    // Reseal executor
    // ---

    function resealSealable(address sealable) external {
        if (msg.sender != _resealCommittee) {
            revert NotResealCommittee(msg.sender);
        }
        if (_stateMachine.getCurrentState() == State.Normal) {
            revert ResealIsNotAllowedInNormalState();
        }
        RESEAL_MANAGER.reseal(sealable);
    }

    function setResealCommittee(address resealCommittee) external {
        _checkAdminExecutor(msg.sender);
        _resealCommittee = resealCommittee;
    }

    // ---
    // Private methods
    // ---

    function _setConfigProvider(IDualGovernanceConfigProvider newConfigProvider) internal {
        if (address(newConfigProvider) == address(0)) {
            revert InvalidConfigProvider(newConfigProvider);
        }

        if (newConfigProvider == _configProvider) {
            return;
        }

        _configProvider = IDualGovernanceConfigProvider(newConfigProvider);
        emit ConfigProviderSet(newConfigProvider);
    }

    function _checkAdminExecutor(address account) internal view {
        if (TIMELOCK.getAdminExecutor() != account) {
            revert InvalidAdminExecutor(account);
        }
    }
}
