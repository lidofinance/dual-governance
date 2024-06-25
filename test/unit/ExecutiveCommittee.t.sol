// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UnitTest} from "test/utils/unit-test.sol";

import {Vm} from "forge-std/Test.sol";

import {ExecutiveCommittee} from "../../contracts/committees/ExecutiveCommittee.sol";

abstract contract ExecutiveCommitteeUnitTest is UnitTest {
    ExecutiveCommittee internal _executiveCommittee;

    address internal _owner = makeAddr("COMMITTEE_OWNER");

    address internal _stranger = makeAddr("STRANGER");

    uint256 internal _membersCount = 13;
    uint256 internal _quorum = 7;
    address[] internal _committeeMembers = new address[](_membersCount);

    constructor() {
        for (uint256 i = 0; i < _membersCount; ++i) {
            _committeeMembers[i] = makeAddr(string(abi.encode(0xFE + i * _membersCount + 65)));
        }
    }

    function test_isMember() public {
        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(_executiveCommittee.isMember(_committeeMembers[i]), true);
        }

        assertEq(_executiveCommittee.isMember(_owner), false);
        assertEq(_executiveCommittee.isMember(_stranger), false);
    }

    function test_getMembers() public {
        address[] memory committeeMembers = _executiveCommittee.getMembers();

        assertEq(committeeMembers.length, _committeeMembers.length);

        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(committeeMembers[i], _committeeMembers[i]);
        }
    }

    function test_addMember_stranger_call() public {
        address newMember = makeAddr("NEW_MEMBER");
        assertEq(_executiveCommittee.isMember(newMember), false);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("SenderIsNotOwner()"));
        _executiveCommittee.addMember(newMember, _quorum);

        for (uint256 i = 0; i < _membersCount; ++i) {
            vm.prank(_committeeMembers[i]);
            vm.expectRevert(abi.encodeWithSignature("SenderIsNotOwner()"));
            _executiveCommittee.addMember(newMember, _quorum);
        }
    }

    function test_addMember_reverts_on_duplicate() public {
        address existedMember = _committeeMembers[0];
        assertEq(_executiveCommittee.isMember(existedMember), true);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("DuplicatedMember(address)", existedMember));
        _executiveCommittee.addMember(existedMember, _quorum);
    }

    function test_addMember_reverts_on_invalid_quorum() public {
        address newMember = makeAddr("NEW_MEMBER");
        assertEq(_executiveCommittee.isMember(newMember), false);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _executiveCommittee.addMember(newMember, 0);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _executiveCommittee.addMember(newMember, _membersCount + 2);
    }

    function test_addMember() public {
        address newMember = makeAddr("NEW_MEMBER");
        uint256 newQuorum = _quorum + 1;

        assertEq(_executiveCommittee.isMember(newMember), false);

        vm.prank(_owner);
        vm.expectEmit(address(_executiveCommittee));
        emit ExecutiveCommittee.MemberAdded(newMember);
        vm.expectEmit(address(_executiveCommittee));
        emit ExecutiveCommittee.QuorumSet(newQuorum);
        _executiveCommittee.addMember(newMember, newQuorum);

        assertEq(_executiveCommittee.isMember(newMember), true);

        address[] memory committeeMembers = _executiveCommittee.getMembers();

        assertEq(committeeMembers.length, _membersCount + 1);
        assertEq(committeeMembers[committeeMembers.length - 1], newMember);
    }

    function test_removeMember_stranger_call() public {
        address memberToRemove = _committeeMembers[0];
        assertEq(_executiveCommittee.isMember(memberToRemove), true);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("SenderIsNotOwner()"));
        _executiveCommittee.removeMember(memberToRemove, _quorum);

        for (uint256 i = 0; i < _membersCount; ++i) {
            vm.prank(_committeeMembers[i]);
            vm.expectRevert(abi.encodeWithSignature("SenderIsNotOwner()"));
            _executiveCommittee.removeMember(memberToRemove, _quorum);
        }
    }

    function test_removeMember_reverts_on_member_is_not_exist() public {
        assertEq(_executiveCommittee.isMember(_stranger), false);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("IsNotMember()"));
        _executiveCommittee.removeMember(_stranger, _quorum);
    }

    function test_removeMember_reverts_on_invalid_quorum() public {
        address memberToRemove = _committeeMembers[0];
        assertEq(_executiveCommittee.isMember(memberToRemove), true);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _executiveCommittee.removeMember(memberToRemove, 0);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _executiveCommittee.removeMember(memberToRemove, _membersCount);
    }

    function test_removeMember() public {
        address memberToRemove = _committeeMembers[0];
        uint256 newQuorum = _quorum - 1;

        assertEq(_executiveCommittee.isMember(memberToRemove), true);

        vm.prank(_owner);
        vm.expectEmit(address(_executiveCommittee));
        emit ExecutiveCommittee.MemberRemoved(memberToRemove);
        vm.expectEmit(address(_executiveCommittee));
        emit ExecutiveCommittee.QuorumSet(newQuorum);
        _executiveCommittee.removeMember(memberToRemove, newQuorum);

        assertEq(_executiveCommittee.isMember(memberToRemove), false);

        address[] memory committeeMembers = _executiveCommittee.getMembers();

        assertEq(committeeMembers.length, _membersCount - 1);
        for (uint256 i = 0; i < committeeMembers.length; ++i) {
            assertNotEq(committeeMembers[i], memberToRemove);
        }
    }
}

contract Target {
    event Executed();

    function trigger() public {
        emit Executed();
    }
}

contract ExecutiveCommitteeWrapper is ExecutiveCommittee {
    Target internal _target;

    constructor(
        address owner,
        address[] memory newMembers,
        uint256 executionQuorum,
        uint256 timelock,
        Target target
    ) ExecutiveCommittee(owner, newMembers, executionQuorum, timelock) {
        _target = target;
    }

    function vote(bytes calldata data, bool support) public {
        _vote(data, support);
    }

    function execute(bytes calldata data) public {
        _markExecuted(data);
        _target.trigger();
    }

    function getVoteState(bytes calldata data)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getVoteState(data);
    }

    function getSupport(bytes32 voteHash) public view returns (uint256 support) {
        return _getSupport(voteHash);
    }
}

contract ExecutiveCommitteeInternalUnitTest is ExecutiveCommitteeUnitTest {
    ExecutiveCommitteeWrapper internal _executiveCommitteeWrapper;
    Target internal _target;
    uint256 _timelock = 3600;

    function setUp() public {
        _target = new Target();
        _executiveCommitteeWrapper =
            new ExecutiveCommitteeWrapper(_owner, _committeeMembers, _quorum, _timelock, _target);
        _executiveCommittee = ExecutiveCommittee(_executiveCommitteeWrapper);
    }

    function test_getSupport() public {
        bytes memory data = abi.encode(address(_target));
        bytes32 dataHash = keccak256(data);

        assertEq(_executiveCommitteeWrapper.getSupport(dataHash), 0);

        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(_executiveCommitteeWrapper.getSupport(dataHash), i);
            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(data, true);
            assertEq(_executiveCommitteeWrapper.getSupport(dataHash), i + 1);
        }

        assertEq(_executiveCommitteeWrapper.getSupport(dataHash), _membersCount);

        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(_executiveCommitteeWrapper.getSupport(dataHash), _membersCount - i);
            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(data, false);
            assertEq(_executiveCommitteeWrapper.getSupport(dataHash), _membersCount - i - 1);
        }

        assertEq(_executiveCommitteeWrapper.getSupport(dataHash), 0);
    }

    function test_getVoteState() public {
        bytes memory data = abi.encode(address(_target));

        uint256 support;
        uint256 execuitionQuorum;
        bool isExecuted;

        (support, execuitionQuorum, isExecuted) = _executiveCommitteeWrapper.getVoteState(data);
        assertEq(support, 0);
        assertEq(execuitionQuorum, _quorum);
        assertEq(isExecuted, false);

        for (uint256 i = 0; i < _membersCount; ++i) {
            (support, execuitionQuorum, isExecuted) = _executiveCommitteeWrapper.getVoteState(data);
            assertEq(support, i);
            assertEq(execuitionQuorum, _quorum);
            assertEq(isExecuted, false);

            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(data, true);

            (support, execuitionQuorum, isExecuted) = _executiveCommitteeWrapper.getVoteState(data);
            assertEq(support, i + 1);
            assertEq(execuitionQuorum, _quorum);
            assertEq(isExecuted, false);
        }

        (support, execuitionQuorum, isExecuted) = _executiveCommitteeWrapper.getVoteState(data);
        assertEq(support, _membersCount);
        assertEq(execuitionQuorum, _quorum);
        assertEq(isExecuted, false);

        _executiveCommitteeWrapper.execute(data);

        (support, execuitionQuorum, isExecuted) = _executiveCommitteeWrapper.getVoteState(data);
        assertEq(support, _membersCount);
        assertEq(execuitionQuorum, _quorum);
        assertEq(isExecuted, true);
    }

    function test_vote() public {
        bytes memory data = abi.encode(address(_target));

        bytes32 dataHash = keccak256(data);

        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], dataHash), false);

        vm.prank(_committeeMembers[0]);
        vm.expectEmit(address(_executiveCommitteeWrapper));
        emit ExecutiveCommittee.Voted(_committeeMembers[0], data, true);
        _executiveCommitteeWrapper.vote(data, true);
        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], dataHash), true);

        vm.prank(_committeeMembers[0]);
        vm.recordLogs();
        _executiveCommitteeWrapper.vote(data, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], dataHash), true);

        vm.prank(_committeeMembers[0]);
        vm.expectEmit(address(_executiveCommitteeWrapper));
        emit ExecutiveCommittee.Voted(_committeeMembers[0], data, false);
        _executiveCommitteeWrapper.vote(data, false);
        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], dataHash), false);

        vm.prank(_committeeMembers[0]);
        vm.recordLogs();
        _executiveCommitteeWrapper.vote(data, false);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], dataHash), false);
    }

    function test_vote_reverts_on_executed() public {
        bytes memory data = abi.encode(address(_target));

        for (uint256 i = 0; i < _quorum; ++i) {
            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(data, true);
        }

        _executiveCommitteeWrapper.execute(data);

        vm.prank(_committeeMembers[0]);
        vm.expectRevert(abi.encodeWithSignature("VoteAlreadyExecuted()"));
        _executiveCommitteeWrapper.vote(data, true);
    }

    function test_execute_events() public {
        bytes memory data = abi.encode(address(_target));

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("QuorumIsNotReached()"));
        _executiveCommitteeWrapper.execute(data);

        for (uint256 i = 0; i < _quorum; ++i) {
            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(data, true);
        }

        vm.prank(_stranger);
        vm.expectEmit(address(_executiveCommitteeWrapper));
        emit ExecutiveCommittee.VoteExecuted(data);
        vm.expectEmit(address(_target));
        emit Target.Executed();
        _executiveCommitteeWrapper.execute(data);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("VoteAlreadyExecuted()"));
        _executiveCommitteeWrapper.execute(data);
    }
}
