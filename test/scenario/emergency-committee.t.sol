// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    ScenarioTestBlueprint, percents, ExternalCall, ExternalCallHelpers
} from "../utils/scenario-test-blueprint.sol";

import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {DAO_AGENT} from "../utils/mainnet-addresses.sol";

contract EmergencyCommitteeTest is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");
    uint256 public constant PAUSE_INFINITELY = type(uint256).max;

    function setUp() external {
        _selectFork();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);
        _depositStETH(_VETOER, 1 ether);
    }

    function test_proposal_approval() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        address[] memory members;

        ExternalCall[] memory proposalCalls = ExternalCallHelpers.create(address(0), new bytes(0));
        uint256 proposalIdToExecute = _submitProposal(_dualGovernance, "Proposal for execution", proposalCalls);

        // Emergency Activation
        members = _emergencyActivationCommittee.getMembers();
        for (uint256 i = 0; i < _emergencyActivationCommittee.quorum() - 1; i++) {
            vm.prank(members[i]);
            _emergencyActivationCommittee.approveActivateEmergencyMode();
            (support, quorum, isExecuted) = _emergencyActivationCommittee.getActivateEmergencyModeState();
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(members[members.length - 1]);
        _emergencyActivationCommittee.approveActivateEmergencyMode();
        (support, quorum, isExecuted) = _emergencyActivationCommittee.getActivateEmergencyModeState();
        assert(support == quorum);
        assert(isExecuted == false);

        _emergencyActivationCommittee.executeActivateEmergencyMode();
        (support, quorum, isExecuted) = _emergencyActivationCommittee.getActivateEmergencyModeState();
        assert(support < quorum);

        // Emergency Execute
        members = _emergencyExecutionCommittee.getMembers();
        for (uint256 i = 0; i < _emergencyExecutionCommittee.quorum() - 1; i++) {
            vm.prank(members[i]);
            _emergencyExecutionCommittee.voteEmergencyExecute(proposalIdToExecute, true);
            (support, quorum, isExecuted) = _emergencyExecutionCommittee.getEmergencyExecuteState(proposalIdToExecute);
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(members[members.length - 1]);
        _emergencyExecutionCommittee.voteEmergencyExecute(proposalIdToExecute, true);
        (support, quorum, isExecuted) = _emergencyExecutionCommittee.getEmergencyExecuteState(proposalIdToExecute);
        assert(support == quorum);
        assert(isExecuted == false);

        _emergencyExecutionCommittee.executeEmergencyExecute(proposalIdToExecute);
        (support, quorum, isExecuted) = _emergencyExecutionCommittee.getEmergencyExecuteState(proposalIdToExecute);
        assert(support < quorum);
    }
}
