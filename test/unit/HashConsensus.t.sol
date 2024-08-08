// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UnitTest} from "test/utils/unit-test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Vm} from "forge-std/Test.sol";

import {HashConsensus} from "../../contracts/committees/HashConsensus.sol";
import {Duration} from "../../contracts/types/Duration.sol";

contract HashConsensusInstance is HashConsensus {
    constructor(
        address owner,
        address[] memory newMembers,
        uint256 executionQuorum,
        uint256 timelock
    ) HashConsensus(owner, newMembers, executionQuorum, timelock) {}
}

abstract contract HashConsensusUnitTest is UnitTest {
    HashConsensus internal _hashConsensus;

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

    function test_constructorInitializesCorrectly() public {
        uint256 timelock = 1;

        vm.expectEmit(true, false, false, true);
        emit HashConsensus.QuorumSet(_quorum);
        vm.expectEmit(true, false, false, true);
        emit HashConsensus.TimelockDurationSet(timelock);

        HashConsensusInstance instance = new HashConsensusInstance(_owner, _committeeMembers, _quorum, timelock);
    }

    function test_constructorRevertsWithZeroQuorum() public {
        uint256 invalidQuorum = 0;

        vm.expectRevert(abi.encodeWithSelector(HashConsensus.InvalidQuorum.selector));
        new HashConsensusInstance(_owner, _committeeMembers, invalidQuorum, 1);
    }

    function test_isMember() public {
        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(_hashConsensus.isMember(_committeeMembers[i]), true);
        }

        assertEq(_hashConsensus.isMember(_owner), false);
        assertEq(_hashConsensus.isMember(_stranger), false);
    }

    function test_getMembers() public {
        address[] memory committeeMembers = _hashConsensus.getMembers();

        assertEq(committeeMembers.length, _committeeMembers.length);

        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(committeeMembers[i], _committeeMembers[i]);
        }
    }

    function test_addMember_stranger_call() public {
        address newMember = makeAddr("NEW_MEMBER");
        assertEq(_hashConsensus.isMember(newMember), false);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _stranger));
        _hashConsensus.addMember(newMember, _quorum);

        for (uint256 i = 0; i < _membersCount; ++i) {
            vm.prank(_committeeMembers[i]);
            vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _committeeMembers[i]));
            _hashConsensus.addMember(newMember, _quorum);
        }
    }

    function test_addMember_reverts_on_duplicate() public {
        address existedMember = _committeeMembers[0];
        assertEq(_hashConsensus.isMember(existedMember), true);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("DuplicatedMember(address)", existedMember));
        _hashConsensus.addMember(existedMember, _quorum);
    }

    function test_addMember_reverts_on_invalid_quorum() public {
        address newMember = makeAddr("NEW_MEMBER");
        assertEq(_hashConsensus.isMember(newMember), false);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.addMember(newMember, 0);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.addMember(newMember, _membersCount + 2);
    }

    function test_addMember() public {
        address newMember = makeAddr("NEW_MEMBER");
        uint256 newQuorum = _quorum + 1;

        assertEq(_hashConsensus.isMember(newMember), false);

        vm.prank(_owner);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.MemberAdded(newMember);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.QuorumSet(newQuorum);
        _hashConsensus.addMember(newMember, newQuorum);

        assertEq(_hashConsensus.isMember(newMember), true);

        address[] memory committeeMembers = _hashConsensus.getMembers();

        assertEq(committeeMembers.length, _membersCount + 1);
        assertEq(committeeMembers[committeeMembers.length - 1], newMember);
    }

    function test_removeMember_stranger_call() public {
        address memberToRemove = _committeeMembers[0];
        assertEq(_hashConsensus.isMember(memberToRemove), true);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _stranger));
        _hashConsensus.removeMember(memberToRemove, _quorum);

        for (uint256 i = 0; i < _membersCount; ++i) {
            vm.prank(_committeeMembers[i]);
            vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _committeeMembers[i]));
            _hashConsensus.removeMember(memberToRemove, _quorum);
        }
    }

    function test_removeMember_reverts_on_member_is_not_exist() public {
        assertEq(_hashConsensus.isMember(_stranger), false);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("IsNotMember()"));
        _hashConsensus.removeMember(_stranger, _quorum);
    }

    function test_removeMember_reverts_on_invalid_quorum() public {
        address memberToRemove = _committeeMembers[0];
        assertEq(_hashConsensus.isMember(memberToRemove), true);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.removeMember(memberToRemove, 0);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.removeMember(memberToRemove, _membersCount);
    }

    function test_removeMember() public {
        address memberToRemove = _committeeMembers[0];
        uint256 newQuorum = _quorum - 1;

        assertEq(_hashConsensus.isMember(memberToRemove), true);

        vm.prank(_owner);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.MemberRemoved(memberToRemove);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.QuorumSet(newQuorum);
        _hashConsensus.removeMember(memberToRemove, newQuorum);

        assertEq(_hashConsensus.isMember(memberToRemove), false);

        address[] memory committeeMembers = _hashConsensus.getMembers();

        assertEq(committeeMembers.length, _membersCount - 1);
        for (uint256 i = 0; i < committeeMembers.length; ++i) {
            assertNotEq(committeeMembers[i], memberToRemove);
        }
    }

    function test_setTimelockDurationByOwner() public {
        uint256 newTimelockDuration = 200;

        vm.expectEmit(true, false, false, true);
        emit HashConsensus.TimelockDurationSet(newTimelockDuration);

        vm.prank(_owner);
        _hashConsensus.setTimelockDuration(newTimelockDuration);

        assertEq(_hashConsensus.timelockDuration(), newTimelockDuration);
    }

    function test_setTimelockDurationRevertsIfNotOwner() public {
        uint256 newTimelockDuration = 200;

        vm.prank(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x123)));
        _hashConsensus.setTimelockDuration(newTimelockDuration);
    }

    function testTimelockDurationEventEmitted() public {
        uint256 newTimelockDuration = 300;

        vm.expectEmit(true, false, false, true);
        emit HashConsensus.TimelockDurationSet(newTimelockDuration);

        vm.prank(_owner);
        _hashConsensus.setTimelockDuration(newTimelockDuration);
    }

    function test_setQuorumByOwner() public {
        uint256 newQuorum = 2;

        vm.expectEmit(true, false, false, true);
        emit HashConsensus.QuorumSet(newQuorum);

        vm.prank(_owner);
        _hashConsensus.setQuorum(newQuorum);

        // Assert that the quorum was updated correctly
        assertEq(_hashConsensus.quorum(), newQuorum);
    }

    function test_setQuorumRevertsIfNotOwner() public {
        uint256 newQuorum = 2;

        vm.prank(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x123)));
        _hashConsensus.setQuorum(newQuorum);
    }

    function test_setQuorumRevertsIfZeroQuorum() public {
        uint256 invalidQuorum = 0;

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.setQuorum(invalidQuorum);
    }

    function test_setQuorumRevertsIfQuorumExceedsMembers() public {
        uint256 invalidQuorum = _committeeMembers.length + 1;

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.setQuorum(invalidQuorum);
    }

    function test_quorumEventEmitted() public {
        uint256 newQuorum = 3;

        vm.expectEmit(true, false, false, true);
        emit HashConsensus.QuorumSet(newQuorum);

        vm.prank(_owner);
        _hashConsensus.setQuorum(newQuorum);
    }
}

contract Target {
    event Executed();

    function trigger() public {
        emit Executed();
    }
}

contract HashConsensusWrapper is HashConsensus {
    event OnlyMemberModifierPassed();

    Target internal _target;

    constructor(
        address owner,
        address[] memory newMembers,
        uint256 executionQuorum,
        uint256 timelock,
        Target target
    ) HashConsensus(owner, newMembers, executionQuorum, timelock) {
        _target = target;
    }

    function vote(bytes32 hash, bool support) public {
        _vote(hash, support);
    }

    function execute(bytes32 hash) public {
        _markUsed(hash);
        _target.trigger();
    }

    function getHashState(bytes32 hash)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getHashState(hash);
    }

    function getSupport(bytes32 hash) public view returns (uint256 support) {
        return _getSupport(hash);
    }

    function onlyMemberProtected() public {
        _checkSenderIsMember();
        emit OnlyMemberModifierPassed();
    }
}

contract HashConsensusInternalUnitTest is HashConsensusUnitTest {
    HashConsensusWrapper internal _hashConsensusWrapper;
    Target internal _target;
    Duration internal _timelock = Duration.wrap(3600);

    bytes internal data;
    bytes32 internal dataHash;

    function setUp() public {
        _target = new Target();
        _hashConsensusWrapper =
            new HashConsensusWrapper(_owner, _committeeMembers, _quorum, _timelock.toSeconds(), _target);
        _hashConsensus = HashConsensus(_hashConsensusWrapper);
        data = abi.encode(address(_target));
        dataHash = keccak256(data);
    }

    function test_getSupport() public {
        assertEq(_hashConsensusWrapper.getSupport(dataHash), 0);

        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(_hashConsensusWrapper.getSupport(dataHash), i);
            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(dataHash, true);
            assertEq(_hashConsensusWrapper.getSupport(dataHash), i + 1);
        }

        assertEq(_hashConsensusWrapper.getSupport(dataHash), _membersCount);

        for (uint256 i = 0; i < _membersCount; ++i) {
            assertEq(_hashConsensusWrapper.getSupport(dataHash), _membersCount - i);
            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(dataHash, false);
            assertEq(_hashConsensusWrapper.getSupport(dataHash), _membersCount - i - 1);
        }

        assertEq(_hashConsensusWrapper.getSupport(dataHash), 0);
    }

    function test_getHashState() public {
        uint256 support;
        uint256 execuitionQuorum;
        bool isExecuted;

        (support, execuitionQuorum, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
        assertEq(support, 0);
        assertEq(execuitionQuorum, _quorum);
        assertEq(isExecuted, false);

        for (uint256 i = 0; i < _membersCount; ++i) {
            (support, execuitionQuorum, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
            assertEq(support, i);
            assertEq(execuitionQuorum, _quorum);
            assertEq(isExecuted, false);

            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(dataHash, true);

            (support, execuitionQuorum, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
            assertEq(support, i + 1);
            assertEq(execuitionQuorum, _quorum);
            assertEq(isExecuted, false);
        }

        (support, execuitionQuorum, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
        assertEq(support, _membersCount);
        assertEq(execuitionQuorum, _quorum);
        assertEq(isExecuted, false);

        _wait(_timelock);

        _hashConsensusWrapper.execute(dataHash);

        (support, execuitionQuorum, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
        assertEq(support, _membersCount);
        assertEq(execuitionQuorum, _quorum);
        assertEq(isExecuted, true);
    }

    function test_vote() public {
        assertEq(_hashConsensusWrapper.approves(_committeeMembers[0], dataHash), false);

        vm.prank(_committeeMembers[0]);
        vm.expectEmit(address(_hashConsensusWrapper));
        emit HashConsensus.Voted(_committeeMembers[0], dataHash, true);
        _hashConsensusWrapper.vote(dataHash, true);
        assertEq(_hashConsensusWrapper.approves(_committeeMembers[0], dataHash), true);

        vm.prank(_committeeMembers[0]);
        vm.recordLogs();
        _hashConsensusWrapper.vote(dataHash, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
        assertEq(_hashConsensusWrapper.approves(_committeeMembers[0], dataHash), true);

        vm.prank(_committeeMembers[0]);
        vm.expectEmit(address(_hashConsensusWrapper));
        emit HashConsensus.Voted(_committeeMembers[0], dataHash, false);
        _hashConsensusWrapper.vote(dataHash, false);
        assertEq(_hashConsensusWrapper.approves(_committeeMembers[0], dataHash), false);

        vm.prank(_committeeMembers[0]);
        vm.recordLogs();
        _hashConsensusWrapper.vote(dataHash, false);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
        assertEq(_hashConsensusWrapper.approves(_committeeMembers[0], dataHash), false);
    }

    function test_vote_reverts_on_executed() public {
        for (uint256 i = 0; i < _quorum; ++i) {
            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(dataHash, true);
        }

        _wait(_timelock);

        _hashConsensusWrapper.execute(dataHash);

        vm.prank(_committeeMembers[0]);
        vm.expectRevert(abi.encodeWithSignature("HashAlreadyUsed()"));
        _hashConsensusWrapper.vote(dataHash, true);
    }

    function test_execute_events() public {
        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("QuorumIsNotReached()"));
        _hashConsensusWrapper.execute(dataHash);

        for (uint256 i = 0; i < _quorum; ++i) {
            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(dataHash, true);
        }

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("TimelockNotPassed()"));
        _hashConsensusWrapper.execute(dataHash);

        _wait(_timelock);
        vm.prank(_stranger);
        vm.expectEmit(address(_hashConsensusWrapper));
        emit HashConsensus.HashUsed(dataHash);
        vm.expectEmit(address(_target));
        emit Target.Executed();
        _hashConsensusWrapper.execute(dataHash);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("HashAlreadyUsed()"));
        _hashConsensusWrapper.execute(dataHash);
    }

    function test_onlyMemberModifier() public {
        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("SenderIsNotMember()"));
        _hashConsensusWrapper.onlyMemberProtected();

        vm.prank(_committeeMembers[0]);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensusWrapper.OnlyMemberModifierPassed();
        _hashConsensusWrapper.onlyMemberProtected();
    }
}
