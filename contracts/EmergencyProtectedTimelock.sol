// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";

import {EmergencyProtection, EmergencyState} from "./libraries/EmergencyProtection.sol";
import {ScheduledCallsBatches, ScheduledCallsBatch, ExecutorCall} from "./libraries/ScheduledCalls.sol";

contract EmergencyProtectedTimelock is ITimelock {
    using SafeCast for uint256;
    using ScheduledCallsBatches for ScheduledCallsBatches.State;
    using EmergencyProtection for EmergencyProtection.State;

    error NotGovernance(address sender);
    error NotAdminExecutor(address sender);

    event GovernanceSet(address indexed governance);

    address public immutable ADMIN_EXECUTOR;
    address public immutable EMERGENCY_GOVERNANCE;

    address internal _governance;

    ScheduledCallsBatches.State internal _scheduledCalls;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(address adminExecutor, address emergencyGovernance) {
        ADMIN_EXECUTOR = adminExecutor;
        EMERGENCY_GOVERNANCE = emergencyGovernance;
    }

    // executes call immediately when the delay is set to 0
    function relay(address executor, ExecutorCall[] calldata calls) external onlyGovernance {
        _scheduledCalls.relay(executor, calls);
    }

    // schedules call to be executed after some delay
    function schedule(uint256 batchId, address executor, ExecutorCall[] calldata calls) external onlyGovernance {
        _scheduledCalls.schedule(batchId, executor, calls);
    }

    // executes scheduled call
    function execute(uint256 batchId) external {
        // Until the emergency mode is deactivated manually, the execution of the calls is allowed
        // only for the emergency committee
        if (_emergencyProtection.isEmergencyModeActivated()) {
            _emergencyProtection.validateIsCommittee(msg.sender);
        }
        _scheduledCalls.execute(batchId);
    }

    function removeCanceledCallsBatch(uint256 batchId) external {
        _scheduledCalls.removeCanceled(batchId);
    }

    function setGovernanceAndDelay(address governance, uint256 delay) external onlyAdminExecutor {
        _setGovernance(governance);
        _scheduledCalls.setDelay(delay);
    }

    function setDelay(uint256 delay) external onlyAdminExecutor {
        _scheduledCalls.setDelay(delay);
    }

    function transferExecutorOwnership(address executor, address owner) external onlyAdminExecutor {
        IOwnable(executor).transferOwnership(owner);
    }

    function setEmergencyProtection(
        address committee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration
    ) external onlyAdminExecutor {
        _emergencyProtection.setup(committee, protectionDuration, emergencyModeDuration);
    }

    function emergencyModeActivate() external {
        _emergencyProtection.activate();
    }

    function emergencyModeDeactivate() external {
        if (!_emergencyProtection.isEmergencyModePassed()) {
            _assertAdminExecutor();
        }
        _emergencyProtection.deactivate();
        _scheduledCalls.cancelAll();
    }

    function emergencyResetGovernance() external {
        _emergencyProtection.validateIsCommittee(msg.sender);
        _emergencyProtection.reset();
        _scheduledCalls.cancelAll();
        _scheduledCalls.setDelay(0);
        _setGovernance(EMERGENCY_GOVERNANCE);
    }

    function getDelay() external view returns (uint256 delay) {
        delay = _scheduledCalls.delay;
    }

    function getGovernance() external view returns (address governance) {
        governance = _governance;
    }

    function getScheduledCallBatchesCount() external view returns (uint256 count) {
        count = _scheduledCalls.count();
    }

    function getScheduledCallBatches() external view returns (ScheduledCallsBatch[] memory batches) {
        batches = _scheduledCalls.all();
    }

    function getScheduledCallsBatch(uint256 batchId) external view returns (ScheduledCallsBatch memory batch) {
        batch = _scheduledCalls.get(batchId);
    }

    function getIsExecutable(uint256 batchId) external view returns (bool isExecutable) {
        isExecutable = !_emergencyProtection.isEmergencyModeActivated() && _scheduledCalls.isExecutable(batchId);
    }

    function getIsCanceled(uint256 batchId) external view returns (bool isExecutable) {
        isExecutable = _scheduledCalls.isCanceled(batchId);
    }

    function getEmergencyState() external view returns (EmergencyState memory res) {
        res = _emergencyProtection.getEmergencyState();
    }

    function _setGovernance(address governance) internal {
        address prevGovernance = _governance;
        if (prevGovernance != governance) {
            _governance = governance;
            emit GovernanceSet(governance);
        }
    }

    function _assertAdminExecutor() private view {
        if (msg.sender != ADMIN_EXECUTOR) {
            revert NotAdminExecutor(msg.sender);
        }
    }

    modifier onlyAdminExecutor() {
        _assertAdminExecutor();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != _governance) {
            revert NotGovernance(msg.sender);
        }
        _;
    }
}
