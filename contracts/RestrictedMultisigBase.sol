// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

abstract contract RestrictedMultisigBase {
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

    struct Action {
        address to;
        bytes data;
        bytes extraData;
    }

    struct ActionState {
        Action action;
        bool isExecuted;
        address[] signers;
    }

    address public immutable OWNER;

    address[] public membersList;
    mapping(address => bool) public members;
    uint256 public quorum;

    mapping(bytes32 actionHash => ActionState) actionsStates;
    mapping(address signer => mapping(bytes32 actionHash => bool support)) public approves;

    constructor(address owner, address[] memory newMembers, uint256 executionQuorum) {
        if (executionQuorum == 0) {
            revert InvalidQuorum();
        }
        quorum = executionQuorum;
        emit QuorumSet(executionQuorum);

        OWNER = owner;

        for (uint256 i = 0; i < newMembers.length; ++i) {
            _addMember(newMembers[i]);
        }
    }

    function _vote(Action memory action, bool support) internal {
        bytes32 actionHash = _hashAction(action);
        if (actionsStates[actionHash].action.to == address(0)) {
            actionsStates[actionHash].action = action;
            emit ActionProposed(action.to, action.data);
        } else {
            _getAndCheckStoredActionState(action);
        }

        if (approves[msg.sender][actionHash] == support) {
            return;
        }

        approves[msg.sender][actionHash] = support;
        emit ActionVoted(msg.sender, support, action.to, action.data);
        if (support == true) {
            actionsStates[actionHash].signers.push(msg.sender);
        } else {
            uint256 signersLength = actionsStates[actionHash].signers.length;
            for (uint256 i = 0; i < signersLength; ++i) {
                if (actionsStates[actionHash].signers[i] == msg.sender) {
                    actionsStates[actionHash].signers[i] = actionsStates[actionHash].signers[signersLength - 1];
                    actionsStates[actionHash].signers.pop();
                    break;
                }
            }
        }
    }

    function _execute(Action memory action) internal {
        (ActionState memory actionState, bytes32 actionHash) = _getAndCheckStoredActionState(action);

        if (actionState.isExecuted == true) {
            revert ActionAlreadyExecuted();
        }
        if (_getSupport(actionHash) < quorum) {
            revert QuorumIsNotReached();
        }

        Address.functionCall(actionState.action.to, actionState.action.data);

        actionsStates[actionHash].isExecuted = true;

        emit ActionExecuted(action.to, action.data);
    }

    function getActionState(Action memory action)
        public
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

        if (newQuorum == 0 || newQuorum > membersList.length) {
            revert InvalidQuorum();
        }
        quorum = newQuorum;
        emit QuorumSet(newQuorum);
    }

    function removeMember(address memberToRemove, uint256 newQuorum) public onlyOwner {
        if (members[memberToRemove] == false) {
            revert IsNotMember();
        }
        members[memberToRemove] = false;
        for (uint256 i = 0; i < membersList.length; ++i) {
            if (membersList[i] == memberToRemove) {
                membersList[i] = membersList[membersList.length - 1];
                membersList.pop();
                break;
            }
        }
        emit MemberRemoved(memberToRemove);

        if (newQuorum == 0 || newQuorum > membersList.length) {
            revert InvalidQuorum();
        }
        quorum = newQuorum;
        emit QuorumSet(newQuorum);
    }

    function _addMember(address newMember) internal {
        membersList.push(newMember);
        members[newMember] = true;
        emit MemberAdded(newMember);
    }

    function _getSupport(bytes32 actionHash) internal view returns (uint256 support) {
        for (uint256 i = 0; i < actionsStates[actionHash].signers.length; ++i) {
            if (members[actionsStates[actionHash].signers[i]] == true) {
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
        if (storedActionState.action.to != action.to || storedActionState.action.data.length != action.data.length) {
            revert ActionMismatch();
        }
        if (storedActionState.isExecuted == true) {
            revert ActionAlreadyExecuted();
        }
    }

    function _hashAction(Action memory action) internal pure returns (bytes32) {
        return keccak256(abi.encode(action.to, action.data, action.extraData));
    }

    modifier onlyMember() {
        if (members[msg.sender] == false) {
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
