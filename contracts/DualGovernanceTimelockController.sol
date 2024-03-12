// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITimelock, ITimelockController} from "./interfaces/ITimelock.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {DualGovernanceState, Status as DualGovernanceStatus} from "./libraries/DualGovernanceState.sol";

contract DualGovernanceTimelockController is ITimelockController, ConfigurationProvider {
    using Proposers for Proposers.State;
    using DualGovernanceState for DualGovernanceState.State;

    error NotTie();
    error NotTimelock(address account);
    error ProposalsCreationSuspended();
    error ProposalsAdoptionSuspended();

    ITimelock public immutable TIMELOCK;

    address internal _tiebreakCommittee;
    Proposers.State internal _proposers;
    DualGovernanceState.State internal _state;

    constructor(address config, address timelock, address escrowMasterCopy) ConfigurationProvider(config) {
        TIMELOCK = ITimelock(timelock);
        _state.initialize(escrowMasterCopy);
    }

    function activateNextState() external {
        _state.activateNextState(CONFIG);
    }

    function handleProposalCreation(address sender, address executor) external {
        _checkTimelock(msg.sender);
        _proposers.checkExecutor(sender, executor);
        _state.activateNextState(CONFIG);
        if (!_state.isProposalsCreationAllowed()) {
            revert ProposalsCreationSuspended();
        }
        _state.setLastProposalCreationTimestamp();
    }

    function handleProposalAdoption(address sender) external {
        if (sender == _tiebreakCommittee) {
            if (!_state.isTiebreak(CONFIG)) {
                revert NotTie();
            } else {
                return;
            }
        } else if (msg.sender != address(TIMELOCK)) {
            revert NotTimelock(sender);
        }
        _state.activateNextState(CONFIG);
        if (!_state.isProposalsAdoptionAllowed()) {
            revert ProposalsAdoptionSuspended();
        }
    }

    function handleProposalsRevocation(address sender) external {
        _checkTimelock(msg.sender);
        _proposers.checkAdminProposer(CONFIG, sender);
        _state.activateNextState(CONFIG);
    }

    function setTiebreakCommittee(address committee) external {
        _checkAdminExecutor(msg.sender);
        _tiebreakCommittee = committee;
    }

    // ---
    // View Methods
    // ---

    function currentState() external view returns (DualGovernanceStatus) {
        return _state.currentState();
    }

    function signallingEscrow() external view returns (address) {
        return address(_state.signallingEscrow);
    }

    function rageQuitEscrow() external view returns (address) {
        return address(_state.rageQuitEscrow);
    }

    function isTiebreak() external view returns (bool) {
        return _state.isTiebreak(CONFIG);
    }

    function isProposalsCreationAllowed() external view returns (bool) {
        return _state.isProposalsCreationAllowed();
    }

    function isProposalsAdoptionAllowed() external view returns (bool) {
        return _state.isProposalsAdoptionAllowed();
    }

    function getVetoSignallingState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt)
    {
        (isActive, duration, activatedAt, enteredAt) = _state.getVetoSignallingState(CONFIG);
    }

    function getVetoSignallingDeactivationState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 enteredAt)
    {
        (isActive, duration, enteredAt) = _state.getVetoSignallingDeactivationState(CONFIG);
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
    // Internal Helper Methods
    // ---

    function _checkTimelock(address account) internal view {
        if (account != address(TIMELOCK)) {
            revert NotTimelock(account);
        }
    }
}
