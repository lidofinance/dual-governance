// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EmergencyExecutionCommittee} from "contracts/committees/EmergencyExecutionCommittee.sol";
import {HashConsensus} from "contracts/committees/HashConsensus.sol";
import {Durations} from "contracts/types/Duration.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";

import {TargetMock} from "test/utils/target-mock.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract EmergencyProtectedTimelockMock is TargetMock {
    uint256 public proposalsCount;

    function getProposalsCount() external view returns (uint256 count) {
        return proposalsCount;
    }

    function setProposalsCount(uint256 _proposalsCount) external {
        proposalsCount = _proposalsCount;
    }
}

contract EmergencyExecutionCommitteeUnitTest is UnitTest {
    EmergencyExecutionCommittee internal emergencyExecutionCommittee;
    uint256 internal quorum = 2;
    address internal owner = makeAddr("owner");
    address[] internal committeeMembers = [address(0x1), address(0x2), address(0x3)];
    address internal emergencyProtectedTimelock;
    uint256 internal proposalId = 1;

    function setUp() external {
        emergencyProtectedTimelock = address(new EmergencyProtectedTimelockMock());
        EmergencyProtectedTimelockMock(payable(emergencyProtectedTimelock)).setProposalsCount(1);
        emergencyExecutionCommittee =
            new EmergencyExecutionCommittee(owner, committeeMembers, quorum, emergencyProtectedTimelock);
    }

    function testFuzz_constructor_HappyPath(
        address _owner,
        uint256 _quorum,
        address _emergencyProtectedTimelock
    ) external {
        vm.assume(_quorum > 0 && _quorum <= committeeMembers.length);
        EmergencyExecutionCommittee localCommittee =
            new EmergencyExecutionCommittee(_owner, committeeMembers, _quorum, _emergencyProtectedTimelock);
        assertEq(localCommittee.EMERGENCY_PROTECTED_TIMELOCK(), _emergencyProtectedTimelock);
    }

    function test_voteEmergencyExecute_HappyPath() external {
        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);

        (uint256 partialSupport,,,) = emergencyExecutionCommittee.getEmergencyExecuteState(proposalId);
        assertEq(partialSupport, 1);

        vm.prank(committeeMembers[1]);
        emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            emergencyExecutionCommittee.getEmergencyExecuteState(proposalId);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);
    }

    function test_voteEmergencyExecute_RevertOn_ProposalIdExceedsProposalsCount() external {
        uint256 nonExistentProposalId = proposalId + 1;

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyExecutionCommittee.ProposalDoesNotExist.selector, nonExistentProposalId)
        );
        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.voteEmergencyExecute(nonExistentProposalId, true);
    }

    function test_voteEmergencyExecute_RevertOn_ProposalIdIsZero() external {
        uint256 nonExistentProposalId = 0;

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyExecutionCommittee.ProposalDoesNotExist.selector, nonExistentProposalId)
        );
        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.voteEmergencyExecute(nonExistentProposalId, true);
    }

    function testFuzz_voteEmergencyExecute_RevertOn_NotMember(address caller) external {
        vm.assume(caller != committeeMembers[0] && caller != committeeMembers[1] && caller != committeeMembers[2]);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.CallerIsNotMember.selector, caller));
        emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);
    }

    function test_executeEmergencyExecute_HappyPath() external {
        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);
        vm.prank(committeeMembers[1]);
        emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);

        vm.prank(committeeMembers[2]);
        vm.expectCall(
            emergencyProtectedTimelock, abi.encodeWithSelector(ITimelock.emergencyExecute.selector, proposalId)
        );
        emergencyExecutionCommittee.executeEmergencyExecute(proposalId);

        (,,, bool isExecuted) = emergencyExecutionCommittee.getEmergencyExecuteState(proposalId);
        assertTrue(isExecuted);
    }

    function test_executeEmergencyExecute_RevertOn_QuorumNotReached() external {
        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);

        vm.prank(committeeMembers[2]);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.QuorumIsNotReached.selector));
        emergencyExecutionCommittee.executeEmergencyExecute(proposalId);
    }

    function test_getEmergencyExecuteState_HappyPath() external {
        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            emergencyExecutionCommittee.getEmergencyExecuteState(proposalId);
        assertEq(support, 0);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);
        (support, executionQuorum, quorumAt, isExecuted) =
            emergencyExecutionCommittee.getEmergencyExecuteState(proposalId);
        assertEq(support, 1);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[1]);
        emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);
        (support, executionQuorum, quorumAt, isExecuted) =
            emergencyExecutionCommittee.getEmergencyExecuteState(proposalId);
        assertEq(support, 2);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[2]);
        emergencyExecutionCommittee.executeEmergencyExecute(proposalId);
        (support, executionQuorum, quorumAt, isExecuted) =
            emergencyExecutionCommittee.getEmergencyExecuteState(proposalId);
        assertEq(support, 2);
        assertTrue(isExecuted);
    }

    function test_approveEmergencyReset_HappyPath() external {
        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.approveEmergencyReset();

        (uint256 partialSupport,,,) = emergencyExecutionCommittee.getEmergencyResetState();
        assertEq(partialSupport, 1);

        vm.prank(committeeMembers[1]);
        emergencyExecutionCommittee.approveEmergencyReset();

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            emergencyExecutionCommittee.getEmergencyResetState();
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);
    }

    function test_executeEmergencyReset_HappyPath() external {
        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.approveEmergencyReset();
        vm.prank(committeeMembers[1]);
        emergencyExecutionCommittee.approveEmergencyReset();

        vm.prank(committeeMembers[2]);
        vm.expectCall(emergencyProtectedTimelock, abi.encodeWithSelector(ITimelock.emergencyReset.selector));
        emergencyExecutionCommittee.executeEmergencyReset();

        (,,, bool isExecuted) = emergencyExecutionCommittee.getEmergencyResetState();
        assertTrue(isExecuted);
    }

    function test_executeEmergencyReset_RevertOn_QuorumNotReached() external {
        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.approveEmergencyReset();

        vm.prank(committeeMembers[2]);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.QuorumIsNotReached.selector));
        emergencyExecutionCommittee.executeEmergencyReset();
    }

    function test_getEmergencyResetState_HappyPath() external {
        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            emergencyExecutionCommittee.getEmergencyResetState();
        assertEq(support, 0);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[0]);
        emergencyExecutionCommittee.approveEmergencyReset();
        (support, executionQuorum, quorumAt, isExecuted) = emergencyExecutionCommittee.getEmergencyResetState();
        assertEq(support, 1);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[1]);
        emergencyExecutionCommittee.approveEmergencyReset();
        (support, executionQuorum, quorumAt, isExecuted) = emergencyExecutionCommittee.getEmergencyResetState();
        assertEq(support, 2);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[2]);
        emergencyExecutionCommittee.executeEmergencyReset();
        (support, executionQuorum, quorumAt, isExecuted) = emergencyExecutionCommittee.getEmergencyResetState();
        assertEq(support, 2);
        assertTrue(isExecuted);
    }
}
