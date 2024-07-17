// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title HashConsensus Contract
/// @notice This contract provides a consensus mechanism based on hash voting among members
/// @dev Inherits from Ownable for access control and uses EnumerableSet for member management
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

    /// @notice Casts a vote on a given hash if hash has not been used
    /// @dev Only callable by members
    /// @param hash The hash to vote on
    /// @param support Indicates whether the member supports the hash
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

    /// @notice Marks a hash as used if quorum is reached and timelock has passed
    /// @dev Internal function that handles marking a hash as used
    /// @param hash The hash to mark as used
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

    /// @notice Gets the state of a given hash
    /// @dev Internal function to retrieve the state of a hash
    /// @param hash The hash to get the state for
    /// @return support The number of votes in support of the hash
    /// @return execuitionQuorum The required number of votes for execution
    /// @return isUsed Whether the hash has been used
    function _getHashState(bytes32 hash)
        internal
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isUsed)
    {
        support = _getSupport(hash);
        execuitionQuorum = quorum;
        isUsed = _hashStates[hash].usedAt > 0;
    }

    /// @notice Adds a new member to the committee and updates the quorum
    /// @dev Only callable by the owner
    /// @param newMember The address of the new member
    /// @param newQuorum The new quorum value
    function addMember(address newMember, uint256 newQuorum) public onlyOwner {
        _addMember(newMember);

        if (newQuorum == 0 || newQuorum > _members.length()) {
            revert InvalidQuorum();
        }
        quorum = newQuorum;
        emit QuorumSet(newQuorum);
    }

    /// @notice Removes a member from the committee and updates the quorum
    /// @dev Only callable by the owner
    /// @param memberToRemove The address of the member to remove
    /// @param newQuorum The new quorum value
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

    /// @notice Gets the list of committee members
    /// @dev Public function to return the list of members
    /// @return An array of addresses representing the committee members
    function getMembers() public view returns (address[] memory) {
        return _members.values();
    }

    /// @notice Checks if an address is a member of the committee
    /// @dev Public function to check membership status
    /// @param member The address to check
    /// @return A boolean indicating whether the address is a member
    function isMember(address member) public view returns (bool) {
        return _members.contains(member);
    }

    /// @notice Sets the timelock duration
    /// @dev Only callable by the owner
    /// @param timelock The new timelock duration in seconds
    function setTimelockDuration(uint256 timelock) public onlyOwner {
        timelockDuration = timelock;
        emit TimelockDurationSet(timelock);
    }

    /// @notice Sets the quorum value
    /// @dev Only callable by the owner
    /// @param newQuorum The new quorum value
    function setQuorum(uint256 newQuorum) public onlyOwner {
        if (newQuorum == 0 || newQuorum > _members.length()) {
            revert InvalidQuorum();
        }

        quorum = newQuorum;
        emit QuorumSet(newQuorum);
    }

    /// @notice Adds a new member to the committee
    /// @dev Internal function to add a new member
    /// @param newMember The address of the new member
    function _addMember(address newMember) internal {
        if (_members.contains(newMember)) {
            revert DuplicatedMember(newMember);
        }
        _members.add(newMember);
        emit MemberAdded(newMember);
    }

    /// @notice Gets the number of votes in support of a given hash
    /// @dev Internal function to count the votes in support of a hash
    /// @param hash The hash to check
    /// @return support The number of votes in support of the hash
    function _getSupport(bytes32 hash) internal view returns (uint256 support) {
        for (uint256 i = 0; i < _members.length(); ++i) {
            if (approves[_members.at(i)][hash]) {
                support++;
            }
        }
    }

    /// @notice Restricts access to only committee members
    /// @dev Modifier to ensure that only members can call a function
    modifier onlyMember() {
        if (!_members.contains(msg.sender)) {
            revert SenderIsNotMember();
        }
        _;
    }
}
