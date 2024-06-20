// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract ExecutiveCommittee {
    using EnumerableSet for EnumerableSet.AddressSet;

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event QuorumSet(uint256 quorum);
    event ActionProposed(address indexed to, bytes data);
    event ActionExecuted(address indexed to, bytes data);
    event ActionVoted(address indexed signer, bool support, address indexed to, bytes data);

    error IsNotMember();
    error SenderIsNotMember();
    error SenderIsNotOwner();
    error DataIsNotEqual();
    error ActionAlreadyExecuted();
    error QuorumIsNotReached();
    error InvalidQuorum();
    error ActionMismatch();
    error DuplicatedMember(address member);

    struct Action {
        address to;
        bytes data;
        bytes salt;
    }

    struct ActionState {
        Action action;
        bool isExecuted;
    }

    address public immutable OWNER;

    EnumerableSet.AddressSet private members;
    uint256 public quorum;

    mapping(bytes32 actionHash => ActionState) public actionsStates;
    mapping(address signer => mapping(bytes32 actionHash => bool support)) public approves;

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

    function _vote(Action memory action, bool support) internal {
        bytes32 digest = _hashAction(action);
        if (actionsStates[digest].action.to == address(0)) {
            actionsStates[digest].action = action;
            emit ActionProposed(action.to, action.data);
        } else {
            _getAndCheckStoredActionState(action);
        }

        if (approves[msg.sender][digest] == support) {
            return;
        }

        approves[msg.sender][digest] = support;
        emit ActionVoted(msg.sender, support, action.to, action.data);
    }

    function _markExecuted(Action memory action) internal {
        (ActionState memory actionState, bytes32 actionHash) = _getAndCheckStoredActionState(action);

        if (actionState.isExecuted == true) {
            revert ActionAlreadyExecuted();
        }
        if (_getSupport(actionHash) < quorum) {
            revert QuorumIsNotReached();
        }

        actionsStates[actionHash].isExecuted = true;

        emit ActionExecuted(action.to, action.data);
    }

    function _getActionState(Action memory action)
        internal
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        (ActionState memory actionState, bytes32 actionHash) = _getAndCheckStoredActionState(action);

        support = _getSupport(actionHash);
        execuitionQuorum = quorum;
        isExecuted = actionState.isExecuted;
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

    function _getSupport(bytes32 actionHash) internal view returns (uint256 support) {
        for (uint256 i = 0; i < members.length(); ++i) {
            if (approves[members.at(i)][actionHash]) {
                support++;
            }
        }
    }

    function _getAndCheckStoredActionState(Action memory action)
        internal
        view
        returns (ActionState memory storedActionState, bytes32 actionHash)
    {
        actionHash = _hashAction(action);

        storedActionState = actionsStates[actionHash];

        if (storedActionState.isExecuted == true) {
            revert ActionAlreadyExecuted();
        }
    }

    function _hashAction(Action memory action) internal pure returns (bytes32) {
        return keccak256(abi.encode(action.to, action.data, action.salt));
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
