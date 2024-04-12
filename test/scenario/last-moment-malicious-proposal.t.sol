// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    percents, ScenarioTestBlueprint, ExecutorCall, ExecutorCallHelpers
} from "../utils/scenario-test-blueprint.sol";

interface IDangerousContract {
    function doRegularStaff(uint256 magic) external;
    function doRugPool() external;
    function doControversialStaff() external;
}

contract LastMomentMaliciousProposalSuccessor is ScenarioTestBlueprint {
    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);
    }

    function testFork_LastMomentMaliciousProposal() external {
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();

        uint256 proposalId;
        // ---
        // ACT 1. DAO SUBMITS PROPOSAL WITH REGULAR STAFF
        // ---
        {
            proposalId = _submitProposal(
                _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _logVetoSignallingState();
        }

        // ---
        // ACT 2. MALICIOUS ACTOR STARTS ACQUIRE VETO SIGNALLING DURATION
        // ---
        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        {
            _lockStETH(maliciousActor, percents("12.0"));
            _assertVetoSignalingState();
            _logVetoSignallingState();

            // almost all veto signalling period has passed
            vm.warp(block.timestamp + 20 days);
            _activateNextState();
            _assertVetoSignalingState();
            _logVetoSignallingState();
        }

        // ---
        // ACT 3. MALICIOUS ACTOR SUBMITS MALICIOUS PROPOSAL
        // ---
        uint256 maliciousProposalId;
        {
            _assertVetoSignalingState();
            maliciousProposalId = _submitProposal(
                _dualGovernance,
                "Malicious Proposal",
                ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()))
            );

            // the both calls aren't executable until the delay has passed
            _assertProposalSubmitted(proposalId);
            _assertProposalSubmitted(maliciousProposalId);
            _logVetoSignallingState();
        }

        // ---
        // ACT 4. MALICIOUS ACTOR UNLOCK FUNDS FROM ESCROW
        // ---
        {
            _unlockStETH(maliciousActor);
            _logVetoSignallingDeactivationState();
            _assertVetoSignalingDeactivationState();
        }

        // ---
        // ACT 5. STETH HOLDERS MAY ACQUIRE QUORUM BECAUSE THE VETO SIGNALLING PERIOD RESTARTED
        // ---
        address stEthWhale = makeAddr("STETH_WHALE");
        {
            _wait(_config.SIGNALLING_DEACTIVATION_DURATION() / 2);
            _lockStETH(stEthWhale, percents("10.0"));
            _logVetoSignallingDeactivationState();
            _assertVetoSignalingState();
            _logVetoSignallingState();
        }

        // ---
        // ACT 6. STETH HOLDER MAY EXIT TO RAGE QUIT WHEN THE SECOND SEAL THRESHOLD REACHED
        // ---
        {
            _wait(_config.SIGNALLING_DEACTIVATION_DURATION() / 2 + 1);

            _activateNextState();
            _assertVetoSignalingState();

            // stEth holders reach the rage quit threshold
            _lockStETH(stEthWhale, percents("10.0"));

            _wait(_config.SIGNALLING_DEACTIVATION_DURATION());
            _activateNextState();

            // the dual governance immediately transfers to the Rage Quit state
            _assertRageQuitState();

            // the malicious call still not executable
            _assertProposalSubmitted(maliciousProposalId);
        }
    }

    function testFork_VetoSignallingDeactivationDefaultDuration() external {
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();

        uint256 proposalId;
        // ---
        // ACT 1. DAO SUBMITS CONTROVERSIAL PROPOSAL
        // ---
        {
            proposalId = _submitProposal(
                _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _logVetoSignallingState();
        }

        // ---
        // ACT 2. MALICIOUS ACTOR ACCUMULATES FIRST THRESHOLD OF STETH IN THE ESCROW
        // ---
        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        {
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2);

            _lockStETH(maliciousActor, percents("12.0"));
            _assertVetoSignalingState();

            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2 + 1);

            _assertProposalSubmitted(proposalId);

            (, uint256 currentVetoSignallingDuration,,) = _getVetoSignallingState();
            vm.warp(block.timestamp + currentVetoSignallingDuration + 1);

            _activateNextState();
            _assertVetoSignalingDeactivationState();
        }

        // ---
        // ACT 3. THE VETO SIGNALLING DEACTIVATION DURATION EQUALS TO "SIGNALLING_DEACTIVATION_DURATION" DAYS
        // ---
        {
            vm.warp(block.timestamp + _config.SIGNALLING_DEACTIVATION_DURATION() + 1);

            _activateNextState();
            _assertVetoCooldownState();

            _assertCanSchedule(_dualGovernance, proposalId, true);
            _scheduleProposal(_dualGovernance, proposalId);
            _assertProposalScheduled(proposalId);

            _waitAfterScheduleDelayPassed();

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
        }
    }
}
