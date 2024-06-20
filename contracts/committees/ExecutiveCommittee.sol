// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract ExecutiveCommittee {
    using EnumerableSet for EnumerableSet.AddressSet;

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event QuorumSet(uint256 quorum);
    event VoteExecuted(address indexed to, bytes data);
    event Voted(address indexed signer, bool support, address indexed to, bytes data);

    error IsNotMember();
    error SenderIsNotMember();
    error SenderIsNotOwner();
    error VoteAlreadyExecuted();
    error QuorumIsNotReached();
    error InvalidQuorum();
    error DuplicatedMember(address member);

    address public immutable OWNER;

    EnumerableSet.AddressSet private members;
    uint256 public quorum;

    mapping(bytes32 digest => bool isEecuted) public voteStates;
    mapping(address signer => mapping(bytes32 digest => bool support)) public approves;

    constructor(address owner, address[] memory newMembers, uint256 executionQuorum) {
        if (executionQuorum == 0) {
            revert InvalidQuorum();
        }
        quorum = executionQuorum;
        emit QuorumSet(executionQuorum);

        OWNER = owner;

        for (uint256 i = 0; i < newMembers.length; ++i) {
            if (members.contains(newMembers[i])) {
                revert DuplicatedMember(newMembers[i]);
            }
            _addMember(newMembers[i]);
        }
    }

    function _vote(bytes32 digest, bool support) internal {
        if (voteStates[digest] == true) {
            revert VoteAlreadyExecuted();
        }

        if (approves[msg.sender][digest] == support) {
            return;
        }

        approves[msg.sender][digest] = support;
        emit Voted(msg.sender, digest);
    }

    function _markExecuted(bytes32 digest) internal {
        if (voteStates[digest] == true) {
            revert VoteAlreadyExecuted();
        }
        if (_getSupport(digest) < quorum) {
            revert QuorumIsNotReached();
        }

        voteStates[digest] = true;

        emit VoteExecuted(digest);
    }

    function _getVoteState(bytes32 digest)
        internal
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        support = _getSupport(digest);
        execuitionQuorum = quorum;
        isExecuted = voteStates[digest];
    }

    function addMember(address newMember, uint256 newQuorum) public onlyOwner {
        _addMember(newMember);

        if (newQuorum == 0 || newQuorum > members.length()) {
            revert InvalidQuorum();
        }
        quorum = newQuorum;
        emit QuorumSet(newQuorum);
    }

    function removeMember(address memberToRemove, uint256 newQuorum) public onlyOwner {
        if (!members.contains(memberToRemove)) {
            revert IsNotMember();
        }
        members.remove(memberToRemove);
        emit MemberRemoved(memberToRemove);

        if (newQuorum == 0 || newQuorum > members.length()) {
            revert InvalidQuorum();
        }
        quorum = newQuorum;
        emit QuorumSet(newQuorum);
    }

    function getMembers() public view returns (address[] memory) {
        return members.values();
    }

    function isMember(address member) public view returns (bool) {
        return members.contains(member);
    }

    function _addMember(address newMember) internal {
        if (members.contains(newMember)) {
            revert DuplicatedMember(newMember);
        }
        members.add(newMember);
        emit MemberAdded(newMember);
    }

    function _getSupport(bytes32 digest) internal view returns (uint256 support) {
        for (uint256 i = 0; i < members.length(); ++i) {
            if (approves[members.at(i)][digest]) {
                support++;
            }
        }
    }

    modifier onlyMember() {
        if (!members.contains(msg.sender)) {
            revert SenderIsNotMember();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert SenderIsNotOwner();
        }
        _;
    }
}
