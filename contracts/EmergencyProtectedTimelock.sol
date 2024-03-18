// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IOwnable} from "./interfaces/IOwnable.sol";

import {Proposal, Proposals, ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection, EmergencyState} from "./libraries/EmergencyProtection.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

contract EmergencyProtectedTimelock is ConfigurationProvider {
    using Proposals for Proposals.State;
    using EmergencyProtection for EmergencyProtection.State;

    error NotGovernance(address account, address governance);
    error SchedulingDisabled();
    error UnscheduledExecutionForbidden();

    event ProposalLaunched(address indexed proposer, address indexed executor, uint256 indexed proposalId);

    address internal _governance;

    Proposals.State internal _proposals;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(address config) ConfigurationProvider(config) {}

    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _checkGovernance(msg.sender);
        newProposalId = _proposals.submit(executor, calls);
        emit ProposalLaunched(msg.sender, executor, newProposalId);
    }

    function schedule(uint256 proposalId) external {
        _checkGovernance(msg.sender);
        _proposals.schedule(proposalId, CONFIG.AFTER_SUBMIT_DELAY());
    }

    function execute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeNotActivated();
        uint256 afterScheduleDelay =
            _emergencyProtection.isEmergencyProtectionEnabled() ? CONFIG.AFTER_SCHEDULE_DELAY() : 0;
        _proposals.execute(proposalId, afterScheduleDelay);
    }

    function cancelAll() external {
        _checkGovernance(msg.sender);
        _proposals.cancelAll();
    }

    function transferExecutorOwnership(address executor, address owner) external {
        _checkAdminExecutor(msg.sender);
        IOwnable(executor).transferOwnership(owner);
    }

    function setGovernance(address newGovernance) external {
        _checkAdminExecutor(msg.sender);
        _setGovernance(newGovernance);
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
        _proposals.execute(proposalId, /* afterScheduleDelay */ 0);
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
        _setGovernance(CONFIG.EMERGENCY_CONTROLLER());
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

    function getGovernance() external view returns (address) {
        return _governance;
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

    function canExecute(uint256 proposalId) external view returns (bool) {
        uint256 afterScheduleDelay =
            _emergencyProtection.isEmergencyProtectionEnabled() ? CONFIG.AFTER_SCHEDULE_DELAY() : 0;
        return !_emergencyProtection.isEmergencyModeActivated() && _proposals.canExecute(proposalId, afterScheduleDelay);
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        return _proposals.canSchedule(proposalId, CONFIG.AFTER_SUBMIT_DELAY());
    }

    // ---
    // Internal Methods
    // ---

    function _setGovernance(address newGovernance) internal {
        address prevController = _governance;
        if (prevController != newGovernance) {
            _governance = newGovernance;
        }
    }

    function _checkGovernance(address account) internal view {
        if (_governance != account) {
            revert NotGovernance(account, _governance);
        }
    }
}
