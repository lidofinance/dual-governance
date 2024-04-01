// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {DualGovernanceDeployScript, DualGovernance, EmergencyProtectedTimelock} from "script/Deploy.s.sol";
import {Tiebreaker} from "contracts/Tiebreaker.sol";
import {TiebreakerNOR} from "contracts/TiebreakerNOR.sol";

import {Utils} from "../utils/utils.sol";
import {INodeOperatorsRegistry} from "../utils/interfaces.sol";
import {NODE_OPERATORS_REGISTRY} from "../utils/mainnet-addresses.sol";

contract TiebreakerScenarioTest is Test {
    Executor__mock private _emergencyExecutor;

    Tiebreaker private _coreTiebreaker;
    Tiebreaker private _efTiebraker;
    TiebreakerNOR private _norTiebreaker;

    uint256 private _efMembersCount = 5;
    uint256 private _efQuorum = 3;

    address[] private _efTiebrakerMembers;
    address[] private _coreTiebrakerMembers;

    function setUp() external {
        Utils.selectFork();

        _coreTiebreaker = new Tiebreaker();

        _emergencyExecutor = new Executor__mock(address(_coreTiebreaker));

        for (uint256 i = 0; i < _efMembersCount; i++) {
            _efTiebrakerMembers.push(makeAddr(string(abi.encode(i + 65))));
        }

        _efTiebraker = new Tiebreaker();
        _efTiebraker.initialize(address(this), _efTiebrakerMembers, _efQuorum);
        _coreTiebrakerMembers.push(address(_efTiebraker));

        _norTiebreaker = new TiebreakerNOR(NODE_OPERATORS_REGISTRY);
        _coreTiebrakerMembers.push(address(_norTiebreaker));

        _coreTiebreaker.initialize(address(this), _coreTiebrakerMembers, 2);
    }

    function test_proposal_execution() external {
        uint256 proposalIdToExecute = 1;

        assert(_emergencyExecutor.proposals(proposalIdToExecute) == false);

        bytes32 execProposalHash = _prepareExecuteProposalHash(address(_emergencyExecutor), proposalIdToExecute, 1);
        bytes32 execApproveHash = _prepareApproveHashHash(address(_coreTiebreaker), execProposalHash, 1);

        for (uint256 i = 0; i < _efQuorum - 1; i++) {
            vm.prank(_efTiebrakerMembers[i]);
            _efTiebraker.approveHash(execApproveHash);
            assert(_efTiebraker.hasQuorum(execApproveHash) == false);
        }

        vm.prank(_efTiebrakerMembers[_efTiebrakerMembers.length - 1]);
        _efTiebraker.approveHash(execApproveHash);

        assert(_efTiebraker.hasQuorum(execApproveHash) == true);

        _efTiebraker.execTransaction(
            address(_coreTiebreaker), abi.encodeWithSignature("approveHash(bytes32)", execProposalHash), 0
        );

        assert(_coreTiebreaker.hasQuorum(execProposalHash) == false);

        uint256 participatedNOCount = 0;
        uint256 requiredOperatorsCount =
            INodeOperatorsRegistry(NODE_OPERATORS_REGISTRY).getActiveNodeOperatorsCount() / 2 + 1;

        for (uint256 i = 0; i < INodeOperatorsRegistry(NODE_OPERATORS_REGISTRY).getNodeOperatorsCount(); i++) {
            (
                bool active,
                , //string memory name,
                address rewardAddress,
                , //uint64 stakingLimit,
                , //uint64 stoppedValidators,
                , //uint64 totalSigningKeys,
                    //uint64 usedSigningKeys
            ) = INodeOperatorsRegistry(NODE_OPERATORS_REGISTRY).getNodeOperator(i, false);
            if (active) {
                vm.prank(rewardAddress);
                _norTiebreaker.approveHash(execApproveHash, i);

                participatedNOCount++;
            }
            if (participatedNOCount >= requiredOperatorsCount) break;
        }

        assert(_norTiebreaker.hasQuorum(execApproveHash) == true);

        _norTiebreaker.execTransaction(
            address(_coreTiebreaker), abi.encodeWithSignature("approveHash(bytes32)", execProposalHash), 0
        );
        assert(_coreTiebreaker.hasQuorum(execProposalHash) == true);

        _coreTiebreaker.execTransaction(
            address(_emergencyExecutor), abi.encodeWithSignature("tiebreaExecute(uint256)", proposalIdToExecute), 0
        );

        assert(_emergencyExecutor.proposals(proposalIdToExecute) == true);
    }

    function _prepareApproveHashHash(address _to, bytes32 _hash, uint256 _nonce) public view returns (bytes32) {
        return _efTiebraker.getTransactionHash(_to, abi.encodeWithSignature("approveHash(bytes32)", _hash), 0, _nonce);
    }

    function _prepareExecuteProposalHash(
        address _to,
        uint256 _proposalId,
        uint256 _nonce
    ) public view returns (bytes32) {
        return _coreTiebreaker.getTransactionHash(
            _to, abi.encodeWithSignature("tiebreaExecute(uint256)", _proposalId), 0, _nonce
        );
    }
}

contract Executor__mock {
    error NotEmergencyCommittee(address sender);
    error ProposalAlreadyExecuted();

    mapping(uint256 => bool) public proposals;
    address private committee;

    constructor(address _committee) {
        committee = _committee;
    }

    function tiebreaExecute(uint256 _proposalId) public {
        if (proposals[_proposalId] == true) {
            revert ProposalAlreadyExecuted();
        }

        if (msg.sender != committee) {
            revert NotEmergencyCommittee(msg.sender);
        }

        proposals[_proposalId] = true;
    }
}
