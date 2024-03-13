// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";

import {Proposal, Proposals, ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection, EmergencyState} from "./libraries/EmergencyProtection.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

contract EmergencyProtectedTimelock is ITimelock, ConfigurationProvider {
    using Proposals for Proposals.State;
    using EmergencyProtection for EmergencyProtection.State;

    error SchedulingDisabled();
    error NotGovernance(address account, address governance);
    error UnscheduledExecutionForbidden();

    event ProposalLaunched(address indexed proposer, address indexed executor, uint256 indexed proposalId);

    address internal _governance;

    Proposals.State internal _proposals;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(address config) ConfigurationProvider(config) {}

    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _checkGovernance(msg.sender);
        newProposalId = _proposals.submit(executor, calls);
    }

    function execute(uint256 proposalId) external {
        _checkGovernance(msg.sender);
        _emergencyProtection.checkEmergencyModeNotActivated();
        _proposals.execute(CONFIG, proposalId);
    }

    function cancelAll() external {
        _checkGovernance(msg.sender);
        _proposals.cancelAll();
    }

    function transferExecutorOwnership(address executor, address owner) external {
        _checkAdminExecutor(msg.sender);
        IOwnable(executor).transferOwnership(owner);
    }

    function setGovernance(address governance) external {
        _checkAdminExecutor(msg.sender);
        _setGovernance(governance);
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
        // TODO: rename into EMERGENCY_GOVERNANCE
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
        return address(_governance);
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

    function canExecute(uint256 proposalId) external view returns (bool) {
        return !_emergencyProtection.isEmergencyModeActivated() && _proposals.canExecute(CONFIG, proposalId);
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

    function _checkGovernance(address account) internal view {
        if (account != _governance) {
            revert NotGovernance(account, _governance);
        }
    }

    function _setGovernance(address governance) internal {
        address prevGovernance = _governance;
        if (prevGovernance != governance) {
            _governance = governance;
        }
    }
}
