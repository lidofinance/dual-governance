// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    percents,
    ScenarioTestBlueprint,
    ExecutorCall,
    ExecutorCallHelpers,
    DualGovernanceState,
    Durations
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
        _step("1. DAO SUBMITS PROPOSAL WITH REGULAR STAFF");
        {
            proposalId = _submitProposal(
                _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _logVetoSignallingState();
        }

        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        _step("2. MALICIOUS ACTOR STARTS ACQUIRE VETO SIGNALLING DURATION");
        {
            _lockStETH(maliciousActor, percents("12.0"));
            _assertVetoSignalingState();
            _logVetoSignallingState();

            // almost all veto signalling period has passed
            _wait(Durations.from(20 days));
            _activateNextState();
            _assertVetoSignalingState();
            _logVetoSignallingState();
        }

        uint256 maliciousProposalId;
        _step("3. MALICIOUS ACTOR SUBMITS MALICIOUS PROPOSAL");
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

        _step("4. MALICIOUS ACTOR UNLOCK FUNDS FROM ESCROW");
        {
            _wait(Durations.from(12 seconds));
            _unlockStETH(maliciousActor);
            _assertVetoSignalingDeactivationState();
            _logVetoSignallingDeactivationState();
        }

        address stEthHolders = makeAddr("STETH_WHALE");
        _step("5. STETH HOLDERS ACQUIRING QUORUM TO VETO MALICIOUS PROPOSAL");
        {
            _wait(_config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().dividedBy(2));
            _lockStETH(stEthHolders, percents(_config.FIRST_SEAL_RAGE_QUIT_SUPPORT() + 1));
            _assertVetoSignalingDeactivationState();
            _logVetoSignallingDeactivationState();

            _wait(_config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().dividedBy(2).plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();
        }

        _step("6. MALICIOUS PROPOSAL CAN'T BE EXECUTED IN THE VETO COOLDOWN STATE");
        {
            // the regular proposal can be executed
            _scheduleProposal(_dualGovernance, proposalId);
            _waitAfterScheduleDelayPassed();

            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);

            vm.expectRevert(DualGovernanceState.ProposalsAdoptionSuspended.selector);
            this.scheduleProposalExternal(maliciousProposalId);

            _assertProposalSubmitted(maliciousProposalId);
        }

        _step("7. NEW VETO SIGNALLING ROUND FOR MALICIOUS PROPOSAL IS STARTED");
        {
            _wait(_config.VETO_COOLDOWN_DURATION().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();
            _logVetoSignallingState();

            // the second seal rage quit support is reached
            _lockStETH(stEthHolders, percents(_config.SECOND_SEAL_RAGE_QUIT_SUPPORT()));
            _assertVetoSignalingState();
            _logVetoSignallingState();

            _wait(_config.DYNAMIC_TIMELOCK_MAX_DURATION().plusSeconds(1));
            _logVetoSignallingState();
            _activateNextState();
            _assertRageQuitState();

            vm.expectRevert(DualGovernanceState.ProposalsAdoptionSuspended.selector);
            this.scheduleProposalExternal(maliciousProposalId);
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
            _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2));

            _lockStETH(maliciousActor, percents("12.0"));
            _assertVetoSignalingState();

            _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2).plusSeconds(1));

            _assertProposalSubmitted(proposalId);

            (, uint256 currentVetoSignallingDuration,,) = _getVetoSignallingState();
            _wait(Durations.from(currentVetoSignallingDuration + 1));

            _activateNextState();
            _assertVetoSignalingDeactivationState();
        }

        // ---
        // ACT 3. THE VETO SIGNALLING DEACTIVATION DURATION EQUALS TO "VETO_SIGNALLING_DEACTIVATION_MAX_DURATION" DAYS
        // ---
        {
            _wait(_config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));

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

    function testFork_VetoSignallingToNormalState() external {
        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        _step("2. MALICIOUS ACTOR LOCKS FIRST SEAL THRESHOLD TO ACTIVATE VETO SIGNALLING BEFORE PROPOSAL SUBMISSION");
        {
            _lockStETH(maliciousActor, percents("3.50"));
            _assertVetoSignalingState();
            _logVetoSignallingState();
        }

        uint256 proposalId;
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();
        _step("2. DAO SUBMITS PROPOSAL WITH REGULAR STAFF");
        {
            proposalId = _submitProposal(
                _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _logVetoSignallingState();
        }

        _step("3. THE VETO SIGNALLING & DEACTIVATION PASSED BUT PROPOSAL STILL NOT EXECUTABLE");
        {
            _wait(_config.DYNAMIC_TIMELOCK_MIN_DURATION().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingDeactivationState();
            _logVetoSignallingDeactivationState();

            _wait(_config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();

            vm.expectRevert(DualGovernanceState.ProposalsAdoptionSuspended.selector);
            this.scheduleProposalExternal(proposalId);
        }

        _step("4. AFTER THE VETO COOLDOWN GOVERNANCE TRANSITIONS INTO NORMAL STATE");
        {
            _unlockStETH(maliciousActor);
            _wait(_config.VETO_COOLDOWN_DURATION().plusSeconds(1));
            _activateNextState();
            _assertNormalState();
        }

        _step("5. PROPOSAL EXECUTABLE IN THE NORMAL STATE");
        {
            _scheduleProposal(_dualGovernance, proposalId);
            _assertProposalScheduled(proposalId);
            _waitAfterScheduleDelayPassed();
            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);
        }
    }

    function testFork_ProposalSubmissionFrontRunning() external {
        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        _step("2. MALICIOUS ACTOR LOCKS FIRST SEAL THRESHOLD TO ACTIVATE VETO SIGNALLING BEFORE PROPOSAL SUBMISSION");
        {
            _lockStETH(maliciousActor, percents("3.50"));
            _assertVetoSignalingState();
            _logVetoSignallingState();
        }

        uint256 proposalId;
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();
        _step("2. DAO SUBMITS PROPOSAL WITH REGULAR STAFF");
        {
            proposalId = _submitProposal(
                _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _logVetoSignallingState();
        }

        _step("3. THE VETO SIGNALLING & DEACTIVATION PASSED BUT PROPOSAL STILL NOT EXECUTABLE");
        {
            _wait(_config.DYNAMIC_TIMELOCK_MIN_DURATION().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingDeactivationState();
            _logVetoSignallingDeactivationState();

            _wait(_config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();

            vm.expectRevert(DualGovernanceState.ProposalsAdoptionSuspended.selector);
            this.scheduleProposalExternal(proposalId);
        }

        _step("4. AFTER THE VETO COOLDOWN NEW VETO SIGNALLING ROUND STARTED");
        {
            _wait(_config.VETO_COOLDOWN_DURATION().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();
            _logVetoSignallingState();

            vm.expectRevert(DualGovernanceState.ProposalsAdoptionSuspended.selector);
            this.scheduleProposalExternal(proposalId);
        }

        _step("5. PROPOSAL EXECUTABLE IN THE NEXT VETO COOLDOWN");
        {
            _wait(_config.DYNAMIC_TIMELOCK_MIN_DURATION().multipliedBy(2));
            _activateNextState();
            _assertVetoSignalingDeactivationState();
            _logVetoSignallingDeactivationState();

            _wait(_config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();

            _scheduleProposal(_dualGovernance, proposalId);
            _assertProposalScheduled(proposalId);
            _waitAfterScheduleDelayPassed();
            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);
        }
    }

    function scheduleProposalExternal(uint256 proposalId) external {
        _scheduleProposal(_dualGovernance, proposalId);
    }
}
