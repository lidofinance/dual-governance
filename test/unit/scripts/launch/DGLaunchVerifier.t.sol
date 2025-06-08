// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {Duration} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {DGLaunchStateVerifier} from "scripts/launch/DGLaunchStateVerifier.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract DGLaunchVerifierUnitTests is UnitTest {
    address private _timelock = makeAddr("timelock");

    // ---
    // constructor()
    // ---

    function testFuzz_constructor(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount
    ) external {
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        assertEq(verifier.TIMELOCK(), _timelock);
        assertEq(verifier.DUAL_GOVERNANCE(), dualGovernance);
        assertEq(verifier.EMERGENCY_GOVERNANCE(), emergencyGovernance);
        assertEq(verifier.EMERGENCY_ACTIVATION_COMMITTEE(), emergencyActivationCommittee);
        assertEq(verifier.EMERGENCY_EXECUTION_COMMITTEE(), emergencyExecutionCommittee);
        assertEq(verifier.EMERGENCY_PROTECTION_END_DATE(), emergencyProtectionEndDate);
        assertEq(verifier.EMERGENCY_MODE_DURATION(), emergencyModeDuration);
        assertEq(verifier.PROPOSALS_COUNT(), proposalsCount);
    }

    // ---
    // verify()
    // ---

    function testFuzz_verify_HappyPath(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount
    ) external {
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        _mockVerifierCalls({
            isEmergencyModeActive: false,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeEndsAfter: Timestamps.ZERO,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        vm.expectEmit();
        emit DGLaunchStateVerifier.DGLaunchConfigurationValidated();
        verifier.verify();
    }

    function testFuzz_verify_RevertOn_EmergencyModeActive(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount
    ) external {
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        _mockVerifierCalls({
            isEmergencyModeActive: true,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeEndsAfter: Timestamps.ZERO,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        vm.expectRevert(DGLaunchStateVerifier.EmergencyModeEnabledAfterLaunch.selector);
        verifier.verify();
    }

    function testFuzz_verify_RevertOn_InvalidGovernanceAddress(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount
    ) external {
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        address notDG = makeAddr("not a DualGovernance");
        _mockVerifierCalls({
            isEmergencyModeActive: false,
            dualGovernance: notDG,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeEndsAfter: Timestamps.ZERO,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DGLaunchStateVerifier.InvalidDGLaunchConfigAddress.selector, "getGovernance()", dualGovernance, notDG
            )
        );
        verifier.verify();
    }

    function testFuzz_verify_RevertOn_InvalidEmergencyGovernanceAddress(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount
    ) external {
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        address notEmergencyGovernance = makeAddr("not an EmergencyGovernance");
        _mockVerifierCalls({
            isEmergencyModeActive: false,
            dualGovernance: dualGovernance,
            emergencyGovernance: notEmergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeEndsAfter: Timestamps.ZERO,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DGLaunchStateVerifier.InvalidDGLaunchConfigAddress.selector,
                "getEmergencyGovernance()",
                emergencyGovernance,
                notEmergencyGovernance
            )
        );
        verifier.verify();
    }

    function testFuzz_verify_RevertOn_InvalidEmergencyActivationCommitteeAddress(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount
    ) external {
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        address notEmergencyActivationCommittee = makeAddr("not an EmergencyActivationCommittee");
        _mockVerifierCalls({
            isEmergencyModeActive: false,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: notEmergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeEndsAfter: Timestamps.ZERO,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DGLaunchStateVerifier.InvalidDGLaunchConfigAddress.selector,
                "getEmergencyActivationCommittee()",
                emergencyActivationCommittee,
                notEmergencyActivationCommittee
            )
        );
        verifier.verify();
    }

    function testFuzz_verify_RevertOn_InvalidEmergencyExecutionCommitteeAddress(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount
    ) external {
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        address notEmergencyExecutionCommittee = makeAddr("not an EmergencyExecutionCommittee");
        _mockVerifierCalls({
            isEmergencyModeActive: false,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: notEmergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeEndsAfter: Timestamps.ZERO,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DGLaunchStateVerifier.InvalidDGLaunchConfigAddress.selector,
                "getEmergencyExecutionCommittee()",
                emergencyExecutionCommittee,
                notEmergencyExecutionCommittee
            )
        );
        verifier.verify();
    }

    function testFuzz_verify_RevertOn_InvalidEmergencyProtectionEndDate(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount,
        Timestamp invalidEmergencyProtectionEndDate
    ) external {
        vm.assume(invalidEmergencyProtectionEndDate != emergencyProtectionEndDate);
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        _mockVerifierCalls({
            isEmergencyModeActive: false,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: invalidEmergencyProtectionEndDate,
            emergencyModeEndsAfter: Timestamps.ZERO,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DGLaunchStateVerifier.InvalidDGLaunchConfigParameter.selector,
                "getEmergencyProtectionDetails().emergencyProtectionEndsAfter",
                emergencyProtectionEndDate,
                invalidEmergencyProtectionEndDate
            )
        );
        verifier.verify();
    }

    function testFuzz_verify_RevertOn_InvalidEmergencyModeDuration(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount,
        Duration invalidEmergencyModeDuration
    ) external {
        vm.assume(invalidEmergencyModeDuration != emergencyModeDuration);
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        _mockVerifierCalls({
            isEmergencyModeActive: false,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeEndsAfter: Timestamps.ZERO,
            emergencyModeDuration: invalidEmergencyModeDuration,
            proposalsCount: proposalsCount
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DGLaunchStateVerifier.InvalidDGLaunchConfigParameter.selector,
                "getEmergencyProtectionDetails().emergencyModeDuration",
                emergencyModeDuration,
                invalidEmergencyModeDuration
            )
        );
        verifier.verify();
    }

    function testFuzz_verify_RevertOn_InvalidEmergencyModeEndDate(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount,
        Timestamp invalidEmergencyModeEndsAfter
    ) external {
        vm.assume(invalidEmergencyModeEndsAfter != Timestamps.ZERO);
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        _mockVerifierCalls({
            isEmergencyModeActive: false,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeEndsAfter: invalidEmergencyModeEndsAfter,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DGLaunchStateVerifier.InvalidDGLaunchConfigParameter.selector,
                "getEmergencyProtectionDetails().emergencyModeEndsAfter",
                0,
                invalidEmergencyModeEndsAfter
            )
        );
        verifier.verify();
    }

    function testFuzz_verify_RevertOn_IncorrectProposalsCount(
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Duration emergencyModeDuration,
        uint256 proposalsCount,
        uint256 invalidProposalsCount
    ) external {
        vm.assume(invalidProposalsCount != proposalsCount);
        DGLaunchStateVerifier.ConstructorParams memory params = DGLaunchStateVerifier.ConstructorParams({
            timelock: _timelock,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: proposalsCount
        });

        DGLaunchStateVerifier verifier = new DGLaunchStateVerifier(params);

        _mockVerifierCalls({
            isEmergencyModeActive: false,
            dualGovernance: dualGovernance,
            emergencyGovernance: emergencyGovernance,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyProtectionEndDate: emergencyProtectionEndDate,
            emergencyModeEndsAfter: Timestamps.ZERO,
            emergencyModeDuration: emergencyModeDuration,
            proposalsCount: invalidProposalsCount
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DGLaunchStateVerifier.InvalidDGLaunchConfigParameter.selector,
                "getProposalsCount()",
                proposalsCount,
                invalidProposalsCount
            )
        );
        verifier.verify();
    }

    // ---
    // Helper methods
    // ---

    function _mockVerifierCalls(
        bool isEmergencyModeActive,
        address dualGovernance,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Timestamp emergencyProtectionEndDate,
        Timestamp emergencyModeEndsAfter,
        Duration emergencyModeDuration,
        uint256 proposalsCount
    ) internal {
        vm.mockCall(
            _timelock,
            abi.encodeWithSelector(IEmergencyProtectedTimelock.isEmergencyModeActive.selector),
            abi.encode(isEmergencyModeActive)
        );

        vm.mockCall(_timelock, abi.encodeWithSelector(ITimelock.getGovernance.selector), abi.encode(dualGovernance));

        vm.mockCall(
            _timelock,
            abi.encodeWithSelector(IEmergencyProtectedTimelock.getEmergencyGovernance.selector),
            abi.encode(emergencyGovernance)
        );

        vm.mockCall(
            _timelock,
            abi.encodeWithSelector(IEmergencyProtectedTimelock.getEmergencyActivationCommittee.selector),
            abi.encode(emergencyActivationCommittee)
        );

        vm.mockCall(
            _timelock,
            abi.encodeWithSelector(IEmergencyProtectedTimelock.getEmergencyExecutionCommittee.selector),
            abi.encode(emergencyExecutionCommittee)
        );

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory emDetails = IEmergencyProtectedTimelock
            .EmergencyProtectionDetails({
            emergencyModeDuration: emergencyModeDuration,
            emergencyModeEndsAfter: emergencyModeEndsAfter,
            emergencyProtectionEndsAfter: emergencyProtectionEndDate
        });

        vm.mockCall(
            _timelock,
            abi.encodeWithSelector(IEmergencyProtectedTimelock.getEmergencyProtectionDetails.selector),
            abi.encode(emDetails)
        );

        vm.mockCall(_timelock, abi.encodeWithSelector(ITimelock.getProposalsCount.selector), abi.encode(proposalsCount));
    }
}
