// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {ResealCommittee} from "contracts/committees/ResealCommittee.sol";
import {HashConsensus} from "contracts/committees/HashConsensus.sol";

import {TargetMock} from "test/utils/target-mock.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract ResealCommitteeUnitTest is UnitTest {
    ResealCommittee internal resealCommittee;

    uint256 internal quorum = 2;
    address internal owner = makeAddr("owner");
    address[] internal committeeMembers = [address(0x1), address(0x2), address(0x3)];
    address internal sealable = makeAddr("sealable");
    address internal dualGovernance;

    function setUp() external {
        dualGovernance = address(new TargetMock());
        resealCommittee = new ResealCommittee(owner, committeeMembers, quorum, dualGovernance, Durations.from(0));
    }

    function test_constructor_HappyPath() external {
        ResealCommittee resealCommitteeLocal =
            new ResealCommittee(owner, committeeMembers, quorum, dualGovernance, Durations.from(0));
        assertEq(resealCommitteeLocal.DUAL_GOVERNANCE(), dualGovernance);
    }

    function test_voteReseal_HappyPath() external {
        vm.prank(committeeMembers[0]);
        resealCommittee.voteReseal(sealable, true);

        (uint256 partialSupport,,) = resealCommittee.getResealState(sealable);
        assertEq(partialSupport, 1);

        vm.prank(committeeMembers[1]);
        resealCommittee.voteReseal(sealable, true);

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt) = resealCommittee.getResealState(sealable);

        assertEq(support, quorum);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(uint40(block.timestamp)));
    }

    function testFuzz_voteReseal_RevertOn_NotMember(address caller) external {
        vm.assume(caller != committeeMembers[0] && caller != committeeMembers[1] && caller != committeeMembers[2]);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.CallerIsNotMember.selector, caller));
        resealCommittee.voteReseal(sealable, true);
    }

    function test_executeReseal_HappyPath() external {
        vm.prank(committeeMembers[0]);
        resealCommittee.voteReseal(sealable, true);
        vm.prank(committeeMembers[1]);
        resealCommittee.voteReseal(sealable, true);

        vm.prank(committeeMembers[2]);
        vm.expectCall(dualGovernance, abi.encodeWithSelector(IDualGovernance.resealSealable.selector, sealable));
        resealCommittee.executeReseal(sealable);

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt) = resealCommittee.getResealState(sealable);
        assertEq(support, 0);
        assertEq(executionQuorum, quorum);
        assertEq(quorumAt, Timestamp.wrap(0));
    }

    function test_executeReseal_RevertOn_QuorumNotReached() external {
        vm.prank(committeeMembers[0]);
        resealCommittee.voteReseal(sealable, true);

        vm.prank(committeeMembers[2]);
        vm.expectRevert(
            abi.encodeWithSelector(
                HashConsensus.HashIsNotScheduled.selector, keccak256(abi.encode(sealable, /* resealNonce */ 0))
            )
        );
        resealCommittee.executeReseal(sealable);
    }

    function test_getResealState_HappyPath() external {
        vm.prank(owner);
        resealCommittee.setQuorum(3);

        (uint256 support, uint256 executionQuorum, Timestamp quorumAt) = resealCommittee.getResealState(sealable);
        assertEq(support, 0);
        assertEq(executionQuorum, 3);
        assertEq(quorumAt, Timestamps.ZERO);

        vm.prank(committeeMembers[0]);
        resealCommittee.voteReseal(sealable, true);

        (support, executionQuorum, quorumAt) = resealCommittee.getResealState(sealable);
        assertEq(support, 1);
        assertEq(executionQuorum, 3);
        assertEq(quorumAt, Timestamps.ZERO);

        vm.prank(committeeMembers[1]);
        resealCommittee.voteReseal(sealable, true);

        (support, executionQuorum, quorumAt) = resealCommittee.getResealState(sealable);
        assertEq(support, 2);
        assertEq(executionQuorum, 3);
        assertEq(quorumAt, Timestamps.ZERO);

        _wait(Durations.from(1));

        vm.prank(committeeMembers[1]);
        resealCommittee.voteReseal(sealable, false);

        (support, executionQuorum, quorumAt) = resealCommittee.getResealState(sealable);
        assertEq(support, 1);
        assertEq(executionQuorum, 3);
        assertEq(quorumAt, Timestamps.ZERO);

        vm.prank(committeeMembers[1]);
        resealCommittee.voteReseal(sealable, true);

        (support, executionQuorum, quorumAt) = resealCommittee.getResealState(sealable);
        assertEq(support, 2);
        assertEq(executionQuorum, 3);
        assertEq(quorumAt, Timestamps.ZERO);

        vm.prank(committeeMembers[2]);
        resealCommittee.voteReseal(sealable, true);

        Timestamp quorumAtExpected = Timestamps.now();
        (support, executionQuorum, quorumAt) = resealCommittee.getResealState(sealable);
        assertEq(support, 3);
        assertEq(executionQuorum, 3);
        assertEq(quorumAt, quorumAtExpected);

        vm.prank(committeeMembers[2]);
        vm.expectCall(dualGovernance, abi.encodeWithSelector(IDualGovernance.resealSealable.selector, sealable));
        resealCommittee.executeReseal(sealable);

        (support, executionQuorum, quorumAt) = resealCommittee.getResealState(sealable);
        assertEq(support, 0);
        assertEq(executionQuorum, 3);
        assertEq(quorumAt, Timestamp.wrap(0));
    }
}
