// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract HashConsensus is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event QuorumSet(uint256 quorum);
    event HashUsed(bytes32 hash);
    event Voted(address indexed signer, bytes32 hash, bool support);
    event TimelockDurationSet(uint256 timelockDuration);

    error IsNotMember();
    error SenderIsNotMember();
    error HashAlreadyUsed();
    error QuorumIsNotReached();
    error InvalidQuorum();
    error DuplicatedMember(address member);
    error TimelockNotPassed();

    struct HashState {
        uint40 quorumAt;
        uint40 usedAt;
    }

    uint256 public quorum;
    uint256 public timelockDuration;

    mapping(bytes32 => HashState) private _hashStates;
    EnumerableSet.AddressSet private _members;
    mapping(address signer => mapping(bytes32 => bool)) public approves;

    constructor(address owner, address[] memory newMembers, uint256 executionQuorum, uint256 timelock) Ownable(owner) {
        if (executionQuorum == 0) {
            revert InvalidQuorum();
        }
        quorum = executionQuorum;
        emit QuorumSet(executionQuorum);

        timelockDuration = timelock;
        emit TimelockDurationSet(timelock);

        for (uint256 i = 0; i < newMembers.length; ++i) {
            _addMember(newMembers[i]);
        }
    }

    function _vote(bytes32 hash, bool support) internal {
        if (_hashStates[hash].usedAt > 0) {
            revert HashAlreadyUsed();
        }

        if (approves[msg.sender][hash] == support) {
            return;
        }

        uint256 heads = _getSupport(hash);
        if (heads == quorum - 1 && support == true) {
            _hashStates[hash].quorumAt = uint40(block.timestamp);
        }

        approves[msg.sender][hash] = support;
        emit Voted(msg.sender, hash, support);
    }

    function _markUsed(bytes32 hash) internal {
        if (_hashStates[hash].usedAt > 0) {
            revert HashAlreadyUsed();
        }
        if (_getSupport(hash) < quorum) {
            revert QuorumIsNotReached();
        }
        if (block.timestamp < _hashStates[hash].quorumAt + timelockDuration) {
            revert TimelockNotPassed();
        }

        _hashStates[hash].usedAt = uint40(block.timestamp);

        emit HashUsed(hash);
    }

    function _getHashState(bytes32 hash)
        internal
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isUsed)
    {
        support = _getSupport(hash);
        execuitionQuorum = quorum;
        isUsed = _hashStates[hash].usedAt > 0;
    }

    function addMember(address newMember, uint256 newQuorum) public onlyOwner {
        _addMember(newMember);

        if (newQuorum == 0 || newQuorum > _members.length()) {
            revert InvalidQuorum();
        }
        quorum = newQuorum;
        emit QuorumSet(newQuorum);
    }

    function removeMember(address memberToRemove, uint256 newQuorum) public onlyOwner {
        if (!_members.contains(memberToRemove)) {
            revert IsNotMember();
        }
        _members.remove(memberToRemove);
        emit MemberRemoved(memberToRemove);

        if (newQuorum == 0 || newQuorum > _members.length()) {
            revert InvalidQuorum();
        }
        quorum = newQuorum;
        emit QuorumSet(newQuorum);
    }

    function getMembers() public view returns (address[] memory) {
        return _members.values();
    }

    function isMember(address member) public view returns (bool) {
        return _members.contains(member);
    }

    function setTimelockDuration(uint256 timelock) public onlyOwner {
        timelockDuration = timelock;
        emit TimelockDurationSet(timelock);
    }

    function setQuorum(uint256 newQuorum) public onlyOwner {
        if (newQuorum == 0 || newQuorum > _members.length()) {
            revert InvalidQuorum();
        }

        quorum = newQuorum;
        emit QuorumSet(newQuorum);
    }

    function _addMember(address newMember) internal {
        if (_members.contains(newMember)) {
            revert DuplicatedMember(newMember);
        }
        _members.add(newMember);
        emit MemberAdded(newMember);
    }

    function _getSupport(bytes32 hash) internal view returns (uint256 support) {
        for (uint256 i = 0; i < _members.length(); ++i) {
            if (approves[_members.at(i)][hash]) {
                support++;
            }
        }
    }

    modifier onlyMember() {
        if (!_members.contains(msg.sender)) {
            revert SenderIsNotMember();
        }
        _;
    }
}
