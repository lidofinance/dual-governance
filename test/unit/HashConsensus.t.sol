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
    ) HashConsensus(owner, timelock) {
        _addMembers(newMembers, executionQuorum);
    }
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

        vm.expectEmit();
        emit Ownable.OwnershipTransferred(address(0), _owner);
        vm.expectEmit();
        emit HashConsensus.TimelockDurationSet(timelock);
        for (uint256 i = 0; i < _committeeMembers.length; i++) {
            vm.expectEmit();
            emit HashConsensus.MemberAdded(_committeeMembers[i]);
        }
        vm.expectEmit();
        emit HashConsensus.QuorumSet(_quorum);

        new HashConsensusInstance(_owner, _committeeMembers, _quorum, timelock);
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

    function test_addMembers_stranger_call() public {
        address[] memory membersToAdd = new address[](1);
        membersToAdd[0] = makeAddr("NEW_MEMBER");
        assertEq(_hashConsensus.isMember(membersToAdd[0]), false);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _stranger));
        _hashConsensus.addMembers(membersToAdd, _quorum);

        for (uint256 i = 0; i < _membersCount; ++i) {
            vm.prank(_committeeMembers[i]);
            vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _committeeMembers[i]));
            _hashConsensus.addMembers(membersToAdd, _quorum);
        }
    }

    function test_addMembers_reverts_on_duplicate() public {
        address[] memory membersToAdd = new address[](1);
        membersToAdd[0] = _committeeMembers[0];
        assertEq(_hashConsensus.isMember(membersToAdd[0]), true);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("DuplicatedMember(address)", membersToAdd[0]));
        _hashConsensus.addMembers(membersToAdd, _quorum);
    }

    function test_addMembers_reverts_on_duplicate_in_array() public {
        address[] memory membersToAdd = new address[](2);
        membersToAdd[0] = makeAddr("NEW_MEMBER");
        membersToAdd[1] = makeAddr("NEW_MEMBER");
        assertEq(_hashConsensus.isMember(membersToAdd[0]), false);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("DuplicatedMember(address)", membersToAdd[1]));
        _hashConsensus.addMembers(membersToAdd, _quorum);
    }

    function test_addMember_reverts_on_invalid_quorum() public {
        address[] memory membersToAdd = new address[](1);
        membersToAdd[0] = makeAddr("NEW_MEMBER");
        assertEq(_hashConsensus.isMember(membersToAdd[0]), false);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.addMembers(membersToAdd, 0);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.addMembers(membersToAdd, _membersCount + 2);
    }

    function test_addMember() public {
        address[] memory membersToAdd = new address[](2);
        membersToAdd[0] = makeAddr("NEW_MEMBER_1");
        membersToAdd[1] = makeAddr("NEW_MEMBER_2");
        assertEq(_hashConsensus.isMember(membersToAdd[0]), false);
        assertEq(_hashConsensus.isMember(membersToAdd[1]), false);

        uint256 newQuorum = _quorum + 1;

        vm.prank(_owner);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.MemberAdded(membersToAdd[0]);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.MemberAdded(membersToAdd[1]);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.QuorumSet(newQuorum);
        _hashConsensus.addMembers(membersToAdd, newQuorum);

        assertEq(_hashConsensus.isMember(membersToAdd[0]), true);
        assertEq(_hashConsensus.isMember(membersToAdd[1]), true);

        address[] memory committeeMembers = _hashConsensus.getMembers();

        assertEq(committeeMembers.length, _membersCount + 2);
        assertEq(committeeMembers[committeeMembers.length - 2], membersToAdd[0]);
        assertEq(committeeMembers[committeeMembers.length - 1], membersToAdd[1]);
    }

    function test_removeMembers_stranger_call() public {
        address[] memory membersToRemove = new address[](1);
        membersToRemove[0] = _committeeMembers[0];
        assertEq(_hashConsensus.isMember(membersToRemove[0]), true);

        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _stranger));
        _hashConsensus.removeMembers(membersToRemove, _quorum);

        for (uint256 i = 0; i < _membersCount; ++i) {
            vm.prank(_committeeMembers[i]);
            vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _committeeMembers[i]));
            _hashConsensus.removeMembers(membersToRemove, _quorum);
        }
    }

    function test_removeMembers_reverts_on_member_is_not_exist() public {
        address[] memory membersToRemove = new address[](1);
        membersToRemove[0] = _stranger;
        assertEq(_hashConsensus.isMember(membersToRemove[0]), false);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.AccountIsNotMember.selector, _stranger));
        _hashConsensus.removeMembers(membersToRemove, _quorum);
    }

    function test_removeMembers_reverts_on_member_duplicate_in_array() public {
        address[] memory membersToRemove = new address[](2);
        membersToRemove[0] = _committeeMembers[0];
        membersToRemove[1] = _committeeMembers[0];
        assertEq(_hashConsensus.isMember(membersToRemove[0]), true);
        assertEq(_hashConsensus.isMember(membersToRemove[1]), true);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.AccountIsNotMember.selector, _committeeMembers[0]));
        _hashConsensus.removeMembers(membersToRemove, _quorum);
    }

    function test_removeMembers_reverts_on_invalid_quorum() public {
        address[] memory membersToRemove = new address[](1);
        membersToRemove[0] = _committeeMembers[0];
        assertEq(_hashConsensus.isMember(membersToRemove[0]), true);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.removeMembers(membersToRemove, 0);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuorum()"));
        _hashConsensus.removeMembers(membersToRemove, _membersCount);
    }

    function test_removeMembers() public {
        address[] memory membersToRemove = new address[](2);
        membersToRemove[0] = _committeeMembers[0];
        membersToRemove[1] = _committeeMembers[1];
        assertEq(_hashConsensus.isMember(membersToRemove[0]), true);
        assertEq(_hashConsensus.isMember(membersToRemove[1]), true);
        uint256 newQuorum = _quorum - 2;

        vm.prank(_owner);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.MemberRemoved(membersToRemove[0]);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.MemberRemoved(membersToRemove[1]);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensus.QuorumSet(newQuorum);
        _hashConsensus.removeMembers(membersToRemove, newQuorum);

        assertEq(_hashConsensus.isMember(membersToRemove[0]), false);
        assertEq(_hashConsensus.isMember(membersToRemove[1]), false);

        address[] memory committeeMembers = _hashConsensus.getMembers();

        assertEq(committeeMembers.length, _membersCount - 2);
        for (uint256 i = 0; i < committeeMembers.length; ++i) {
            assertNotEq(committeeMembers[i], membersToRemove[0]);
            assertNotEq(committeeMembers[i], membersToRemove[1]);
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

    function test_setTimelockDurationRevertsIfValueIsSame() public {
        uint256 newTimelockDuration = 300;

        vm.startPrank(_owner);
        _hashConsensus.setTimelockDuration(newTimelockDuration);

        vm.expectRevert(abi.encodeWithSelector(HashConsensus.InvalidTimelockDuration.selector, newTimelockDuration));
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

    function test_setQuorumRevertsIfQuorumIsSame() public {
        uint256 invalidQuorum = 2;

        vm.startPrank(_owner);
        _hashConsensus.setQuorum(invalidQuorum);

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
    ) HashConsensus(owner, timelock) {
        _target = target;
        _addMembers(newMembers, executionQuorum);
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
        returns (uint256 support, uint256 executionQuorum, uint256 scheduledAt, bool isExecuted)
    {
        return _getHashState(hash);
    }

    function getSupport(bytes32 hash) public view returns (uint256 support) {
        return _getSupport(hash);
    }

    function onlyMemberProtected() public {
        _checkCallerIsMember();
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
        uint256 executionQuorum;
        uint256 scheduledAt;
        bool isExecuted;

        (support, executionQuorum, scheduledAt, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
        assertEq(support, 0);
        assertEq(executionQuorum, _quorum);
        assertEq(scheduledAt, 0);
        assertEq(isExecuted, false);

        uint256 expectedQuorumAt = block.timestamp;

        for (uint256 i = 0; i < _membersCount; ++i) {
            (support, executionQuorum, scheduledAt, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
            assertEq(support, i);
            assertEq(executionQuorum, _quorum);
            if (i >= executionQuorum) {
                assertEq(scheduledAt, expectedQuorumAt);
            } else {
                assertEq(scheduledAt, 0);
            }
            assertEq(isExecuted, false);

            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(dataHash, true);

            (support, executionQuorum, scheduledAt, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
            assertEq(support, i + 1);
            assertEq(executionQuorum, _quorum);
            if (i >= executionQuorum - 1) {
                assertEq(scheduledAt, expectedQuorumAt);
            } else {
                assertEq(scheduledAt, 0);
            }
            assertEq(isExecuted, false);
        }

        (support, executionQuorum, scheduledAt, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
        assertEq(support, _membersCount);
        assertEq(executionQuorum, _quorum);
        assertEq(scheduledAt, expectedQuorumAt);
        assertEq(isExecuted, false);

        _wait(_timelock);

        _hashConsensusWrapper.execute(dataHash);

        (support, executionQuorum, scheduledAt, isExecuted) = _hashConsensusWrapper.getHashState(dataHash);
        assertEq(support, _membersCount);
        assertEq(executionQuorum, _quorum);
        assertEq(scheduledAt, expectedQuorumAt);
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
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.HashAlreadyUsed.selector, dataHash));
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
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.HashAlreadyUsed.selector, dataHash));
        _hashConsensusWrapper.execute(dataHash);
    }

    function test_onlyMemberModifier() public {
        vm.prank(_stranger);
        vm.expectRevert(abi.encodeWithSelector(HashConsensus.CallerIsNotMember.selector, _stranger));
        _hashConsensusWrapper.onlyMemberProtected();

        vm.prank(_committeeMembers[0]);
        vm.expectEmit(address(_hashConsensus));
        emit HashConsensusWrapper.OnlyMemberModifierPassed();
        _hashConsensusWrapper.onlyMemberProtected();
    }

    function test_scheduleProposalRevertsIfHashIsUsed() public {
        bytes32 hash = keccak256("hash");

        for (uint256 i = 0; i < _quorum; ++i) {
            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(hash, true);
        }

        _wait(Duration.wrap(3600));

        _hashConsensusWrapper.execute(hash);

        vm.expectRevert(abi.encodeWithSelector(HashConsensus.HashAlreadyUsed.selector, hash));
        _hashConsensusWrapper.scheduleProposal(hash);
    }

    function test_scheduleProposalDoNothingIfQuorumAlreadyReached() public {
        bytes32 hash = keccak256("hash");

        for (uint256 i = 0; i < _quorum; ++i) {
            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(hash, true);
        }

        (,, uint256 scheduledAtBefore,) = _hashConsensusWrapper.getHashState(hash);

        _wait(_timelock);
        _hashConsensusWrapper.scheduleProposal(hash);

        (,, uint256 scheduledAtAfter,) = _hashConsensusWrapper.getHashState(hash);

        assertEq(scheduledAtBefore, scheduledAtAfter);
    }

    function test_scheduleProposalDoNothingIfQuorumIsNotReached() public {
        bytes32 hash = keccak256("hash");

        for (uint256 i = 0; i < _quorum - 1; ++i) {
            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(hash, true);
        }

        (,, uint256 scheduledAtBefore,) = _hashConsensusWrapper.getHashState(hash);
        assertEq(scheduledAtBefore, 0);

        _hashConsensusWrapper.scheduleProposal(hash);

        (,, uint256 scheduledAtAfter,) = _hashConsensusWrapper.getHashState(hash);
        assertEq(scheduledAtAfter, 0);
    }

    function test_scheduleProposal() public {
        bytes32 hash = keccak256("hash");

        for (uint256 i = 0; i < _quorum - 1; ++i) {
            vm.prank(_committeeMembers[i]);
            _hashConsensusWrapper.vote(hash, true);
        }

        vm.prank(_owner);
        _hashConsensusWrapper.setQuorum(_quorum - 1);

        (,, uint256 scheduledAtBefore,) = _hashConsensusWrapper.getHashState(hash);

        assertEq(scheduledAtBefore, 0);

        _hashConsensusWrapper.scheduleProposal(hash);

        (,, uint256 scheduledAtAfter,) = _hashConsensusWrapper.getHashState(hash);

        assertEq(scheduledAtAfter, block.timestamp);
    }
}
