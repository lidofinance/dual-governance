// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";

import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";
import {ScheduledCalls, ExecutorCall, ScheduledExecutorCallsBatch} from "./libraries/ScheduledCalls.sol";

contract EmergencyProtectedTimelock is ITimelock {
    using SafeCast for uint256;
    using ScheduledCalls for ScheduledCalls.State;
    using EmergencyProtection for EmergencyProtection.State;

    error NotGovernance(address sender);
    error NotAdminExecutor(address sender);

    event DelaySet(uint256 timelock);
    event GovernanceSet(address indexed governance);

    address public immutable ADMIN_EXECUTOR;
    address public immutable EMERGENCY_GOVERNANCE;

    uint40 internal _delay;
    address internal _governance;

    ScheduledCalls.State internal _scheduledCalls;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(address adminExecutor, address emergencyGovernance) {
        ADMIN_EXECUTOR = adminExecutor;
        EMERGENCY_GOVERNANCE = emergencyGovernance;
    }

    function forward(uint256 batchId, address executor, ExecutorCall[] calldata calls) external {
        if (msg.sender != _governance) {
            revert NotGovernance(msg.sender);
        }
        if (_delay == 0) {
            _scheduledCalls.forward(batchId, executor, calls);
        } else {
            _scheduledCalls.add(batchId, executor, _delay, calls);
        }
    }

    function execute(uint256 batchId) external returns (bytes[] memory) {
        if (_emergencyProtection.isActive()) {
            _emergencyProtection.validateIsCommittee(msg.sender);
        }
        return _scheduledCalls.execute(batchId);
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
        _emergencyProtection.deactivate();
        _scheduledCalls.cancelAll();
    }

    function emergencyResetGovernance() external {
        _emergencyProtection.reset();
        _scheduledCalls.cancelAll();
        _setGovernance(EMERGENCY_GOVERNANCE, 0);
    }

    function getDelay() external view returns (uint256 delay) {
        delay = _delay;
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
        returns (ScheduledExecutorCallsBatch[] memory batches)
    {
        batches = _scheduledCalls.all();
    }

    function getScheduledCallsBatch(
        uint256 batchId
    ) external view returns (ScheduledExecutorCallsBatch memory batch) {
        batch = _scheduledCalls.get(batchId);
    }

    function getIsExecutable(uint256 batchId) external view returns (bool isExecutable) {
        isExecutable = _scheduledCalls.isExecutable(batchId);
    }

    function getIsCanceled(uint256 batchId) external view returns (bool isExecutable) {
        isExecutable = _scheduledCalls.isCanceled(batchId);
    }

    function getEmergencyState()
        external
        view
        returns (
            bool isActive,
            address committee,
            uint256 protectedTill,
            uint256 emergencyModeEndsAfter,
            uint256 emergencyModeDuration
        )
    {
        EmergencyProtection.State memory state = _emergencyProtection;
        isActive = _emergencyProtection.isActive();
        committee = state.committee;
        protectedTill = state.protectedTill;
        emergencyModeEndsAfter = state.emergencyModeEndsAfter;
        emergencyModeDuration = state.emergencyModeDuration;
    }

    function _setGovernance(address governance, uint256 delay) internal {
        address prevGovernance = _governance;
        uint256 prevTimelock = _delay;
        if (prevGovernance != governance) {
            _governance = governance;
            emit GovernanceSet(governance);
        }
        if (prevTimelock != delay) {
            _delay = delay.toUint40();
            emit DelaySet(delay);
        }
    }

    modifier onlyAdminExecutor() {
        if (msg.sender != ADMIN_EXECUTOR) {
            revert NotAdminExecutor(msg.sender);
        }
        _;
    }
}
