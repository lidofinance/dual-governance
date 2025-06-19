// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";
import {IPotentiallyDangerousContract} from "../utils/interfaces/IPotentiallyDangerousContract.sol";

import {DGScenarioTestSetup} from "../utils/integration-tests.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";
import {ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";

address constant MULTICALL3_MAINNET = 0xcA11bde05977b3631167028862bE2a173976CA11;

contract DGProposalOperationsPeculiaritiesTest is DGScenarioTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});
    }

    function testFork_LastMomentMaliciousProposal_HappyPath() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. DAO submits proposal with regular staff");
        {
            proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
        }

        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        _setupStETHBalance(maliciousActor, PercentsD16.fromBasisPoints(15_00));
        _step("2. Malicious actor starts acquire veto signalling duration");
        {
            _lockStETH(maliciousActor, PercentsD16.fromBasisPoints(12_00));
            _assertVetoSignalingState();

            // almost all veto signalling period has passed
            _wait(Durations.from(20 days));
            _activateNextState();
            _assertVetoSignalingState();
        }

        uint256 maliciousProposalId;
        _step("3. Malicious actor submits malicious proposal");
        {
            _assertVetoSignalingState();

            ExternalCall[] memory maliciousCalls = new ExternalCall[](1);

            maliciousCalls[0] = ExternalCall({
                target: address(_targetMock),
                value: 0,
                payload: abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ())
            });

            maliciousProposalId = _submitProposalByAdminProposer(maliciousCalls, "Malicious Proposal");

            // the both calls aren't executable until the delay has passed
            _assertProposalSubmitted(proposalId);
            _assertProposalSubmitted(maliciousProposalId);
        }

        _step("4. Malicious actor unlock funds from escrow");
        {
            _wait(Durations.from(12 seconds));
            _unlockStETH(maliciousActor);
            _assertVetoSignallingDeactivationState();
        }

        address stEthHolders = makeAddr("STETH_WHALE");
        _setupStETHBalance(stEthHolders, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
        _step("5. StETH holders acquiring quorum to veto malicious proposal");
        {
            _wait(_getVetoSignallingDeactivationMaxDuration().dividedBy(2));
            _lockStETH(stEthHolders, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1));
            _assertVetoSignallingDeactivationState();

            _wait(_getVetoSignallingDeactivationMaxDuration().dividedBy(2).plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();
        }

        _step("6. Malicious proposal can't be executed in the veto cooldown state");
        {
            // the regular proposal can be executed
            _scheduleProposal(proposalId);
            _wait(_getAfterScheduleDelay());

            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);

            vm.expectRevert(
                abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, maliciousProposalId)
            );
            this.external__scheduleProposal(maliciousProposalId);

            _assertProposalSubmitted(maliciousProposalId);
        }

        _step("7. New veto signalling round for malicious proposal is started");
        {
            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();

            // the second seal rage quit support is reached
            _setupStETHBalance(stEthHolders, _getSecondSealRageQuitSupport());
            _lockStETH(stEthHolders, _getSecondSealRageQuitSupport());
            _assertVetoSignalingState();

            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();

            vm.expectRevert(
                abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, maliciousProposalId)
            );
            this.external__scheduleProposal(maliciousProposalId);
        }
    }

    function testFork_ProposalsSubmittedInVetoSignalling_CanBeExecutedOnlyNextVetoCooldownOrNormal() external {
        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        _step("2. Malicious actor locks first seal threshold to activate VetoSignalling before proposal submission");
        {
            _setupStETHBalance(maliciousActor, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
            _lockStETH(maliciousActor, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1));
            _assertVetoSignalingState();
        }

        uint256 proposalId;
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
        _step("2. DAO submits proposal with regular staff");
        {
            _wait(_getVetoSignallingDuration().dividedBy(2));
            proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
        }

        _step("3. The VetoSignalling & Deactivation passed but proposal still not executable");
        {
            _wait(_getVetoSignallingDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoSignallingDeactivationState();

            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();

            vm.expectRevert(abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, proposalId));
            this.external__scheduleProposal(proposalId);
        }

        _step("4. After the VetoCooldown new VetoSignalling round started");
        {
            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();

            vm.expectRevert(abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, proposalId));
            this.external__scheduleProposal(proposalId);
        }

        _step("5. Proposal executable in the next VetoCooldown");
        {
            _wait(_getVetoSignallingMinDuration().multipliedBy(2));
            _activateNextState();
            _assertVetoSignallingDeactivationState();

            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();

            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);
            _wait(_getAfterScheduleDelay());
            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);
        }
    }

    function testFork_ProposalsSubmittedInRageQuit_CanBeExecutedOnlyNextVetoCooldownOrNormal() external {
        ExternalCall[] memory regularStuffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. The proposal is submitted");
        {
            proposalId =
                _submitProposalByAdminProposer(regularStuffCalls, "Propose to doSmth on target passing dual governance");

            _assertSubmittedProposalData(proposalId, _timelock.getAdminExecutor(), regularStuffCalls);
            _assertCanSchedule(proposalId, false);
        }

        address vetoer = makeAddr("MALICIOUS_ACTOR");
        _setupStETHBalance(vetoer, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
        _step("2. The second seal rage quit support is acquired");
        {
            _lockStETH(vetoer, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1));
            _assertVetoSignalingState();

            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();
        }

        uint256 anotherProposalId;
        _step("3. Another proposal is submitted during the rage quit state");
        {
            _activateNextState();
            _assertRageQuitState();

            ExternalCallsBuilder.Context memory builder = ExternalCallsBuilder.create({callsCount: 1});
            builder.addCall(address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ()));

            anotherProposalId = _submitProposalByAdminProposer(builder.getResult(), "Another Proposal");
        }

        _step("4. Rage quit is finalized");
        {
            // request withdrawals batches
            IRageQuitEscrow rageQuitEscrow = _getRageQuitEscrow();

            while (!rageQuitEscrow.isWithdrawalsBatchesClosed()) {
                rageQuitEscrow.requestNextWithdrawalsBatch(96);
            }

            _finalizeWithdrawalQueue();

            while (rageQuitEscrow.getUnclaimedUnstETHIdsCount() > 0) {
                rageQuitEscrow.claimNextWithdrawalsBatch(128);
            }

            rageQuitEscrow.startRageQuitExtensionPeriod();

            _wait(_getRageQuitExtensionPeriodDuration().plusSeconds(1));
            assertTrue(rageQuitEscrow.isRageQuitFinalized());
        }

        _step("5. Proposal submitted before rage quit is executable");
        {
            _activateNextState();
            _assertVetoCooldownState();

            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);
        }

        _step("6. Proposal submitted during rage quit is not executable");
        {
            _activateNextState();
            _assertVetoCooldownState();

            vm.expectRevert(
                abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, anotherProposalId)
            );
            this.external__scheduleProposal(anotherProposalId);
        }

        _step("7. Proposal submitted before rage quit is executed");
        {
            _wait(_getAfterScheduleDelay());

            _assertVetoCooldownState();
            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);
        }

        _step("8. When DG enters Normal state again the proposal submitted during rage quit becomes executable");
        {
            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();

            _assertNormalState();

            _scheduleProposal(anotherProposalId);
            _assertProposalScheduled(anotherProposalId);

            _wait(_getAfterScheduleDelay());

            _executeProposal(anotherProposalId);
            _assertProposalExecuted(anotherProposalId);
        }
    }

    function testFork_ProposalsSubmittedBeforeVetoSignalling_CanBeExecutedInVetoCooldown() external {
        ExternalCall[] memory regularStuffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. DAO submits regular proposal");
        {
            proposalId = _submitProposalByAdminProposer(
                regularStuffCalls, "DAO does regular stuff on potentially dangerous contract"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStuffCalls);
        }

        address vetoers = makeAddr("PROPOSAL_VETOERS");
        _step("2. Some stETH holders accumulate stETH in the Escrow passing first seal RageQuit threshold");
        {
            _wait(_timelock.getAfterSubmitDelay().dividedBy(2));
            _setupStETHBalance(vetoers, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_01));

            _lockStETH(vetoers, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));

            _assertVetoSignalingState();

            _wait(_getVetoSignallingMaxDuration().dividedBy(2));

            _activateNextState();
            _assertVetoSignallingDeactivationState();
        }

        _step("3. Not enough stETH for RageQuit, entering VetoCooldown state and executing proposal");
        {
            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoCooldownState();

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStuffCalls);
        }

        _step("4. After VetoCooldown system enters VetoSignalling state unless vetoers unlock their stETH from Escrow");
        {
            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();
        }
    }

    function testFork_ProposalScheduleAndExecute_HappyPath_SameTransaction() external {
        _step("0. Prepare DG setup, setting after schedule delay to 0");
        {
            assertFalse(_timelock.isEmergencyProtectionEnabled());

            ExternalCallsBuilder.Context memory afterScheduleDelayProposalBuilder =
                ExternalCallsBuilder.create({callsCount: 1});

            afterScheduleDelayProposalBuilder.addCall({
                target: address(_timelock),
                payload: abi.encodeCall(_timelock.setAfterScheduleDelay, (Durations.ZERO))
            });
            uint256 proposalId = _submitProposalByAdminProposer(
                afterScheduleDelayProposalBuilder.getResult(), "Setting afterScheduleDelay to zero"
            );

            _wait(_getAfterSubmitDelay());

            _scheduleProposal(proposalId);

            _wait(_getAfterScheduleDelay());

            _executeProposal(proposalId);

            assertEq(_timelock.getAfterScheduleDelay(), Durations.ZERO);
            assertTrue(_timelock.getAfterSubmitDelay() > Durations.ZERO);
        }

        ExternalCall[] memory regularStuffCalls = _getMockTargetRegularStaffCalls();
        uint256 regularProposalId;
        _step("1. DAO submits regular proposal");
        {
            regularProposalId = _submitProposalByAdminProposer(regularStuffCalls);
            _assertCanSchedule(regularProposalId, false);
            _assertCanExecute(regularProposalId, false);
        }

        _step("2. Schedule and execute proposal at the same tx using multicall3");
        {
            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(regularProposalId, true);

            IMulticall3.Call[] memory calls = new IMulticall3.Call[](2);

            calls[0].target = address(_dgDeployedContracts.dualGovernance);
            calls[0].callData =
                abi.encodeCall(_dgDeployedContracts.dualGovernance.scheduleProposal, (regularProposalId));

            calls[1].target = address(_timelock);
            calls[1].callData = abi.encodeCall(_timelock.execute, (regularProposalId));

            IMulticall3(MULTICALL3_MAINNET).aggregate(calls);

            _assertProposalExecuted(regularProposalId);
            _assertTargetMockCalls(_getAdminExecutor(), regularStuffCalls);
        }
    }
}
