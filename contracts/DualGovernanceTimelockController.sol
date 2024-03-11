// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITimelock, ITimelockController} from "./interfaces/ITimelock.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

import {DualGovernanceState, Status as DualGovernanceStatus} from "./libraries/DualGovernanceState.sol";

contract DualGovernanceTimelockController is ITimelockController, ConfigurationProvider {
    using DualGovernanceState for DualGovernanceState.State;

    error NotTimelock(address account);
    error ProposalsCreationSuspended();
    error ProposalsAdoptionSuspended();

    ITimelock public immutable TIMELOCK;
    DualGovernanceState.State internal _state;

    constructor(address config, address timelock, address escrowMasterCopy) ConfigurationProvider(config) {
        TIMELOCK = ITimelock(timelock);
        _state.initialize(escrowMasterCopy);
    }

    function activateNextState() external {
        _state.activateNextState(CONFIG);
    }

    function handleProposalCreation() external {
        _checkTimelock(msg.sender);
        _state.activateNextState(CONFIG);
        if (!_state.isProposalsCreationAllowed()) {
            revert ProposalsCreationSuspended();
        }
        _state.setLastProposalCreationTimestamp();
    }

    function handleProposalAdoption() external {
        _checkTimelock(msg.sender);
        _state.activateNextState(CONFIG);
        if (!_state.isProposalsAdoptionAllowed()) {
            revert ProposalsAdoptionSuspended();
        }
    }

    function handleProposalsRevocation() external {
        _checkTimelock(msg.sender);
        _state.activateNextState(CONFIG);
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
    // Internal Helper Methods
    // ---

    function _checkTimelock(address account) internal view {
        if (account != address(TIMELOCK)) {
            revert NotTimelock(account);
        }
    }
}
