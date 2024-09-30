// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EmergencyActivationCommittee} from "contracts/committees/EmergencyActivationCommittee.sol";
import {HashConsensus} from "contracts/committees/HashConsensus.sol";
import {Durations} from "contracts/types/Duration.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";

import {TargetMock} from "test/utils/target-mock.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract EmergencyActivationCommitteeUnitTest is UnitTest {
    bytes32 private constant _EMERGENCY_ACTIVATION_HASH = keccak256("EMERGENCY_ACTIVATE");

    EmergencyActivationCommittee internal emergencyActivationCommittee;
    uint256 internal quorum = 2;
    address internal owner = makeAddr("owner");
    address[] internal committeeMembers = [address(0x1), address(0x2), address(0x3)];
    address internal emergencyProtectedTimelock;

    function setUp() external {
        emergencyProtectedTimelock = address(new TargetMock());
        emergencyActivationCommittee =
            new EmergencyActivationCommittee(owner, committeeMembers, quorum, emergencyProtectedTimelock);
    }

    function testFuzz_constructor_HappyPath(
        address _owner,
        uint256 _quorum,
        address _emergencyProtectedTimelock
    ) external {
        vm.assume(_quorum > 0 && _quorum <= committeeMembers.length);
        EmergencyActivationCommittee localCommittee =
            new EmergencyActivationCommittee(_owner, committeeMembers, _quorum, _emergencyProtectedTimelock);
        assertEq(localCommittee.EMERGENCY_PROTECTED_TIMELOCK(), _emergencyProtectedTimelock);
    }

    function test_approveActivateEmergencyMode_HappyPath() external {
        vm.prank(committeeMembers[0]);
        emergencyActivationCommittee.approveActivateEmergencyMode();

        (uint256 partialSupport,,,) = emergencyActivationCommittee.getActivateEmergencyModeState();
        assertEq(partialSupport, 1);

        vm.prank(committeeMembers[1]);
        emergencyActivationCommittee.approveActivateEmergencyMode();

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            emergencyActivationCommittee.getActivateEmergencyModeState();
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertEq(isExecuted, false);
    }

    function testFuzz_approveActivateEmergencyMode_RevertOn_NotMember(address caller) external {
        vm.assume(caller != committeeMembers[0] && caller != committeeMembers[1] && caller != committeeMembers[2]);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.CallerIsNotMember.selector, caller));
        emergencyActivationCommittee.approveActivateEmergencyMode();
    }

    function test_executeActivateEmergencyMode_HappyPath() external {
        vm.prank(committeeMembers[0]);
        emergencyActivationCommittee.approveActivateEmergencyMode();
        vm.prank(committeeMembers[1]);
        emergencyActivationCommittee.approveActivateEmergencyMode();

        vm.prank(committeeMembers[2]);
        vm.expectCall(
            emergencyProtectedTimelock,
            abi.encodeWithSelector(IEmergencyProtectedTimelock.activateEmergencyMode.selector)
        );
        emergencyActivationCommittee.executeActivateEmergencyMode();

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            emergencyActivationCommittee.getActivateEmergencyModeState();
        assertEq(support, 2);
        assertEq(executionQuorum, 2);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertEq(isExecuted, true);
    }

    function test_executeActivateEmergencyMode_RevertOn_QuorumNotReached() external {
        vm.prank(committeeMembers[0]);
        emergencyActivationCommittee.approveActivateEmergencyMode();

        vm.prank(committeeMembers[2]);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.HashIsNotScheduled.selector, _EMERGENCY_ACTIVATION_HASH));
        emergencyActivationCommittee.executeActivateEmergencyMode();
    }

    function test_getActivateEmergencyModeState_HappyPath() external {
        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            emergencyActivationCommittee.getActivateEmergencyModeState();
        assertEq(support, 0);
        assertEq(executionQuorum, 2);
        assertEq(quorumAt, Timestamp.wrap(0));

        vm.prank(committeeMembers[0]);
        emergencyActivationCommittee.approveActivateEmergencyMode();

        (support, executionQuorum, quorumAt, isExecuted) = emergencyActivationCommittee.getActivateEmergencyModeState();
        assertEq(support, 1);
        assertEq(executionQuorum, 2);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertEq(isExecuted, false);

        vm.prank(committeeMembers[1]);
        emergencyActivationCommittee.approveActivateEmergencyMode();

        (support, executionQuorum, quorumAt, isExecuted) = emergencyActivationCommittee.getActivateEmergencyModeState();
        Timestamp quorumAtExpected = Timestamp.wrap(uint40(block.timestamp));
        assertEq(support, 2);
        assertEq(executionQuorum, 2);
        assertEq(quorumAt, quorumAtExpected);
        assertEq(isExecuted, false);

        vm.prank(committeeMembers[2]);
        vm.expectCall(
            emergencyProtectedTimelock,
            abi.encodeWithSelector(IEmergencyProtectedTimelock.activateEmergencyMode.selector)
        );
        emergencyActivationCommittee.executeActivateEmergencyMode();

        (support, executionQuorum, quorumAt, isExecuted) = emergencyActivationCommittee.getActivateEmergencyModeState();
        assertEq(support, 2);
        assertEq(executionQuorum, 2);
        assertEq(quorumAt, quorumAtExpected);
        assertEq(isExecuted, true);
    }
}
