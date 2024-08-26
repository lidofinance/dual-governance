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
    event Voted(address indexed signer, bytes32 hash, bool support);
    event TimelockDurationSet(Duration timelockDuration);

    error DuplicatedMember(address account);
    error AccountIsNotMember(address account);
    error CallerIsNotMember(address caller);
    error HashAlreadyUsed(bytes32 hash);
    error QuorumIsNotReached();
    error InvalidQuorum();
    error InvalidTimelockDuration(Duration timelock);
    error TimelockNotPassed();
    error ProposalAlreadyScheduled(bytes32 hash);

    struct HashState {
        Timestamp scheduledAt;
        Timestamp usedAt;
    }

    uint256 public quorum;
    Duration public timelockDuration;

    mapping(bytes32 => HashState) private _hashStates;
    EnumerableSet.AddressSet private _members;
    mapping(address signer => mapping(bytes32 => bool)) public approves;

    constructor(address owner, Duration timelock) Ownable(owner) {
        timelockDuration = timelock;
        emit TimelockDurationSet(timelock);
    }

    /// @notice Casts a vote on a given hash if hash has not been used
    /// @dev Only callable by members
    /// @param hash The hash to vote on
    /// @param support Indicates whether the member supports the hash
    function _vote(bytes32 hash, bool support) internal {
        if (_hashStates[hash].usedAt > Timestamps.from(0)) {
            revert HashAlreadyUsed(hash);
        }

        if (approves[msg.sender][hash] == support) {
            return;
        }

        uint256 heads = _getSupport(hash);
        // heads compares to quorum - 1 because the current vote is not counted yet
        if (heads >= quorum - 1 && support == true && _hashStates[hash].scheduledAt == Timestamps.from(0)) {
            _hashStates[hash].scheduledAt = Timestamps.from(block.timestamp);
        }

        approves[msg.sender][hash] = support;
        emit Voted(msg.sender, hash, support);
    }

    /// @notice Marks a hash as used if quorum is reached and timelock has passed
    /// @dev Internal function that handles marking a hash as used
    /// @param hash The hash to mark as used
    function _markUsed(bytes32 hash) internal {
        if (_hashStates[hash].usedAt > Timestamps.from(0)) {
            revert HashAlreadyUsed(hash);
        }

        uint256 support = _getSupport(hash);

        if (support == 0 || support < quorum) {
            revert QuorumIsNotReached();
        }
        if (timelockDuration.addTo(_hashStates[hash].scheduledAt) > Timestamps.from(block.timestamp)) {
            revert TimelockNotPassed();
        }

        _hashStates[hash].usedAt = Timestamps.from(block.timestamp);

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
        support = _getSupport(hash);
        executionQuorum = quorum;
        scheduledAt = _hashStates[hash].scheduledAt;
        isUsed = _hashStates[hash].usedAt > Timestamps.from(0);
    }

    /// @notice Adds new members to the contract and sets the execution quorum.
    /// @dev This function allows the contract owner to add multiple new members and set the execution quorum.
    ///      The function reverts if the caller is not the owner, if the execution quorum is set to zero,
    ///      or if it exceeds the total number of members.
    /// @param newMembers The array of addresses to be added as new members
    /// @param executionQuorum The minimum number of members required for executing certain operations
    function addMembers(address[] memory newMembers, uint256 executionQuorum) public {
        _checkOwner();

        _addMembers(newMembers, executionQuorum);
    }

    /// @notice Removes specified members from the contract and updates the execution quorum.
    /// @dev This function can only be called by the contract owner. It removes multiple members from
    ///      the contract. If any of the specified members are not found in the members list, the
    ///      function will revert. The quorum is also updated and must not be zero or greater than
    ///      the new total number of members.
    /// @param membersToRemove The array of addresses to be removed from the members list.
    /// @param newQuorum The updated minimum number of members required for executing certain operations.
    function removeMembers(address[] memory membersToRemove, uint256 newQuorum) public {
        _checkOwner();

        for (uint256 i = 0; i < membersToRemove.length; ++i) {
            if (!_members.contains(membersToRemove[i])) {
                revert AccountIsNotMember(membersToRemove[i]);
            }
            _members.remove(membersToRemove[i]);
            emit MemberRemoved(membersToRemove[i]);
        }

        _setQuorum(newQuorum);
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
    function setTimelockDuration(Duration timelock) public {
        _checkOwner();
        if (timelock == timelockDuration) {
            revert InvalidTimelockDuration(timelock);
        }
        timelockDuration = timelock;
        emit TimelockDurationSet(timelock);
    }

    /// @notice Sets the quorum value
    /// @dev Only callable by the owner
    /// @param newQuorum The new quorum value
    function setQuorum(uint256 newQuorum) public {
        _checkOwner();
        _setQuorum(newQuorum);
    }

    /// @notice Schedules a proposal for execution if quorum is reached and it has not been scheduled yet.
    /// @dev This function schedules a proposal for execution if the quorum is reached and
    ///      the proposal has not been scheduled yet. Could happen when execution quorum was set to the same value as
    ///      current support of the proposal.
    /// @param hash The hash of the proposal to be scheduled
    function schedule(bytes32 hash) public {
        if (_hashStates[hash].usedAt > Timestamps.from(0)) {
            revert HashAlreadyUsed(hash);
        }

        if (_getSupport(hash) < quorum) {
            revert QuorumIsNotReached();
        }
        if (_hashStates[hash].scheduledAt > Timestamps.from(0)) {
            revert ProposalAlreadyScheduled(hash);
        }

        _hashStates[hash].scheduledAt = Timestamps.from(block.timestamp);
    }

    /// @notice Sets the execution quorum required for certain operations.
    /// @dev The quorum value must be greater than zero and not exceed the current number of members.
    /// @param executionQuorum The new quorum value to be set.
    function _setQuorum(uint256 executionQuorum) internal {
        if (executionQuorum == 0 || executionQuorum > _members.length() || executionQuorum == quorum) {
            revert InvalidQuorum();
        }
        quorum = executionQuorum;
        emit QuorumSet(executionQuorum);
    }

    /// @notice Adds new members to the contract and sets the execution quorum.
    /// @dev This internal function adds multiple new members and sets the execution quorum.
    ///      The function reverts if the execution quorum is set to zero or exceeds the total number of members.
    /// @param newMembers The array of addresses to be added as new members.
    /// @param executionQuorum The minimum number of members required for executing certain operations.
    function _addMembers(address[] memory newMembers, uint256 executionQuorum) internal {
        for (uint256 i = 0; i < newMembers.length; ++i) {
            if (_members.contains(newMembers[i])) {
                revert DuplicatedMember(newMembers[i]);
            }
            _members.add(newMembers[i]);
            emit MemberAdded(newMembers[i]);
        }

        _setQuorum(executionQuorum);
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
    /// @dev Reverts if the sender is not a member
    function _checkCallerIsMember() internal view {
        if (!_members.contains(msg.sender)) {
            revert CallerIsNotMember(msg.sender);
        }
    }
}
