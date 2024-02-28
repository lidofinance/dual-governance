// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    DualGovernanceState,
    DualGovernanceConfig,
    Status as DualGovernanceStatus
} from "./libraries/DualGovernanceState.sol";

interface ITimelock {
    function isAdminExecutor(address account) external view returns (bool);
}

contract DualGovernanceTimelockController {
    using DualGovernanceState for DualGovernanceState.State;

    error NotTimelock(address account);
    error NotAdminExecutor(address account);
    error ProposalsCreationSuspended();
    error ProposalsAdoptionSuspended();

    ITimelock public immutable TIMELOCK;
    DualGovernanceState.State internal _state;

    constructor(address timelock, address signalingEscrow_, DualGovernanceConfig memory config_) {
        TIMELOCK = ITimelock(timelock);
        _state.setConfig(config_);
        _state.setEscrow(signalingEscrow_);
    }

    function config() external view returns (DualGovernanceConfig memory) {
        return _state.getConfig();
    }

    function currentState() external view returns (DualGovernanceStatus) {
        return _state.status;
    }

    function setConfig(DualGovernanceConfig memory config_) external {
        _checkAdminExecutor(msg.sender);
        _state.setConfig(config_);
    }

    function setSealableWithdrawalBlockers(address[] calldata sealableWithdrawalBlockers_) external {
        _checkAdminExecutor(msg.sender);
        _state.setSealableWithdrawalBlockers(sealableWithdrawalBlockers_);
    }

    function signalingEscrow() external view returns (address) {
        return address(_state.signallingEscrow);
    }

    function rageQuitEscrow() external view returns (address) {
        return address(_state.rageQuitEscrow);
    }

    function isLocked() external view returns (bool) {
        return _state.isDeadLockedOrFrozen();
    }

    function activateNextState() external {
        _state.activateNextState();
    }

    function isProposalsCreationAllowed() external view returns (bool) {
        return _state.isProposalsCreationAllowed();
    }

    function isProposalsAdoptionAllowed() external view returns (bool) {
        return _state.isProposalsAdoptionAllowed();
    }

    function handleProposalCreation() external {
        _checkTimelock(msg.sender);
        _state.activateNextState();
        if (!_state.isProposalsCreationAllowed()) {
            revert ProposalsCreationSuspended();
        }
    }

    function handleProposalAdoption() external {
        _checkTimelock(msg.sender);
        _state.activateNextState();
        if (!_state.isProposalsAdoptionAllowed()) {
            revert ProposalsAdoptionSuspended();
        }
    }

    function handleProposalsRevocation() external {
        _checkTimelock(msg.sender);
        _state.activateNextState();
        _state.haltProposalsCreation();
    }

    function _checkTimelock(address account) internal view {
        if (account != address(TIMELOCK)) {
            revert NotTimelock(account);
        }
    }

    function _checkAdminExecutor(address account) internal view {
        if (!TIMELOCK.isAdminExecutor(account)) {
            revert NotAdminExecutor(account);
        }
    }
}
