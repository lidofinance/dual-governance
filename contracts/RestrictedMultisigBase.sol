// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

abstract contract RestrictedMultisigBase {
    error IsNotMember();
    error SenderIsNotMember();
    error SenderIsNotOwner();
    error DataIsNotEqual();

    struct Action {
        address to;
        bytes data;
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
        quorum = executionQuorum;
        OWNER = owner;

        for (uint256 i = 0; i < newMembers.length; ++i) {
            _addMember(newMembers[i]);
        }
    }

    function _vote(Action memory action, bool support) internal {
        bytes32 actionHash = _hashAction(action);
        if (actionsStates[actionHash].action.to == address(0)) {
            actionsStates[actionHash].action = action;
        } else {
            _getAndCheckStoredActionState(action);
        }

        if (approves[msg.sender][actionHash] == support) {
            return;
        }

        approves[msg.sender][actionHash] = support;
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

        require(actionState.isExecuted == false);
        require(_getState(actionHash) >= quorum);

        Address.functionCall(actionState.action.to, actionState.action.data);

        actionsStates[actionHash].isExecuted = true;
    }

    function getActionState(Action memory action)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        (ActionState memory actionState, bytes32 actionHash) = _getAndCheckStoredActionState(action);

        support = _getState(actionHash);
        execuitionQuorum = quorum;
        isExecuted = actionState.isExecuted;
    }

    function addMember(address newMember, uint256 newQuorum) public onlyOwner {
        _addMember(newMember);
        quorum = newQuorum;
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

        require(newQuorum > 0);
        require(newQuorum <= membersList.length);
        quorum = newQuorum;
    }

    function _addMember(address newMember) internal {
        membersList.push(newMember);
        members[newMember] = true;
    }

    function _getState(bytes32 actionHash) internal view returns (uint256 support) {
        for (uint256 i = 0; i < actionsStates[actionHash].signers.length; ++i) {
            if (members[actionsStates[actionHash].signers[i]] == true) {
                support++;
            }
        }
    }

    function _getAndCheckStoredActionState(Action memory action)
        internal
        view
        returns (ActionState memory storedAction, bytes32 actionHash)
    {
        actionHash = _hashAction(action);

        storedAction = actionsStates[actionHash];
        require(storedAction.action.to == action.to);
        require(storedAction.action.data.length == action.data.length);
        require(storedAction.isExecuted == false);
    }

    function _hashAction(Action memory action) internal pure returns (bytes32) {
        return keccak256(abi.encode(action.to, action.data));
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
