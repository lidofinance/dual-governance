// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ITimelock, ITimelockController} from "./interfaces/ITimelock.sol";

import {Proposal, Proposals, ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection, EmergencyState} from "./libraries/EmergencyProtection.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

contract EmergencyProtectedTimelock is ITimelock, ConfigurationProvider {
    using Proposals for Proposals.State;
    using EmergencyProtection for EmergencyProtection.State;

    error SchedulingDisabled();
    error UnscheduledExecutionForbidden();

    event ProposalLaunched(address indexed proposer, address indexed executor, uint256 indexed proposalId);

    ITimelockController internal _controller;

    Proposals.State internal _proposals;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(address config) ConfigurationProvider(config) {}

    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _controller.onSubmitProposal(msg.sender, executor);
        newProposalId = _proposals.submit(executor, calls);
        emit ProposalLaunched(msg.sender, executor, newProposalId);
    }

    function execute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeNotActivated();
        _controller.onExecuteProposal(msg.sender, proposalId);
        _proposals.execute(CONFIG, proposalId);
    }

    function cancelAll() external {
        _controller.onCancelAllProposals(msg.sender);
        _proposals.cancelAll();
    }

    function transferExecutorOwnership(address executor, address owner) external {
        _checkAdminExecutor(msg.sender);
        IOwnable(executor).transferOwnership(owner);
    }

    function setController(address controller) external {
        _checkAdminExecutor(msg.sender);
        _setController(controller);
    }

    // ---
    // Emergency Protection Functionality
    // ---

    function emergencyActivate() external {
        _emergencyProtection.checkEmergencyCommittee(msg.sender);
        _emergencyProtection.activate();
    }

    function emergencyExecute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeActivated();
        _emergencyProtection.checkEmergencyCommittee(msg.sender);
        _proposals.execute(CONFIG, proposalId);
    }

    function emergencyDeactivate() external {
        if (!_emergencyProtection.isEmergencyModePassed()) {
            _checkAdminExecutor(msg.sender);
        }
        _emergencyProtection.deactivate();
        _proposals.cancelAll();
    }

    function emergencyReset() external {
        _emergencyProtection.checkEmergencyModeActivated();
        _emergencyProtection.checkEmergencyCommittee(msg.sender);
        _emergencyProtection.reset();
        _proposals.cancelAll();
        _setController(CONFIG.EMERGENCY_CONTROLLER());
    }

    function setEmergencyProtection(
        address committee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration
    ) external {
        _checkAdminExecutor(msg.sender);
        _emergencyProtection.setup(committee, protectionDuration, emergencyModeDuration);
    }

    function isEmergencyProtectionEnabled() external view returns (bool) {
        return _emergencyProtection.isEmergencyProtectionEnabled();
    }

    function getEmergencyState() external view returns (EmergencyState memory res) {
        res = _emergencyProtection.getEmergencyState();
    }

    // ---
    // Timelock View Methods
    // ---

    function getController() external view returns (address) {
        return address(_controller);
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        proposal = _proposals.get(proposalId);
    }

    function getProposalsCount() external view returns (uint256 count) {
        count = _proposals.count();
    }

    // ---
    // Proposals Lifecycle View Methods
    // ---

    function isDelayPassed(uint256 proposalId) external view returns (bool) {
        return block.timestamp >= _proposals.get(proposalId).submittedAt + CONFIG.AFTER_SUBMIT_DELAY();
    }

    function canSubmit() external view returns (bool) {
        return _controller.isProposalsSubmissionAllowed();
    }

    function canExecute(uint256 proposalId) external view returns (bool) {
        return !_emergencyProtection.isEmergencyModeActivated() && _controller.isProposalExecutionAllowed(proposalId)
            && _proposals.canExecute(CONFIG, proposalId);
    }

    function isProposalExecuted(uint256 proposalId) external view returns (bool) {
        return _proposals.isProposalExecuted(proposalId);
    }

    function isProposalSubmitted(uint256 proposalId) external view returns (bool) {
        return _proposals.isProposalSubmitted(proposalId);
    }

    function isProposalCanceled(uint256 proposalId) external view returns (bool) {
        return _proposals.isProposalCanceled(proposalId);
    }

    // ---
    // Internal Methods
    // ---

    function _setController(address controller) internal {
        address prevController = address(_controller);
        if (prevController != controller) {
            _controller = ITimelockController(controller);
        }
    }
}
