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

contract ExecutiveCommitteeWrapper is ExecutiveCommittee {
    constructor(
        address owner,
        address[] memory newMembers,
        uint256 executionQuorum
    ) ExecutiveCommittee(owner, newMembers, executionQuorum) {}

    function vote(Action memory action, bool support) public {
        _vote(action, support);
    }

    function execute(Action memory action) public {
        _execute(action);
    }

    function getActionState(Action memory action)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getActionState(action);
    }

    function getSupport(bytes32 actionHash) public view returns (uint256 support) {
        return _getSupport(actionHash);
    }

    function getAndCheckStoredActionState(Action memory action)
        public
        view
        returns (ActionState memory storedActionState, bytes32 actionHash)
    {
        return _getAndCheckStoredActionState(action);
    }

    function hashAction(Action memory action) public pure returns (bytes32) {
        return _hashAction(action);
    }
}

contract Target {
    event Executed();

    function trigger() public {
        emit Executed();
    }
}

contract ExecutiveCommitteeInternalUnitTest is ExecutiveCommitteeUnitTest {
    ExecutiveCommitteeWrapper internal _executiveCommitteeWrapper;
    Target internal _target;

    function setUp() public {
        _target = new Target();
        _executiveCommitteeWrapper = new ExecutiveCommitteeWrapper(_owner, _committeeMembers, _quorum);
        _executiveCommittee = ExecutiveCommittee(_executiveCommitteeWrapper);
    }

    function test_hashAction() public {
        ExecutiveCommittee.Action memory action = ExecutiveCommittee.Action(address(1), new bytes(10), new bytes(100));

        bytes32 actionHash = keccak256(abi.encode(action.to, action.data, action.salt));

        assertEq(_executiveCommitteeWrapper.hashAction(action), actionHash);
    }

    function test_getSupport() public {
        ExecutiveCommittee.Action memory action = ExecutiveCommittee.Action(address(1), new bytes(10), new bytes(100));
        bytes32 actionHash = keccak256(abi.encode(action.to, action.data, action.salt));

        assertEq(_executiveCommitteeWrapper.getSupport(actionHash), 0);

        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(_executiveCommitteeWrapper.getSupport(actionHash), i);
            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(action, true);
            assertEq(_executiveCommitteeWrapper.getSupport(actionHash), i + 1);
        }

        assertEq(_executiveCommitteeWrapper.getSupport(actionHash), _membersCount);

        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(_executiveCommitteeWrapper.getSupport(actionHash), _membersCount - i);
            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(action, false);
            assertEq(_executiveCommitteeWrapper.getSupport(actionHash), _membersCount - i - 1);
        }

        assertEq(_executiveCommitteeWrapper.getSupport(actionHash), 0);
    }

    function test_getAndCheckActionState() public {
        address to = address(_target);
        bytes memory data = abi.encodeWithSelector(Target.trigger.selector);
        bytes memory salt = abi.encodePacked(hex"beaf");

        ExecutiveCommittee.Action memory action = ExecutiveCommittee.Action(to, data, salt);
        bytes32 actionHash = keccak256(abi.encode(action.to, action.data, action.salt));

        ExecutiveCommittee.ActionState memory storedActionStateFromContract;
        bytes32 actionHashFromContract;

        vm.expectRevert(abi.encodeWithSignature("ActionMismatch()"));
        _executiveCommitteeWrapper.getAndCheckStoredActionState(action);

        vm.prank(_committeeMembers[0]);
        _executiveCommitteeWrapper.vote(action, false);

        (storedActionStateFromContract, actionHashFromContract) =
            _executiveCommitteeWrapper.getAndCheckStoredActionState(action);
        assertEq(storedActionStateFromContract.isExecuted, false);
        assertEq(storedActionStateFromContract.action.to, to);
        assertEq(storedActionStateFromContract.action.data, data);
        assertEq(storedActionStateFromContract.action.salt, salt);
        assertEq(actionHashFromContract, actionHash);

        for (uint256 i = 0; i < _membersCount; ++i) {
            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(action, true);
        }

        _executiveCommitteeWrapper.execute(action);

        vm.expectRevert(abi.encodeWithSignature("ActionAlreadyExecuted()"));
        _executiveCommitteeWrapper.getAndCheckStoredActionState(action);
    }

    function test_getActionState() public {
        address to = address(_target);
        bytes memory data = abi.encodeWithSelector(Target.trigger.selector);
        bytes memory salt = abi.encodePacked(hex"beaf");

        ExecutiveCommittee.Action memory action = ExecutiveCommittee.Action(to, data, salt);

        vm.prank(_committeeMembers[0]);
        _executiveCommitteeWrapper.vote(action, false);

        uint256 support;
        uint256 execuitionQuorum;
        bool isExecuted;

        (support, execuitionQuorum, isExecuted) = _executiveCommitteeWrapper.getActionState(action);
        assertEq(support, 0);
        assertEq(execuitionQuorum, _quorum);
        assertEq(isExecuted, false);

        for (uint256 i = 0; i < _membersCount; ++i) {
            (support, execuitionQuorum, isExecuted) = _executiveCommitteeWrapper.getActionState(action);
            assertEq(support, i);
            assertEq(execuitionQuorum, _quorum);
            assertEq(isExecuted, false);

            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(action, true);

            (support, execuitionQuorum, isExecuted) = _executiveCommitteeWrapper.getActionState(action);
            assertEq(support, i + 1);
            assertEq(execuitionQuorum, _quorum);
            assertEq(isExecuted, false);
        }

        (support, execuitionQuorum, isExecuted) = _executiveCommitteeWrapper.getActionState(action);
        assertEq(support, _membersCount);
        assertEq(execuitionQuorum, _quorum);
        assertEq(isExecuted, false);

        _executiveCommitteeWrapper.execute(action);

        vm.expectRevert(abi.encodeWithSignature("ActionAlreadyExecuted()"));
        _executiveCommitteeWrapper.getActionState(action);
    }

    function test_vote() public {
        address to = address(_target);
        bytes memory data = abi.encodeWithSelector(Target.trigger.selector);
        bytes memory salt = abi.encodePacked(hex"beaf");

        ExecutiveCommittee.Action memory action = ExecutiveCommittee.Action(to, data, salt);
        bytes32 actionHash = keccak256(abi.encode(action.to, action.data, action.salt));

        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], actionHash), false);

        vm.prank(_committeeMembers[0]);
        vm.expectEmit(address(_executiveCommitteeWrapper));
        emit ExecutiveCommittee.ActionVoted(_committeeMembers[0], true, to, data);
        _executiveCommitteeWrapper.vote(action, true);
        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], actionHash), true);

        vm.prank(_committeeMembers[0]);
        vm.recordLogs();
        _executiveCommitteeWrapper.vote(action, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], actionHash), true);

        vm.prank(_committeeMembers[0]);
        vm.expectEmit(address(_executiveCommitteeWrapper));
        emit ExecutiveCommittee.ActionVoted(_committeeMembers[0], false, to, data);
        _executiveCommitteeWrapper.vote(action, false);
        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], actionHash), false);

        vm.prank(_committeeMembers[0]);
        vm.recordLogs();
        _executiveCommitteeWrapper.vote(action, false);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
        assertEq(_executiveCommitteeWrapper.approves(_committeeMembers[0], actionHash), false);
    }

    function test_vote_reverts_on_executed() public {
        address to = address(_target);
        bytes memory data = abi.encodeWithSelector(Target.trigger.selector);
        bytes memory salt = abi.encodePacked(hex"beaf");

        ExecutiveCommittee.Action memory action = ExecutiveCommittee.Action(to, data, salt);

        for (uint256 i = 0; i < _quorum; ++i) {
            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(action, true);
        }

        _executiveCommitteeWrapper.execute(action);

        vm.prank(_committeeMembers[0]);
        vm.expectRevert(abi.encodeWithSignature("ActionAlreadyExecuted()"));
        _executiveCommitteeWrapper.vote(action, true);
    }

    function test_execute_events() public {
        address to = address(_target);
        bytes memory data = abi.encodeWithSelector(Target.trigger.selector);
        bytes memory salt = abi.encodePacked(hex"beaf");

        ExecutiveCommittee.Action memory action = ExecutiveCommittee.Action(to, data, salt);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("ActionMismatch()"));
        _executiveCommitteeWrapper.execute(action);

        vm.prank(_committeeMembers[0]);
        _executiveCommitteeWrapper.vote(action, true);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("QuorumIsNotReached()"));
        _executiveCommitteeWrapper.execute(action);

        for (uint256 i = 0; i < _quorum; ++i) {
            vm.prank(_committeeMembers[i]);
            _executiveCommitteeWrapper.vote(action, true);
        }

        vm.prank(_stranger);
        vm.expectEmit(address(_target));
        emit Target.Executed();
        vm.expectEmit(address(_executiveCommitteeWrapper));
        emit ExecutiveCommittee.ActionExecuted(to, data);

        _executiveCommitteeWrapper.execute(action);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("ActionAlreadyExecuted()"));
        _executiveCommitteeWrapper.execute(action);
    }
}
