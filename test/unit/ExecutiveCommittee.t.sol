// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UnitTest} from "test/utils/unit-test.sol";

import {ExecutiveCommittee} from "../../contracts/ExecutiveCommittee.sol";

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
