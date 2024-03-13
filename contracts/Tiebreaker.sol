// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IEmergencyExecutor {
    function emergencyExecute(uint256 proposalId) external;
}

/**
 * A contract provides ability to execute locked proposals.
 */
contract Tiebreaker is IEmergencyExecutor {
    error SenderIsNotMember();
    error SenderIsNotOwner();
    error IsNotMember();
    error ProposalIsNotSupported();
    error ProposalAlreadyExecuted(uint256 proposalId);
    error ZeroQuorum();

    address executor;

    mapping(address => bool) members;
    address public owner;
    address[] membersList;

    struct ProposalState {
        address[] supportersList;
        mapping(address => bool) supporters;
        bool isExecuted;
    }

    mapping(uint256 => ProposalState) proposals;

    constructor(address _owner, address[] memory _members, address _executor) {
        owner = _owner;
        membersList = _members;
        executor = _executor;
    }

    function emergencyExecute(uint256 _proposalId) public onlyMember {
        proposals[_proposalId].supportersList.push(msg.sender);
        proposals[_proposalId].supporters[msg.sender] = true;
    }

    function forwardExecution(uint256 _proposalId) public {
        if (!hasQuorum(_proposalId)) {
            revert ProposalIsNotSupported();
        }

        if (proposals[_proposalId].isExecuted == true) {
            revert ProposalAlreadyExecuted(_proposalId);
        }

        IEmergencyExecutor(executor).emergencyExecute(_proposalId);

        proposals[_proposalId].isExecuted = true;
    }

    function addMember(address _newMember) public onlyOwner {
        membersList.push(_newMember);
        members[_newMember] = true;
    }

    function removeMember(address _member) public onlyOwner {
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
    }

    function hasQuorum(uint256 _proposalId) public view returns (bool) {
        uint256 supportersCount = 0;
        uint256 quorum = membersList.length / 2 + 1;
        if (quorum == 0) {
            revert ZeroQuorum();
        }

        for (uint256 i = 0; i < proposals[_proposalId].supportersList.length; ++i) {
            if (members[proposals[_proposalId].supportersList[i]] == true) {
                supportersCount++;
            }
        }
        return supportersCount >= quorum;
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
