// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract ExecutiveCommittee is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event QuorumSet(uint256 quorum);
    event VoteExecuted(bytes data);
    event Voted(address indexed signer, bytes data, bool support);
    event TimelockDurationSet(uint256 timelockDuration);

    error IsNotMember();
    error SenderIsNotMember();
    error VoteAlreadyExecuted();
    error QuorumIsNotReached();
    error InvalidQuorum();
    error DuplicatedMember(address member);
    error TimelockNotPassed();

    EnumerableSet.AddressSet private members;
    uint256 public quorum;
    uint256 public timelockDuration;

    struct VoteState {
        bytes data;
        uint256 quorumAt;
        bool isExecuted;
    }

    mapping(bytes32 digest => VoteState) public voteStates;
    mapping(address signer => mapping(bytes32 digest => bool support)) public approves;

    constructor(address owner, address[] memory newMembers, uint256 executionQuorum, uint256 timelock) Ownable(owner) {
        if (executionQuorum == 0) {
            revert InvalidQuorum();
        }
        quorum = executionQuorum;
        emit QuorumSet(executionQuorum);

        timelockDuration = timelock;
        emit TimelockDurationSet(timelock);

        for (uint256 i = 0; i < newMembers.length; ++i) {
            if (members.contains(newMembers[i])) {
                revert DuplicatedMember(newMembers[i]);
            }
            _addMember(newMembers[i]);
        }
    }

    function _vote(bytes memory data, bool support) internal {
        bytes32 digest = keccak256(data);

        if (voteStates[digest].data.length == 0) {
            voteStates[digest].data = data;
        }

        if (voteStates[digest].isExecuted == true) {
            revert VoteAlreadyExecuted();
        }

        if (approves[msg.sender][digest] == support) {
            return;
        }

        uint256 heads = _getSupport(digest);
        if (heads == quorum - 1 && support == true) {
            voteStates[digest].quorumAt = block.timestamp;
        }

        approves[msg.sender][digest] = support;
        emit Voted(msg.sender, data, support);
    }

    function _markExecuted(bytes memory data) internal {
        bytes32 digest = keccak256(data);

        if (voteStates[digest].isExecuted == true) {
            revert VoteAlreadyExecuted();
        }
        if (_getSupport(digest) < quorum) {
            revert QuorumIsNotReached();
        }
        if (block.timestamp < voteStates[digest].quorumAt + timelockDuration) {
            revert TimelockNotPassed();
        }

        voteStates[digest].isExecuted = true;

        emit VoteExecuted(data);
    }

    function _getVoteState(bytes memory data)
        internal
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        bytes32 digest = keccak256(data);

        support = _getSupport(digest);
        execuitionQuorum = quorum;
        isExecuted = voteStates[digest].isExecuted;
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

    function setTimelockDuration(uint256 timelock) public onlyOwner {
        timelockDuration = timelock;
        emit TimelockDurationSet(timelock);
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
}
