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
        _deployTarget();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ true);
        _depositStETH(_VETOER, 1 ether);
    }

    function test_emergency_committees_happy_path() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        address[] memory members;

        ExternalCall[] memory proposalCalls = _getTargetRegularStaffCalls();
        uint256 proposalIdToExecute = _submitProposal(_dualGovernance, "Proposal for execution", proposalCalls);

        _wait(_config.AFTER_SUBMIT_DELAY().plusSeconds(1));
        _assertCanSchedule(_dualGovernance, proposalIdToExecute, true);
        _scheduleProposal(_dualGovernance, proposalIdToExecute);

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
        assert(isExecuted == true);

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
        assert(isExecuted == true);
    }
}
