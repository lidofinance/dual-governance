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

    uint256 private efMembersCount = 5;
    address[] private _efTiebrakerMembers;

    function setUp() external {
        Utils.selectFork();

        _emergencyExecutor = new Executor__mock();

        _coreTiebreaker = new Tiebreaker(address(this), new address[](0), address(_emergencyExecutor));

        for (uint256 i = 0; i < 5; i++) {
            _efTiebrakerMembers.push(makeAddr(string(abi.encode(i + 65))));
        }

        _efTiebraker = new Tiebreaker(address(this), _efTiebrakerMembers, address(_coreTiebreaker));

        _norTiebreaker = new TiebreakerNOR(NODE_OPERATORS_REGISTRY, address(_coreTiebreaker));

        _coreTiebreaker.addMember(address(_efTiebraker));
        _coreTiebreaker.addMember(address(_norTiebreaker));
    }

    function test_proposal_execution() external {
        uint256 proposalIdToExecute = 1;

        assert(_emergencyExecutor.proposals(proposalIdToExecute) == false);

        for (uint256 i = 0; i < _efTiebrakerMembers.length / 2; i++) {
            vm.prank(_efTiebrakerMembers[i]);
            _efTiebraker.emergencyExecute(proposalIdToExecute);

            assert(_efTiebraker.hasQuorum(proposalIdToExecute) == false);
        }

        vm.prank(_efTiebrakerMembers[_efTiebrakerMembers.length - 1]);
        _efTiebraker.emergencyExecute(proposalIdToExecute);

        assert(_efTiebraker.hasQuorum(proposalIdToExecute) == true);

        assert(_coreTiebreaker.hasQuorum(proposalIdToExecute) == false);

        _efTiebraker.forwardExecution(proposalIdToExecute);

        assert(_coreTiebreaker.hasQuorum(proposalIdToExecute) == false);

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
                _norTiebreaker.emergencyExecute(proposalIdToExecute, i);

                participatedNOCount++;
            }
            if (participatedNOCount >= requiredOperatorsCount) break;
        }

        assert(_norTiebreaker.hasQuorum(proposalIdToExecute) == true);

        _norTiebreaker.forwardExecution(proposalIdToExecute);

        assert(_coreTiebreaker.hasQuorum(proposalIdToExecute) == true);

        assert(_emergencyExecutor.proposals(proposalIdToExecute) == true);
    }
}

contract Executor__mock {
    error NotEmergencyCommittee(address sender);
    error ProposalAlreadyExecuted();

    mapping(uint256 => bool) public proposals;
    address private committee;

    function emergencyExecute(uint256 _proposalId) public {
        if (proposals[_proposalId] == true) {
            revert ProposalAlreadyExecuted();
        }

        if (msg.sender != committee) {
            revert NotEmergencyCommittee(msg.sender);
        }

        proposals[_proposalId] = true;
    }
}
