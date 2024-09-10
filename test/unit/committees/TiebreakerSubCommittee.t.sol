// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITiebreakerCore} from "contracts/interfaces/ITiebreakerCore.sol";

import {TiebreakerCore} from "contracts/committees/TiebreakerCore.sol";
import {TiebreakerSubCommittee, ProposalType} from "contracts/committees/TiebreakerSubCommittee.sol";
import {HashConsensus} from "contracts/committees/HashConsensus.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";
import {UnitTest} from "test/utils/unit-test.sol";
import {ITiebreakerCore} from "contracts/interfaces/ITiebreakerCore.sol";

import {TargetMock} from "test/utils/target-mock.sol";

contract TiebreakerCoreMock is TargetMock {
    error ProposalDoesNotExist(uint256 proposalId);

    uint256 public proposalsCount;

    function checkProposalExists(uint256 _proposalId) external view {
        if (_proposalId > proposalsCount) {
            revert ProposalDoesNotExist(_proposalId);
        }
    }

    function setProposalsCount(uint256 _proposalsCount) external {
        proposalsCount = _proposalsCount;
    }
}

contract TiebreakerSubCommitteeUnitTest is UnitTest {
    TiebreakerSubCommittee internal tiebreakerSubCommittee;
    uint256 internal quorum = 2;
    address internal owner = makeAddr("owner");
    address[] internal committeeMembers = [address(0x1), address(0x2), address(0x3)];
    address internal tiebreakerCore;
    uint256 internal proposalId = 1;
    address internal sealable = makeAddr("sealable");

    function setUp() external {
        tiebreakerCore = address(new TiebreakerCoreMock());
        TiebreakerCoreMock(payable(tiebreakerCore)).setProposalsCount(1);
        tiebreakerSubCommittee = new TiebreakerSubCommittee(owner, committeeMembers, quorum, tiebreakerCore);
    }

    function test_constructor_HappyPath(address _owner, uint256 _quorum, address _tiebreakerCore) external {
        vm.assume(_quorum > 0 && _quorum <= committeeMembers.length);
        new TiebreakerSubCommittee(_owner, committeeMembers, _quorum, _tiebreakerCore);
    }

    function test_scheduleProposal_HappyPath() external {
        vm.prank(committeeMembers[0]);
        tiebreakerSubCommittee.scheduleProposal(proposalId);

        (uint256 partialSupport,,,) = tiebreakerSubCommittee.getScheduleProposalState(proposalId);
        assertEq(partialSupport, 1);

        vm.prank(committeeMembers[1]);
        tiebreakerSubCommittee.scheduleProposal(proposalId);

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            tiebreakerSubCommittee.getScheduleProposalState(proposalId);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);
    }

    function testFuzz_scheduleProposal_RevertOn_NotMember(address caller) external {
        vm.assume(caller != committeeMembers[0] && caller != committeeMembers[1] && caller != committeeMembers[2]);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.CallerIsNotMember.selector, caller));
        tiebreakerSubCommittee.scheduleProposal(proposalId);
    }

    function test_executeScheduleProposal_HappyPath() external {
        vm.prank(committeeMembers[0]);
        tiebreakerSubCommittee.scheduleProposal(proposalId);
        vm.prank(committeeMembers[1]);
        tiebreakerSubCommittee.scheduleProposal(proposalId);

        vm.prank(committeeMembers[2]);
        vm.expectCall(tiebreakerCore, abi.encodeWithSelector(ITiebreakerCore.scheduleProposal.selector, proposalId));
        tiebreakerSubCommittee.executeScheduleProposal(proposalId);

        (,,, bool isExecuted) = tiebreakerSubCommittee.getScheduleProposalState(proposalId);
        assertTrue(isExecuted);
    }

    function test_executeScheduleProposal_RevertOn_QuorumNotReached() external {
        vm.prank(committeeMembers[0]);
        tiebreakerSubCommittee.scheduleProposal(proposalId);

        vm.prank(committeeMembers[2]);
        vm.expectRevert(
            abi.encodeWithSelector(
                HashConsensus.HashIsNotScheduled.selector,
                keccak256(abi.encode(ProposalType.ScheduleProposal, proposalId))
            )
        );
        tiebreakerSubCommittee.executeScheduleProposal(proposalId);
    }

    function test_scheduleProposal_RevertOn_ProposalDoesNotExist() external {
        uint256 nonExistentProposalId = proposalId + 1;

        vm.expectRevert(abi.encodeWithSelector(TiebreakerCore.ProposalDoesNotExist.selector, nonExistentProposalId));
        vm.prank(committeeMembers[0]);
        tiebreakerSubCommittee.scheduleProposal(nonExistentProposalId);
    }

    function test_sealableResume_HappyPath() external {
        vm.mockCall(
            tiebreakerCore,
            abi.encodeWithSelector(ITiebreakerCore.getSealableResumeNonce.selector, sealable),
            abi.encode(0)
        );

        vm.prank(committeeMembers[0]);
        tiebreakerSubCommittee.sealableResume(sealable);

        (uint256 partialSupport,,,) = tiebreakerSubCommittee.getSealableResumeState(sealable);
        assertEq(partialSupport, 1);

        vm.prank(committeeMembers[1]);
        tiebreakerSubCommittee.sealableResume(sealable);

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            tiebreakerSubCommittee.getSealableResumeState(sealable);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);
    }

    function testFuzz_sealableResume_RevertOn_NotMember(address caller) external {
        vm.assume(caller != committeeMembers[0] && caller != committeeMembers[1] && caller != committeeMembers[2]);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.CallerIsNotMember.selector, caller));
        tiebreakerSubCommittee.sealableResume(sealable);
    }

    function test_executeSealableResume_HappyPath() external {
        vm.mockCall(
            tiebreakerCore,
            abi.encodeWithSelector(ITiebreakerCore.getSealableResumeNonce.selector, sealable),
            abi.encode(0)
        );

        vm.prank(committeeMembers[0]);
        tiebreakerSubCommittee.sealableResume(sealable);
        vm.prank(committeeMembers[1]);
        tiebreakerSubCommittee.sealableResume(sealable);

        vm.prank(committeeMembers[2]);
        vm.expectCall(tiebreakerCore, abi.encodeWithSelector(ITiebreakerCore.sealableResume.selector, sealable, 0));
        tiebreakerSubCommittee.executeSealableResume(sealable);

        (,,, bool isExecuted) = tiebreakerSubCommittee.getSealableResumeState(sealable);
        assertTrue(isExecuted);
    }

    function test_executeSealableResume_RevertOn_QuorumNotReached() external {
        vm.mockCall(
            tiebreakerCore,
            abi.encodeWithSelector(ITiebreakerCore.getSealableResumeNonce.selector, sealable),
            abi.encode(0)
        );

        vm.prank(committeeMembers[0]);
        tiebreakerSubCommittee.sealableResume(sealable);

        vm.prank(committeeMembers[2]);
        vm.expectRevert(
            abi.encodeWithSelector(
                HashConsensus.HashIsNotScheduled.selector, keccak256(abi.encode(sealable, /*nonce */ 0))
            )
        );
        tiebreakerSubCommittee.executeSealableResume(sealable);
    }

    function test_getScheduleProposalState_HappyPath() external {
        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            tiebreakerSubCommittee.getScheduleProposalState(proposalId);
        assertEq(support, 0);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[0]);
        tiebreakerSubCommittee.scheduleProposal(proposalId);

        (support, executionQuorum, quorumAt, isExecuted) = tiebreakerSubCommittee.getScheduleProposalState(proposalId);
        assertEq(support, 1);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[1]);
        tiebreakerSubCommittee.scheduleProposal(proposalId);

        (support, executionQuorum, quorumAt, isExecuted) = tiebreakerSubCommittee.getScheduleProposalState(proposalId);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[2]);
        tiebreakerSubCommittee.executeScheduleProposal(proposalId);

        (support, executionQuorum, quorumAt, isExecuted) = tiebreakerSubCommittee.getScheduleProposalState(proposalId);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertTrue(isExecuted);
    }

    function test_getSealableResumeState_HappyPath() external {
        vm.mockCall(
            tiebreakerCore,
            abi.encodeWithSelector(ITiebreakerCore.getSealableResumeNonce.selector, sealable),
            abi.encode(0)
        );

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            tiebreakerSubCommittee.getSealableResumeState(sealable);
        assertEq(support, 0);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[0]);
        tiebreakerSubCommittee.sealableResume(sealable);

        (support, executionQuorum, quorumAt, isExecuted) = tiebreakerSubCommittee.getSealableResumeState(sealable);
        assertEq(support, 1);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[1]);
        tiebreakerSubCommittee.sealableResume(sealable);

        (support, executionQuorum, quorumAt, isExecuted) = tiebreakerSubCommittee.getSealableResumeState(sealable);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[2]);
        tiebreakerSubCommittee.executeSealableResume(sealable);

        (support, executionQuorum, quorumAt, isExecuted) = tiebreakerSubCommittee.getSealableResumeState(sealable);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertTrue(isExecuted);
    }
}
