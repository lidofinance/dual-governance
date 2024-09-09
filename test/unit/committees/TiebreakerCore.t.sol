// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TiebreakerCore} from "contracts/committees/TiebreakerCore.sol";
import {HashConsensus} from "contracts/committees/HashConsensus.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";

import {TargetMock} from "test/utils/target-mock.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract TiebreakerCoreUnitTest is UnitTest {
    TiebreakerCore internal tiebreakerCore;
    uint256 internal quorum = 2;
    address internal owner = makeAddr("owner");
    address[] internal committeeMembers = [address(0x1), address(0x2), address(0x3)];
    address internal dualGovernance;
    uint256 internal proposalId = 1;
    address internal sealable = makeAddr("sealable");
    Duration internal timelock = Durations.from(1 days);

    function setUp() external {
        dualGovernance = address(new TargetMock());
        tiebreakerCore = new TiebreakerCore(owner, dualGovernance, timelock);

        vm.prank(owner);
        tiebreakerCore.addMembers(committeeMembers, quorum);
    }

    function testFuzz_constructor_HappyPath(address _owner, address _dualGovernance, Duration _timelock) external {
        new TiebreakerCore(_owner, _dualGovernance, _timelock);
    }

    function test_scheduleProposal_HappyPath() external {
        vm.prank(committeeMembers[0]);
        tiebreakerCore.scheduleProposal(proposalId);

        (uint256 partialSupport,,,) = tiebreakerCore.getScheduleProposalState(proposalId);
        assertEq(partialSupport, 1);

        vm.prank(committeeMembers[1]);
        tiebreakerCore.scheduleProposal(proposalId);

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            tiebreakerCore.getScheduleProposalState(proposalId);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);
    }

    function testFuzz_scheduleProposal_RevertOn_NotMember(address caller) external {
        vm.assume(caller != committeeMembers[0] && caller != committeeMembers[1] && caller != committeeMembers[2]);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.CallerIsNotMember.selector, caller));
        tiebreakerCore.scheduleProposal(proposalId);
    }

    function test_executeScheduleProposal_HappyPath() external {
        vm.prank(committeeMembers[0]);
        tiebreakerCore.scheduleProposal(proposalId);
        vm.prank(committeeMembers[1]);
        tiebreakerCore.scheduleProposal(proposalId);

        _wait(timelock);

        vm.prank(committeeMembers[2]);
        vm.expectCall(
            dualGovernance, abi.encodeWithSelector(IDualGovernance.tiebreakerScheduleProposal.selector, proposalId)
        );
        tiebreakerCore.executeScheduleProposal(proposalId);

        (,,, bool isExecuted) = tiebreakerCore.getScheduleProposalState(proposalId);
        assertTrue(isExecuted);
    }

    function test_sealableResume_HappyPath() external {
        uint256 nonce = tiebreakerCore.getSealableResumeNonce(sealable);

        vm.prank(committeeMembers[0]);
        tiebreakerCore.sealableResume(sealable, nonce);

        (uint256 partialSupport,,,) = tiebreakerCore.getSealableResumeState(sealable, nonce);
        assertEq(partialSupport, 1);

        vm.prank(committeeMembers[1]);
        tiebreakerCore.sealableResume(sealable, nonce);

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            tiebreakerCore.getSealableResumeState(sealable, nonce);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
        assertFalse(isExecuted);
    }

    function test_sealableResume_RevertOn_NonceMismatch() external {
        uint256 wrongNonce = 999;

        vm.prank(committeeMembers[0]);
        vm.expectRevert(abi.encodeWithSelector(TiebreakerCore.ResumeSealableNonceMismatch.selector));
        tiebreakerCore.sealableResume(sealable, wrongNonce);
    }

    function test_executeSealableResume_HappyPath() external {
        uint256 nonce = tiebreakerCore.getSealableResumeNonce(sealable);

        vm.prank(committeeMembers[0]);
        tiebreakerCore.sealableResume(sealable, nonce);
        vm.prank(committeeMembers[1]);
        tiebreakerCore.sealableResume(sealable, nonce);

        _wait(timelock);

        vm.prank(committeeMembers[2]);
        vm.expectCall(
            dualGovernance, abi.encodeWithSelector(IDualGovernance.tiebreakerResumeSealable.selector, sealable)
        );
        tiebreakerCore.executeSealableResume(sealable);

        (,,, bool isExecuted) = tiebreakerCore.getSealableResumeState(sealable, nonce);
        assertTrue(isExecuted);

        uint256 newNonce = tiebreakerCore.getSealableResumeNonce(sealable);
        assertEq(newNonce, nonce + 1);
    }

    function test_getScheduleProposalState_HappyPath() external {
        (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted) =
            tiebreakerCore.getScheduleProposalState(proposalId);
        assertEq(support, 0);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[0]);
        tiebreakerCore.scheduleProposal(proposalId);

        (support, executionQuorum, quorumAt, isExecuted) = tiebreakerCore.getScheduleProposalState(proposalId);
        assertEq(support, 1);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
        assertFalse(isExecuted);

        vm.prank(committeeMembers[1]);
        tiebreakerCore.scheduleProposal(proposalId);

        (support, executionQuorum, quorumAt, isExecuted) = tiebreakerCore.getScheduleProposalState(proposalId);
        Timestamp quorumAtExpected = Timestamp.wrap(uint40(block.timestamp));
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, quorumAtExpected);
        assertFalse(isExecuted);

        _wait(timelock);

        vm.prank(committeeMembers[2]);
        tiebreakerCore.executeScheduleProposal(proposalId);

        (support, executionQuorum, quorumAt, isExecuted) = tiebreakerCore.getScheduleProposalState(proposalId);
        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, quorumAtExpected);
        assertTrue(isExecuted);
    }
}
