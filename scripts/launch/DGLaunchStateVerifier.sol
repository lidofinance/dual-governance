// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {Duration} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {IDGLaunchVerifier} from "scripts/launch/interfaces/IDGLaunchVerifier.sol";

contract DGLaunchStateVerifier is IDGLaunchVerifier {
    event DGLaunchConfigurationValidated();

    error EmergencyModeEnabledAfterLaunch();
    error InvalidDGLaunchConfigAddress(string paramName, address expectedValue, address actualValue);
    error InvalidDGLaunchConfigParameter(string paramName, uint256 expectedValue, uint256 actualValue);

    struct ConstructorParams {
        address timelock;
        address dualGovernance;
        address emergencyGovernance;
        address emergencyActivationCommittee;
        address emergencyExecutionCommittee;
        Timestamp emergencyProtectionEndDate;
        Duration emergencyModeDuration;
        uint256 proposalsCount;
    }

    address public immutable TIMELOCK;
    address public immutable DUAL_GOVERNANCE;
    address public immutable EMERGENCY_GOVERNANCE;
    address public immutable EMERGENCY_ACTIVATION_COMMITTEE;
    address public immutable EMERGENCY_EXECUTION_COMMITTEE;
    Timestamp public immutable EMERGENCY_PROTECTION_END_DATE;
    Duration public immutable EMERGENCY_MODE_DURATION;
    uint256 public immutable PROPOSALS_COUNT;

    constructor(ConstructorParams memory params) {
        TIMELOCK = params.timelock;
        DUAL_GOVERNANCE = params.dualGovernance;
        EMERGENCY_GOVERNANCE = params.emergencyGovernance;
        EMERGENCY_ACTIVATION_COMMITTEE = params.emergencyActivationCommittee;
        EMERGENCY_EXECUTION_COMMITTEE = params.emergencyExecutionCommittee;
        EMERGENCY_PROTECTION_END_DATE = params.emergencyProtectionEndDate;
        EMERGENCY_MODE_DURATION = params.emergencyModeDuration;
        PROPOSALS_COUNT = params.proposalsCount;
    }

    function verify() external {
        IEmergencyProtectedTimelock timelockInstance = IEmergencyProtectedTimelock(TIMELOCK);

        if (timelockInstance.isEmergencyModeActive() == true) {
            revert EmergencyModeEnabledAfterLaunch();
        }

        if (timelockInstance.getGovernance() != DUAL_GOVERNANCE) {
            revert InvalidDGLaunchConfigAddress({
                paramName: "getGovernance()",
                expectedValue: DUAL_GOVERNANCE,
                actualValue: timelockInstance.getGovernance()
            });
        }

        if (timelockInstance.getEmergencyGovernance() != EMERGENCY_GOVERNANCE) {
            revert InvalidDGLaunchConfigAddress({
                paramName: "getEmergencyGovernance()",
                expectedValue: EMERGENCY_GOVERNANCE,
                actualValue: timelockInstance.getEmergencyGovernance()
            });
        }

        if (timelockInstance.getEmergencyActivationCommittee() != EMERGENCY_ACTIVATION_COMMITTEE) {
            revert InvalidDGLaunchConfigAddress({
                paramName: "getEmergencyActivationCommittee()",
                expectedValue: EMERGENCY_ACTIVATION_COMMITTEE,
                actualValue: timelockInstance.getEmergencyActivationCommittee()
            });
        }

        if (timelockInstance.getEmergencyExecutionCommittee() != EMERGENCY_EXECUTION_COMMITTEE) {
            revert InvalidDGLaunchConfigAddress({
                paramName: "getEmergencyExecutionCommittee()",
                expectedValue: EMERGENCY_EXECUTION_COMMITTEE,
                actualValue: timelockInstance.getEmergencyExecutionCommittee()
            });
        }

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
            timelockInstance.getEmergencyProtectionDetails();

        if (details.emergencyProtectionEndsAfter != EMERGENCY_PROTECTION_END_DATE) {
            revert InvalidDGLaunchConfigParameter({
                paramName: "getEmergencyProtectionDetails().emergencyProtectionEndsAfter",
                expectedValue: EMERGENCY_PROTECTION_END_DATE.toSeconds(),
                actualValue: details.emergencyProtectionEndsAfter.toSeconds()
            });
        }

        if (details.emergencyModeDuration != EMERGENCY_MODE_DURATION) {
            revert InvalidDGLaunchConfigParameter({
                paramName: "getEmergencyProtectionDetails().emergencyModeDuration",
                expectedValue: EMERGENCY_MODE_DURATION.toSeconds(),
                actualValue: details.emergencyModeDuration.toSeconds()
            });
        }

        if (details.emergencyModeEndsAfter != Timestamps.ZERO) {
            revert InvalidDGLaunchConfigParameter({
                paramName: "getEmergencyProtectionDetails().emergencyModeEndsAfter",
                expectedValue: 0,
                actualValue: details.emergencyModeEndsAfter.toSeconds()
            });
        }

        if (timelockInstance.getProposalsCount() != PROPOSALS_COUNT) {
            revert InvalidDGLaunchConfigParameter({
                paramName: "getProposalsCount()",
                expectedValue: PROPOSALS_COUNT,
                actualValue: timelockInstance.getProposalsCount()
            });
        }

        emit DGLaunchConfigurationValidated();
    }
}
