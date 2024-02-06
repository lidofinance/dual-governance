// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";

import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";
import {ScheduledCallsBatches, ScheduledCallsBatch, ExecutorCall} from "./libraries/ScheduledCalls.sol";

contract EmergencyProtectedTimelock is ITimelock {
    using SafeCast for uint256;
    using ScheduledCallsBatches for ScheduledCallsBatches.State;
    using EmergencyProtection for EmergencyProtection.State;

    error NotGovernance(address sender);
    error NotAdminExecutor(address sender);

    event DelaySet(uint256 delay);
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

    // executes call immediately when the delay for scheduled calls is set to 0
    function relay(address executor, ExecutorCall[] calldata calls) external onlyGovernance {
        _scheduledCalls.relay(executor, calls);
    }

    // schedules call to be executed after some delay
    function schedule(
        uint256 batchId,
        address executor,
        ExecutorCall[] calldata calls
    ) external onlyGovernance {
        _scheduledCalls.add(batchId, executor, calls);
    }

    // executes scheduled call
    function execute(uint256 batchId) external {
        if (_emergencyProtection.isActive()) {
            _emergencyProtection.validateIsCommittee(msg.sender);
        }
        _scheduledCalls.execute(batchId);
    }

    function removeCanceledCallsBatch(uint256 batchId) external {
        _scheduledCalls.removeCanceled(batchId);
    }

    function setGovernance(address governance, uint256 delay) external onlyAdminExecutor {
        _setGovernance(governance, delay);
    }

    function transferExecutorOwnership(address executor, address owner) external onlyAdminExecutor {
        IOwnable(executor).transferOwnership(owner);
    }

    function setEmergencyProtection(
        address committee,
        uint256 lifetime,
        uint256 duration
    ) external onlyAdminExecutor {
        _emergencyProtection.setup(committee, lifetime, duration);
    }

    function emergencyModeActivate() external {
        _emergencyProtection.activate();
    }

    function emergencyModeDeactivate() external {
        if (_emergencyProtection.isActive()) {
            _assertAdminExecutor();
        }
        _scheduledCalls.cancelAll();
        _emergencyProtection.deactivate();
    }

    function emergencyResetGovernance() external {
        _scheduledCalls.cancelAll();
        _emergencyProtection.reset();
        _setGovernance(EMERGENCY_GOVERNANCE, 0);
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

    function getScheduledCallBatches()
        external
        view
        returns (ScheduledCallsBatch[] memory batches)
    {
        batches = _scheduledCalls.all();
    }

    function getScheduledCallsBatch(
        uint256 batchId
    ) external view returns (ScheduledCallsBatch memory batch) {
        batch = _scheduledCalls.get(batchId);
    }

    function getIsExecutable(uint256 batchId) external view returns (bool isExecutable) {
        isExecutable = _scheduledCalls.isExecutable(batchId);
    }

    function getIsCanceled(uint256 batchId) external view returns (bool isExecutable) {
        isExecutable = _scheduledCalls.isCanceled(batchId);
    }

    struct EmergencyState {
        bool isActive;
        address committee;
        uint256 protectedTill;
        uint256 emergencyModeEndsAfter;
        uint256 emergencyModeDuration;
    }

    function getEmergencyState() external view returns (EmergencyState memory res) {
        EmergencyProtection.State memory state = _emergencyProtection;
        res.isActive = _emergencyProtection.isActive();
        res.committee = state.committee;
        res.protectedTill = state.protectedTill;
        res.emergencyModeEndsAfter = state.emergencyModeEndsAfter;
        res.emergencyModeDuration = state.emergencyModeDuration;
    }

    function _setGovernance(address governance, uint256 delay) internal {
        address prevGovernance = _governance;
        uint256 prevDelay = _scheduledCalls.delay;
        if (prevGovernance != governance) {
            _governance = governance;
            emit GovernanceSet(governance);
        }
        if (prevDelay != delay) {
            _scheduledCalls.delay = delay.toUint32();
            emit DelaySet(delay);
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
