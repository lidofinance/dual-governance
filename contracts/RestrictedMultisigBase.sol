// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

abstract contract RestrictedMultisigBase {
    error IsNotMember();
    error SenderIsNotMember();
    error SenderIsNotOwner();
    error DataIsNotEqual();

    struct Action {
        uint256 actionType;
        bytes data;
        bool isExecuted;
        address[] signers;
    }

    address public owner;

    address[] public membersList;
    mapping(address => bool) public members;
    uint256 public quorum;

    mapping(bytes32 actionHash => Action) actions;
    mapping(address signer => mapping(bytes32 actionHash => bool support)) public approves;

    constructor(address _owner, address[] memory _members, uint256 _quorum) {
        quorum = _quorum;
        owner = _owner;

        for (uint256 i = 0; i < _members.length; ++i) {
            _addMember(_members[i]);
        }
    }

    function _vote(Action memory _action, bool _supports) internal {
        bytes32 actionHash = _hashAction(_action);
        if (actions[actionHash].data.length == 0) {
            actions[actionHash].actionType = _action.actionType;
            actions[actionHash].data = _action.data;
        } else {
            _checkStoredAction(_action);
        }

        if (approves[msg.sender][actionHash] == _supports) {
            return;
        }

        approves[msg.sender][actionHash] = _supports;
        if (_supports == true) {
            actions[actionHash].signers.push(msg.sender);
        } else {
            uint256 signersLength = actions[actionHash].signers.length;
            for (uint256 i = 0; i < signersLength; ++i) {
                if (actions[actionHash].signers[i] == msg.sender) {
                    actions[actionHash].signers[i] = actions[actionHash].signers[signersLength - 1];
                    actions[actionHash].signers.pop();
                    break;
                }
            }
        }
    }

    function _execute(Action memory _action) internal {
        _checkStoredAction(_action);

        bytes32 actionHash = _hashAction(_action);

        require(actions[actionHash].isExecuted == false);
        require(_getSuport(actionHash) >= quorum);

        _issueCalls(_action);

        actions[actionHash].isExecuted = true;
    }

    function _getState(Action memory _action)
        public
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        _checkStoredAction(_action);

        bytes32 actionHash = _hashAction(_action);
        support = _getSuport(actionHash);
        execuitionQuorum = quorum;
        isExecuted = actions[actionHash].isExecuted;
    }

    function addMember(address _newMember, uint256 _quorum) public onlyOwner {
        _addMember(_newMember);
        quorum = _quorum;
    }

    function removeMember(address _member, uint256 _quorum) public onlyOwner {
        if (members[_member] == false) {
            revert IsNotMember();
        }
        members[_member] = false;
        for (uint256 i = 0; i < membersList.length; ++i) {
            if (membersList[i] == _member) {
                membersList[i] = membersList[membersList.length - 1];
                membersList.pop();
                break;
            }
        }
        quorum = _quorum;
    }

    function _addMember(address _newMember) internal {
        membersList.push(_newMember);
        members[_newMember] = true;
    }

    function _issueCalls(Action memory _action) internal virtual;

    function _getSuport(bytes32 _actionHash) internal returns (uint256 support) {
        for (uint256 i = 0; i < actions[_actionHash].signers.length; ++i) {
            if (members[actions[_actionHash].signers[i]] == true) {
                support++;
            }
        }
    }

    function _checkStoredAction(Action memory _action) internal {
        bytes32 actionHash = _hashAction(_action);

        require(_action.actionType > 0);
        require(actions[actionHash].actionType == _action.actionType);
        require(actions[actionHash].isExecuted == false);

        require(actions[actionHash].data.length == _action.data.length);
        for (uint256 i = 0; i < _action.data.length; ++i) {
            if (actions[actionHash].data[i] != _action.data[i]) {
                revert DataIsNotEqual();
            }
        }
    }

    function _hashAction(Action memory _action) internal pure returns (bytes32) {
        return keccak256(abi.encode(_action.actionType, _action.data));
    }

    modifier onlyMember() {
        if (members[msg.sender] == false) {
            revert SenderIsNotMember();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert SenderIsNotOwner();
        }
        _;
    }
}
