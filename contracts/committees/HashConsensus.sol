// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

/// @title HashConsensus Contract
/// @notice This contract provides a consensus mechanism based on hash voting among members
/// @dev Inherits from Ownable for access control and uses EnumerableSet for member management
abstract contract HashConsensus is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event QuorumSet(uint256 quorum);
    event HashUsed(bytes32 hash);
    event HashScheduled(bytes32 hash);
    event Voted(address indexed signer, bytes32 hash, bool support);
    event TimelockDurationSet(Duration timelockDuration);

    error DuplicatedMember(address account);
    error InvalidMemberAccount(address account);
    error AccountIsNotMember(address account);
    error CallerIsNotMember(address caller);
    error HashAlreadyUsed(bytes32 hash);
    error HashIsNotScheduled(bytes32 hash);
    error HashAlreadyScheduled(bytes32 hash);
    error QuorumIsNotReached();
    error InvalidQuorum();
    error InvalidTimelockDuration(Duration timelock);
    error TimelockNotPassed();

    /// @notice Represents current and historical state of a hash
    /// @param scheduledAt The timestamp when the hash was scheduled
    /// @param usedAt The timestamp when the hash was used
    /// @param supportWhenScheduled The number of votes in support when the hash was scheduled
    /// @param quorumWhenScheduled The required number of votes for execution when the hash was scheduled
    struct HashState {
        Timestamp scheduledAt;
        Timestamp usedAt;
        uint256 supportWhenScheduled;
        uint256 quorumWhenScheduled;
    }

    uint256 private _quorum;
    Duration private _timelockDuration;

    mapping(bytes32 hash => HashState state) private _hashStates;
    EnumerableSet.AddressSet private _members;
    mapping(address signer => mapping(bytes32 hash => bool approve)) public approves;

    constructor(address owner, Duration timelock) Ownable(owner) {
        _timelockDuration = timelock;
        emit TimelockDurationSet(timelock);
    }

    /// @notice Gets the list of committee members
    /// @dev Public function to return the list of members
    /// @return An array of addresses representing the committee members
    function getMembers() external view returns (address[] memory) {
        return _members.values();
    }

    /// @notice Adds new members to the contract and sets the execution quorum.
    /// @dev This function allows the contract owner to add multiple new members and set the execution quorum.
    ///      The function reverts if the caller is not the owner, if the execution quorum is set to zero,
    ///      or if it exceeds the total number of members.
    /// @param newMembers The array of addresses to be added as new members
    /// @param executionQuorum The minimum number of members required for executing certain operations
    function addMembers(address[] memory newMembers, uint256 executionQuorum) external {
        _checkOwner();

        _addMembers(newMembers, executionQuorum);
    }

    /// @notice Removes specified members from the contract and updates the execution quorum.
    /// @dev This function can only be called by the contract owner. It removes multiple members from
    ///      the contract. If any of the specified members are not found in the members list, the
    ///      function will revert. The quorum is also updated and must not be zero or greater than
    ///      the new total number of members.
    /// @param membersToRemove The array of addresses to be removed from the members list.
    /// @param executionQuorum The updated minimum number of members required for executing certain operations.
    function removeMembers(address[] memory membersToRemove, uint256 executionQuorum) external {
        _checkOwner();

        _removeMembers(membersToRemove, executionQuorum);
    }

    /// @notice Checks if an address is a member of the committee
    /// @dev Public function to check membership status
    /// @param member The address to check
    /// @return A boolean indicating whether the address is a member
    function isMember(address member) external view returns (bool) {
        return _members.contains(member);
    }

    /// @notice Gets the timelock duration value
    function getTimelockDuration() external view returns (Duration) {
        return _timelockDuration;
    }

    /// @notice Sets the timelock duration
    /// @dev Only callable by the owner
    /// @param newTimelock The new timelock duration in seconds
    function setTimelockDuration(Duration newTimelock) external {
        _checkOwner();
        if (newTimelock == _timelockDuration) {
            revert InvalidTimelockDuration(newTimelock);
        }
        _timelockDuration = newTimelock;
        emit TimelockDurationSet(newTimelock);
    }

    /// @notice Gets the quorum value
    function getQuorum() external view returns (uint256) {
        return _quorum;
    }

    /// @notice Sets the quorum value
    /// @dev Only callable by the owner
    /// @param newQuorum The new quorum value
    function setQuorum(uint256 newQuorum) external {
        _checkOwner();

        if (newQuorum == _quorum) {
            revert InvalidQuorum();
        }

        _setQuorum(newQuorum);
    }

    /// @notice Schedules a proposal for execution if quorum is reached and it has not been scheduled yet.
    /// @dev This function schedules a proposal for execution if the quorum is reached and
    ///      the proposal has not been scheduled yet. Could happen when execution quorum was set to the same value as
    ///      current support of the proposal.
    /// @param hash The hash of the proposal to be scheduled
    function schedule(bytes32 hash) external {
        HashState storage state = _hashStates[hash];
        if (state.scheduledAt.isNotZero()) {
            revert HashAlreadyScheduled(hash);
        }

        uint256 currentQuorum = _quorum;

        if (currentQuorum == 0) {
            revert InvalidQuorum();
        }

        uint256 currentSupport = _getSupport(hash);

        if (currentSupport < currentQuorum) {
            revert QuorumIsNotReached();
        }

        state.scheduledAt = Timestamps.now();
        state.supportWhenScheduled = currentSupport;
        state.quorumWhenScheduled = currentQuorum;
        emit HashScheduled(hash);
    }

    /// @notice Casts a vote on a given hash if hash has not been used
    /// @dev Only callable by members
    /// @param hash The hash to vote on
    /// @param support Indicates whether the member supports the hash
    function _vote(bytes32 hash, bool support) internal {
        HashState storage state = _hashStates[hash];
        if (state.scheduledAt.isNotZero()) {
            revert HashAlreadyScheduled(hash);
        }

        approves[msg.sender][hash] = support;
        emit Voted(msg.sender, hash, support);

        uint256 currentSupport = _getSupport(hash);
        uint256 currentQuorum = _quorum;

        if (currentSupport >= currentQuorum) {
            state.scheduledAt = Timestamps.now();
            state.supportWhenScheduled = currentSupport;
            state.quorumWhenScheduled = currentQuorum;
            emit HashScheduled(hash);
        }
    }

    /// @notice Marks a hash as used if quorum is reached and timelock has passed
    /// @dev Internal function that handles marking a hash as used
    /// @param hash The hash to mark as used
    function _markUsed(bytes32 hash) internal {
        if (_hashStates[hash].scheduledAt.isZero()) {
            revert HashIsNotScheduled(hash);
        }

        if (_hashStates[hash].usedAt.isNotZero()) {
            revert HashAlreadyUsed(hash);
        }

        if (_timelockDuration.addTo(_hashStates[hash].scheduledAt) > Timestamps.now()) {
            revert TimelockNotPassed();
        }

        _hashStates[hash].usedAt = Timestamps.now();

        emit HashUsed(hash);
    }

    /// @notice Gets the state of a given hash
    /// @dev Internal function to retrieve the state of a hash
    /// @param hash The hash to get the state for
    /// @return support The number of votes in support of the hash
    /// @return executionQuorum The required number of votes for execution
    /// @return scheduledAt The timestamp when the quorum was reached or scheduleProposal was called
    /// @return isUsed Whether the hash has been used
    function _getHashState(bytes32 hash)
        internal
        view
        returns (uint256 support, uint256 executionQuorum, Timestamp scheduledAt, bool isUsed)
    {
        HashState storage hashState = _hashStates[hash];
        scheduledAt = hashState.scheduledAt;
        isUsed = hashState.usedAt.isNotZero();
        if (scheduledAt.isZero()) {
            support = _getSupport(hash);
            executionQuorum = _quorum;
        } else {
            support = hashState.supportWhenScheduled;
            executionQuorum = hashState.quorumWhenScheduled;
        }
    }

    /// @notice Sets the execution quorum required for certain operations.
    /// @dev The quorum value must be greater than zero and not exceed the current number of members.
    /// @param executionQuorum The new quorum value to be set.
    function _setQuorum(uint256 executionQuorum) internal {
        if (executionQuorum == 0 || executionQuorum > _members.length()) {
            revert InvalidQuorum();
        }

        if (executionQuorum != _quorum) {
            _quorum = executionQuorum;
            emit QuorumSet(executionQuorum);
        }
    }

    /// @notice Adds new members to the contract and sets the execution quorum.
    /// @dev This internal function adds multiple new members and sets the execution quorum.
    ///      The function reverts if the execution quorum is set to zero or exceeds the total number of members.
    /// @param newMembers The array of addresses to be added as new members.
    /// @param executionQuorum The minimum number of members required for executing certain operations.
    function _addMembers(address[] memory newMembers, uint256 executionQuorum) internal {
        uint256 membersCount = newMembers.length;

        for (uint256 i = 0; i < membersCount; ++i) {
            if (newMembers[i] == address(0)) {
                revert InvalidMemberAccount(newMembers[i]);
            }
            if (!_members.add(newMembers[i])) {
                revert DuplicatedMember(newMembers[i]);
            }
            emit MemberAdded(newMembers[i]);
        }

        _setQuorum(executionQuorum);
    }

    /// @notice Removes specified members from the contract and updates the execution quorum.
    /// @dev This internal function removes multiple members from the contract. If any of the specified members are not
    ///      found in the members list, the function will revert. The quorum is also updated and must not be zero or
    ///      greater than the new total number of members.
    /// @param membersToRemove The array of addresses to be removed from the members list.
    /// @param executionQuorum The updated minimum number of members required for executing certain operations.
    function _removeMembers(address[] memory membersToRemove, uint256 executionQuorum) internal {
        uint256 membersCount = membersToRemove.length;

        for (uint256 i = 0; i < membersCount; ++i) {
            if (!_members.remove(membersToRemove[i])) {
                revert AccountIsNotMember(membersToRemove[i]);
            }
            emit MemberRemoved(membersToRemove[i]);
        }

        _setQuorum(executionQuorum);
    }

    /// @notice Gets the number of votes in support of a given hash
    /// @dev Internal function to count the votes in support of a hash
    /// @param hash The hash to check
    /// @return support The number of votes in support of the hash
    function _getSupport(bytes32 hash) internal view returns (uint256 support) {
        uint256 membersCount = _members.length();

        for (uint256 i = 0; i < membersCount; ++i) {
            if (approves[_members.at(i)][hash]) {
                support++;
            }
        }
    }

    /// @notice Restricts access to only committee members
    /// @dev Reverts if the sender is not a member
    function _checkCallerIsMember() internal view {
        if (!_members.contains(msg.sender)) {
            revert CallerIsNotMember(msg.sender);
        }
    }
}
