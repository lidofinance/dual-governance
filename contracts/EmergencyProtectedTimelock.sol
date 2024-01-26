// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ScheduledCalls, ExecutorCall, ScheduledExecutorCallsBatch} from "./libraries/ScheduledCalls.sol";
import {IOwnable} from "./interfaces/IOwnable.sol";

contract EmergencyProtectedTimelock {
    using SafeCast for uint256;
    using ScheduledCalls for ScheduledCalls.State;

    error NotGovernance(address sender);
    error NotAdminExecutor(address sender);
    error NotEmergencyCommittee(address sender);
    error EmergencyCommitteeExpired();
    error EmergencyModeNotEntered();
    error EmergencyPeriodFinished();
    error EmergencyPeriodNotFinished();

    event TimelockSet(uint256 timelock);
    event EmergencyCommitteeSet(address indexed guardian);
    event GovernanceSet(address indexed governance);
    event EmergencyCommitteeActiveTillSet(uint256 guardedTill);
    event EmergencyModeEntered();
    event EmergencyModeExited();
    event EmergencyDurationSet(uint256 emergencyModeDuration);

    address public immutable ADMIN_EXECUTOR;
    address public immutable EMERGENCY_GOVERNANCE;

    address internal _governance;
    uint40 internal _timelock;

    // has rights to activate emergency mode
    address internal _emergencyCommittee;
    // during this period of time committee may activate the emergency mode
    uint40 internal _emergencyCommitteeActiveTill;
    // TODO: limit the range of this variable to some adequate values
    uint40 internal _emergencyModeDuration;
    // when the emergency mode activated, this is the start of the emergency mode
    uint40 internal _emergencyModeEnteredAt;

    ScheduledCalls.State internal _scheduledCalls;

    constructor(address adminExecutor, address emergencyGovernance) {
        ADMIN_EXECUTOR = adminExecutor;
        EMERGENCY_GOVERNANCE = emergencyGovernance;
    }

    function schedule(
        uint256 batchId,
        address executor,
        ExecutorCall[] calldata calls
    ) external onlyGovernance {
        _scheduledCalls.schedule(batchId, executor, _timelock, calls);
    }

    function execute(uint256 batchId) external returns (bytes[] memory) {
        if (_isEmergencyModeActive() && msg.sender != _emergencyCommittee) {
            revert NotEmergencyCommittee(msg.sender);
        }
        return _scheduledCalls.execute(batchId);
    }

    function setGovernance(address governance, uint256 timelock) external onlyAdminExecutor {
        _setGovernance(governance, timelock);
    }

    function setEmergencyCommittee(
        address committee,
        uint256 lifetime,
        uint256 duration
    ) external onlyAdminExecutor {
        _setEmergencyCommittee(committee, lifetime, duration);
    }

    function transferExecutorOwnership(address executor, address owner) external onlyAdminExecutor {
        IOwnable(executor).transferOwnership(owner);
    }

    function enterEmergencyMode() external {
        if (msg.sender != _emergencyCommittee) {
            revert NotEmergencyCommittee(msg.sender);
        }
        if (block.timestamp >= _emergencyCommitteeActiveTill) {
            revert EmergencyCommitteeExpired();
        }
        _scheduledCalls.unscheduleAll();
        _emergencyModeEnteredAt = block.timestamp.toUint40();
        emit EmergencyModeEntered();
    }

    function exitEmergencyMode() external {
        uint256 emergencyModeEnteredAt = _emergencyModeEnteredAt;
        if (emergencyModeEnteredAt == 0) {
            revert EmergencyModeNotEntered();
        }
        if (
            msg.sender != _emergencyCommittee &&
            block.timestamp < emergencyModeEnteredAt + _emergencyModeDuration
        ) {
            revert EmergencyPeriodNotFinished();
        }
        _exitEmergencyMode();
        emit EmergencyModeExited();
    }

    function emergencyResetGovernance() external {
        uint256 emergencyModeEnteredAt = _emergencyModeEnteredAt;
        if (emergencyModeEnteredAt == 0) {
            revert EmergencyModeNotEntered();
        }
        if (msg.sender != _emergencyCommittee) {
            revert NotEmergencyCommittee(msg.sender);
        }
        if (block.timestamp >= _emergencyCommitteeActiveTill) {
            revert EmergencyCommitteeExpired();
        }
        if (block.timestamp > emergencyModeEnteredAt + _emergencyModeDuration) {
            revert EmergencyPeriodFinished();
        }
        _exitEmergencyMode();
        _setGovernance(EMERGENCY_GOVERNANCE, 0);
    }

    function removeCanceledCalls(uint256 batchId) external {
        _scheduledCalls.removeCanceled(batchId);
    }

    function getGovernance() external view returns (address governance) {
        governance = _governance;
    }

    function getScheduledCalls(
        uint256 batchId
    ) external view returns (ScheduledExecutorCallsBatch memory batch) {
        batch = _scheduledCalls.get(batchId);
    }

    function getEmergencyCommittee() external view returns (address emergencyCommittee) {
        emergencyCommittee = _emergencyCommittee;
    }

    function getEmergencyModeState()
        external
        view
        returns (bool isActive, uint256 start, uint256 end)
    {
        start = _emergencyModeEnteredAt;
        if (start > 0) {
            end = start + _emergencyModeDuration;
            isActive = block.timestamp >= start && block.timestamp < end;
        }
    }

    function _exitEmergencyMode() internal {
        _scheduledCalls.unscheduleAll();
        _setEmergencyCommittee(address(0), 0, 0);
        _emergencyModeEnteredAt = 0;
        emit EmergencyModeExited();
    }

    function _isEmergencyModeActive() internal view returns (bool) {
        uint256 emergencyModeEnteredAt = _emergencyModeEnteredAt;
        // TODO: check the boundaries properly
        return block.timestamp - emergencyModeEnteredAt <= _emergencyModeDuration;
    }

    function _setGovernance(address governance, uint256 timelock) internal {
        address prevGovernance = _governance;
        uint256 prevTimelock = _timelock;
        if (prevGovernance != governance) {
            _governance = governance;
            emit GovernanceSet(governance);
        }
        if (prevTimelock != timelock) {
            _timelock = timelock.toUint40();
            emit TimelockSet(timelock);
        }
    }

    function _setEmergencyCommittee(
        address emergencyCommittee,
        uint256 emergencyCommitteeLifetime,
        uint256 emergencyModeDuration
    ) internal {
        address prevEmergencyCommittee = _emergencyCommittee;
        if (prevEmergencyCommittee != emergencyCommittee) {
            _emergencyCommittee = emergencyCommittee;
            emit EmergencyCommitteeSet(emergencyCommittee);
        }

        uint256 prevEmergencyCommitteeActiveTill = _emergencyCommitteeActiveTill;
        uint256 emergencyCommitteeActiveTill = block.timestamp + emergencyCommitteeLifetime;

        if (prevEmergencyCommitteeActiveTill != emergencyCommitteeActiveTill) {
            _emergencyCommitteeActiveTill = emergencyCommitteeActiveTill.toUint40();
            emit EmergencyCommitteeActiveTillSet(emergencyCommitteeActiveTill);
        }

        uint256 prevEmergencyModeDuration = _emergencyModeDuration;
        if (prevEmergencyModeDuration != emergencyModeDuration) {
            _emergencyModeDuration = emergencyModeDuration.toUint40();
            emit EmergencyDurationSet(emergencyModeDuration);
        }
    }

    modifier onlyGovernance() {
        if (msg.sender != _governance) {
            revert NotGovernance(msg.sender);
        }
        _;
    }

    modifier onlyAdminExecutor() {
        if (msg.sender != ADMIN_EXECUTOR) {
            revert NotAdminExecutor(msg.sender);
        }
        _;
    }
}
