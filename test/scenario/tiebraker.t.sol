// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {DualGovernanceDeployScript, DualGovernance, EmergencyProtectedTimelock} from "script/Deploy.s.sol";
import {TiebreakerCore} from "contracts/TiebreakerCore.sol";
import {TiebreakerSubDAO} from "contracts/TiebreakerSubDAO.sol";

import {Utils} from "../utils/utils.sol";
import {INodeOperatorsRegistry} from "../utils/interfaces.sol";
import {NODE_OPERATORS_REGISTRY} from "../utils/mainnet-addresses.sol";

contract TiebreakerScenarioTest is Test {
    Executor__mock private _emergencyExecutor;

    TiebreakerCore private _coreTiebreaker;
    TiebreakerSubDAO private _efTiebreaker;
    TiebreakerSubDAO private _nosTiebreaker;

    uint256 private _efMembersCount = 5;
    uint256 private _efQuorum = 3;

    uint256 private _nosMembersCount = 10;
    uint256 private _nosQuorum = 7;

    address[] private _efTiebreakerMembers;
    address[] private _nosTiebreakerMembers;
    address[] private _coreTiebreakerMembers;

    function setUp() external {
        Utils.selectFork();

        _emergencyExecutor = new Executor__mock();
        _coreTiebreaker = new TiebreakerCore(address(this), new address[](0), 0, address(_emergencyExecutor));

        _emergencyExecutor.setCommittee(address(_coreTiebreaker));

        // EF sub DAO
        _efTiebreaker = new TiebreakerSubDAO(address(this), new address[](0), 0, address(_coreTiebreaker));
        for (uint256 i = 0; i < _efMembersCount; i++) {
            _efTiebreakerMembers.push(makeAddr(string(abi.encode(i + 65))));
            _efTiebreaker.addMember(_efTiebreakerMembers[i], _efQuorum);
        }
        _coreTiebreakerMembers.push(address(_efTiebreaker));
        _coreTiebreaker.addMember(address(_efTiebreaker), _efQuorum);

        // NOs sub DAO
        _nosTiebreaker = new TiebreakerSubDAO(address(this), new address[](0), 0, address(_coreTiebreaker));
        for (uint256 i = 0; i < _nosMembersCount; i++) {
            _nosTiebreakerMembers.push(makeAddr(string(abi.encode(i + 65))));
            _nosTiebreaker.addMember(_nosTiebreakerMembers[i], _nosQuorum);
        }
        _coreTiebreakerMembers.push(address(_nosTiebreaker));
        _coreTiebreaker.addMember(address(_nosTiebreaker), 2);
    }

    function test_proposal_execution() external {
        uint256 proposalIdToExecute = 1;
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        assert(_emergencyExecutor.proposals(proposalIdToExecute) == false);

        // EF sub DAO
        for (uint256 i = 0; i < _efQuorum - 1; i++) {
            vm.prank(_efTiebreakerMembers[i]);
            _efTiebreaker.voteApproveProposal(proposalIdToExecute, true);
            (support, quorum, isExecuted) = _efTiebreaker.getApproveProposalState(proposalIdToExecute);
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(_efTiebreakerMembers[_efTiebreakerMembers.length - 1]);
        _efTiebreaker.voteApproveProposal(proposalIdToExecute, true);
        (support, quorum, isExecuted) = _efTiebreaker.getApproveProposalState(proposalIdToExecute);
        assert(support == quorum);
        assert(isExecuted == false);

        _efTiebreaker.approveProposal(proposalIdToExecute);
        (support, quorum, isExecuted) = _coreTiebreaker.getApproveProposalState(proposalIdToExecute);
        assert(support < quorum);

        // NOs sub DAO

        for (uint256 i = 0; i < _nosQuorum - 1; i++) {
            vm.prank(_nosTiebreakerMembers[i]);
            _nosTiebreaker.voteApproveProposal(proposalIdToExecute, true);
            (support, quorum, isExecuted) = _nosTiebreaker.getApproveProposalState(proposalIdToExecute);
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(_nosTiebreakerMembers[_nosTiebreakerMembers.length - 1]);
        _nosTiebreaker.voteApproveProposal(proposalIdToExecute, true);

        (support, quorum, isExecuted) = _nosTiebreaker.getApproveProposalState(proposalIdToExecute);
        assert(support == quorum);
        assert(isExecuted == false);

        _nosTiebreaker.approveProposal(proposalIdToExecute);
        (support, quorum, isExecuted) = _coreTiebreaker.getApproveProposalState(proposalIdToExecute);
        assert(support == quorum);

        _coreTiebreaker.approveProposal(proposalIdToExecute);

        assert(_emergencyExecutor.proposals(proposalIdToExecute) == true);
    }
}

contract Executor__mock {
    error NotEmergencyCommittee(address sender);
    error ProposalAlreadyExecuted();

    mapping(uint256 => bool) public proposals;
    address private committee;

    function setCommittee(address _committee) public {
        committee = _committee;
    }

    function tiebreakerApproveProposal(uint256 _proposalId) public {
        if (proposals[_proposalId] == true) {
            revert ProposalAlreadyExecuted();
        }

        if (msg.sender != committee) {
            revert NotEmergencyCommittee(msg.sender);
        }

        proposals[_proposalId] = true;
    }
}
