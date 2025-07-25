// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TimelockState} from "contracts/libraries/TimelockState.sol";
import {ExecutableProposals, Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";

import {IRageQuitEscrow, ContractsDeployment, DGRegressionTestSetup} from "../utils/integration-tests.sol";

import {ExternalCallsBuilder, ExternalCall} from "scripts/utils/ExternalCallsBuilder.sol";

import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";

import {
    ImmutableDualGovernanceConfigProvider,
    DualGovernanceConfig
} from "contracts/ImmutableDualGovernanceConfigProvider.sol";
import {Escrow} from "contracts/Escrow.sol";
import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IDualGovernanceConfigProvider} from "contracts/interfaces/IDualGovernanceConfigProvider.sol";

import {Proposers} from "contracts/libraries/Proposers.sol";

import {PercentsD16, PercentD16, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

import {ContractsDeployment, DGRegressionTestSetup} from "test/utils/integration-tests.sol";
import {
    DGSetupDeployArtifacts,
    DGSetupDeployConfig,
    TiebreakerDeployConfig,
    TiebreakerDeployedContracts
} from "scripts/utils/contracts-deployment.sol";

contract DualGovernanceUpgradeScenariosRegressionTest is DGRegressionTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _loadOrDeployDGSetup();
        _setupStETHBalance(_VETOER, PercentsD16.fromBasisPoints(30_00));
    }

    function testFork_OldEscrowInstanceAllowsUnlockTokens_HappyPath() external {
        DualGovernance newDualGovernanceInstance;
        _step("1. Deploy new Dual Governance implementation");
        {
            newDualGovernanceInstance = ContractsDeployment.deployDualGovernance(
                DualGovernance.DualGovernanceComponents({
                    timelock: _timelock,
                    resealManager: _dgDeployedContracts.resealManager,
                    configProvider: _dgDeployedContracts.dualGovernanceConfigProvider
                }),
                _dgDeployConfig.dualGovernance
            );
        }

        uint256 updateDualGovernanceProposalId;
        _step("2. Submit proposal to update the Dual Governance implementation");
        {
            updateDualGovernanceProposalId = _submitProposalByAdminProposer(
                _getActionsToUpdateDualGovernanceImplementation(address(newDualGovernanceInstance)),
                "Update the Dual Governance implementation"
            );
        }

        _step("3. Users accumulate some stETH in the Signalling Escrow");
        {
            _lockStETHUpTo(_VETOER, _getSecondSealRageQuitSupport() - PercentsD16.from(10));
            _assertVetoSignalingState();
            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoSignallingDeactivationState();
            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoCooldownState();
        }

        _step("4. When the VetoCooldown is entered proposal to update becomes executable");
        {
            _scheduleProposal(updateDualGovernanceProposalId);
            _assertProposalScheduled(updateDualGovernanceProposalId);

            _wait(_getAfterScheduleDelay());
            _executeProposal(updateDualGovernanceProposalId);

            assertEq(_timelock.getGovernance(), address(newDualGovernanceInstance));
        }

        _step("5. The old instance of the Dual Governance can't submit proposals anymore");
        {
            // wait until the VetoCooldown ends in the old dual governance instance
            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();

            // old instance of the Dual Governance can't submit proposals anymore
            vm.expectRevert(
                abi.encodeWithSelector(
                    TimelockState.CallerIsNotGovernance.selector, address(_dgDeployedContracts.dualGovernance)
                )
            );
            vm.prank(address(_lido.voting));
            _dgDeployedContracts.dualGovernance.submitProposal(_getMockTargetRegularStaffCalls(), "Regular actions");
        }

        _step("6. Users can unlock stETH from the old Signalling Escrow");
        {
            _unlockStETH(_VETOER);
        }

        _step("7. Users can withdraw funds even if the Rage Quit is started in the old instance of the Dual Governance");
        {
            // the Rage Quit started on the old DualGovernance instance
            _lockStETH(_VETOER, _getSecondSealRageQuitSupport());
            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();

            // The Rage Quit may be finished in the previous DG instance so vetoers will not lose their funds by mistake
            IRageQuitEscrow rageQuitEscrow = _getRageQuitEscrow();

            while (!rageQuitEscrow.isWithdrawalsBatchesClosed()) {
                rageQuitEscrow.requestNextWithdrawalsBatch(96);
            }

            _finalizeWithdrawalQueue();

            while (rageQuitEscrow.getUnclaimedUnstETHIdsCount() > 0) {
                rageQuitEscrow.claimNextWithdrawalsBatch(32);
            }

            rageQuitEscrow.startRageQuitExtensionPeriod();

            _wait(_getRageQuitExtensionPeriodDuration().plusSeconds(1));
            assertEq(rageQuitEscrow.isRageQuitFinalized(), true);

            _wait(_getRageQuitEthWithdrawalsDelay());

            uint256 vetoerETHBalanceBefore = _VETOER.balance;

            vm.prank(_VETOER);
            rageQuitEscrow.withdrawETH();

            assertTrue(_VETOER.balance > vetoerETHBalanceBefore);
        }
    }

    function testFork_ProposalExecution_RevertOn_SubmittedViaOldGovernance() external {
        // DAO initiates the update of the Dual Governance
        // Malicious actor locks funds in the Signalling Escrow to waste the full duration of VetoSignalling
        // At the end of the VetoSignalling, malicious actor unlocks all funds from VetoSignalling and
        //  submits proposal to steal the control over governance
        //
        DualGovernance newDualGovernanceInstance;
        _step("1. Deploy new Dual Governance implementation");
        {
            newDualGovernanceInstance = ContractsDeployment.deployDualGovernance(
                DualGovernance.DualGovernanceComponents({
                    timelock: _timelock,
                    resealManager: _dgDeployedContracts.resealManager,
                    configProvider: _dgDeployedContracts.dualGovernanceConfigProvider
                }),
                _dgDeployConfig.dualGovernance
            );
        }

        uint256 updateDualGovernanceProposalId;
        _step("2. DAO submits proposal to update the Dual Governance implementation");
        {
            updateDualGovernanceProposalId = _submitProposalByAdminProposer(
                _getActionsToUpdateDualGovernanceImplementation(address(newDualGovernanceInstance)),
                "Update the Dual Governance implementation"
            );
        }

        _step("3. Malicious actor accumulate second seal in the Signalling Escrow");
        {
            _lockStETH(_VETOER, _getSecondSealRageQuitSupport());
            _wait(_getVetoSignallingMaxDuration().minusSeconds(_lido.voting.voteTime()));
            _assertVetoSignalingState();
        }

        uint256 maliciousProposalId;
        _step("4. Malicious actor unlock funds from Signalling Escrow");
        {
            ExternalCall[] memory maliciousCalls = new ExternalCall[](1);
            maliciousCalls[0].target = address(_timelock);
            maliciousCalls[0].payload = abi.encodeCall(_timelock.setGovernance, (_VETOER));

            maliciousProposalId = _submitProposalByAdminProposer(maliciousCalls, "Steal control over timelock contract");

            _unlockStETH(_VETOER);
            _assertVetoSignallingDeactivationState();
        }

        _step("5. Regular can't collect second seal in VETO_SIGNALLING_DEACTIVATION_MAX_DURATION");
        {
            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();
        }

        _step("6. The Dual Governance implementation is updated on the new version");
        {
            // Malicious proposal can't be executed directly on the old DualGovernance instance, as it was submitted
            // during the VetoSignalling phase
            vm.expectRevert(
                abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, maliciousProposalId)
            );
            _dgDeployedContracts.dualGovernance.scheduleProposal(maliciousProposalId);

            _scheduleProposal(updateDualGovernanceProposalId);
            _assertProposalScheduled(updateDualGovernanceProposalId);

            _wait(_getAfterScheduleDelay());
            _executeProposal(updateDualGovernanceProposalId);

            assertEq(_timelock.getGovernance(), address(newDualGovernanceInstance));
        }

        _step("7. After the update malicious proposal is cancelled and can't be executed via new DualGovernance");
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ExecutableProposals.UnexpectedProposalStatus.selector, maliciousProposalId, ProposalStatus.Cancelled
                )
            );
            newDualGovernanceInstance.scheduleProposal(maliciousProposalId);

            assertEq(_timelock.getProposalDetails(maliciousProposalId).status, ProposalStatus.Cancelled);
        }
    }

    function testFork_DualGovernanceUpgradeInNormalMode() external {
        _step("1. DAO operates as usual");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO performs regular stuff on a potentially dangerous contract"
            );

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _assertCanSchedule(proposalId, false);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }

        _step("2. Vetoer vetoes 50% of the 1st seal");
        {
            _lockStETHUpTo(_VETOER, PercentsD16.fromBasisPoints(50));
        }

        _step("3. Deploy new Dual Governance and Tiebreaker");
        DualGovernance newDualGovernance;
        TiebreakerCoreCommittee newTiebreakerCoreCommittee;
        DGSetupDeployConfig.Context memory previousDGDeployConfig;
        {
            DGSetupDeployArtifacts.Context memory deployArtifact =
                DGSetupDeployArtifacts.load(vm.envString("DEPLOY_ARTIFACT_FILE_NAME"));

            previousDGDeployConfig = deployArtifact.deployConfig;

            // Deploy new Dual Governance
            DualGovernance.DualGovernanceComponents memory components = DualGovernance.DualGovernanceComponents({
                timelock: deployArtifact.deployedContracts.timelock,
                resealManager: deployArtifact.deployedContracts.resealManager,
                configProvider: deployArtifact.deployedContracts.dualGovernanceConfigProvider
            });

            newDualGovernance = new DualGovernance(
                components,
                previousDGDeployConfig.dualGovernance.signallingTokens,
                previousDGDeployConfig.dualGovernance.sanityCheckParams
            );

            TiebreakerDeployConfig.Context memory tiebreakerConfig = deployArtifact.deployConfig.tiebreaker;
            tiebreakerConfig.chainId = deployArtifact.deployConfig.chainId;
            tiebreakerConfig.owner = address(deployArtifact.deployedContracts.adminExecutor);
            tiebreakerConfig.dualGovernance = address(newDualGovernance);

            // Deploying new Tiebreaker
            TiebreakerDeployedContracts.Context memory tiebreakerDeployedContracts =
                ContractsDeployment.deployTiebreaker(tiebreakerConfig, address(this));

            newTiebreakerCoreCommittee = tiebreakerDeployedContracts.tiebreakerCoreCommittee;
        }

        _step("4. DAO proposes to upgrade the Dual Governance");

        {
            ExternalCallsBuilder.Context memory upgradeDGCallsBuilder = ExternalCallsBuilder.create({callsCount: 8});

            // 1. Set Tiebreaker activation timeout
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    ITiebreaker.setTiebreakerActivationTimeout,
                    previousDGDeployConfig.dualGovernance.tiebreakerActivationTimeout
                )
            );

            // 2. Set Tiebreaker committee
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(ITiebreaker.setTiebreakerCommittee, address(newTiebreakerCoreCommittee))
            );

            // 3. Add Accounting Oracle as Tiebreaker withdrawal blocker
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    ITiebreaker.addTiebreakerSealableWithdrawalBlocker,
                    previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[0]
                )
            );

            // 4. Add Validators Exit Bus Oracle as Tiebreaker withdrawal blocker
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    ITiebreaker.addTiebreakerSealableWithdrawalBlocker,
                    previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[1]
                )
            );

            // 5. Register Aragon Voting as admin proposer
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(IDualGovernance.registerProposer, (address(_lido.voting), _getAdminExecutor()))
            );

            // 6. Set Aragon Voting as proposals canceller
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance), abi.encodeCall(IDualGovernance.setProposalsCanceller, address(_lido.voting))
            );

            // 7. Set reseal committee
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    IDualGovernance.setResealCommittee, address(previousDGDeployConfig.dualGovernance.resealCommittee)
                )
            );

            // 8. Upgrade Dual Governance
            upgradeDGCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(ITimelock.setGovernance, address(newDualGovernance))
            );

            uint256 proposalId =
                _submitProposalByAdminProposer(upgradeDGCallsBuilder.getResult(), "Upgrade Dual Governance");
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, upgradeDGCallsBuilder.getResult());

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);

            _wait(_getAfterScheduleDelay());

            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);

            _dgDeployedContracts.dualGovernance = DualGovernance(newDualGovernance);
            _dgDeployedContracts.tiebreakerCoreCommittee = TiebreakerCoreCommittee(newTiebreakerCoreCommittee);
            _dgDeployedContracts.escrowMasterCopy = Escrow(
                payable(address(Escrow(payable(newDualGovernance.getVetoSignallingEscrow())).ESCROW_MASTER_COPY()))
            );

            address[] memory tiebreakerSubCommitteesAddresses =
                _dgDeployedContracts.tiebreakerCoreCommittee.getMembers();

            _dgDeployedContracts.tiebreakerSubCommittees =
                new TiebreakerSubCommittee[](tiebreakerSubCommitteesAddresses.length);

            for (uint256 i = 0; i < tiebreakerSubCommitteesAddresses.length; ++i) {
                _dgDeployedContracts.tiebreakerSubCommittees[i] =
                    TiebreakerSubCommittee(tiebreakerSubCommitteesAddresses[i]);
            }
        }

        _step("5. Check Dual Governance state");
        {
            // Check emergency protection
            assertTrue(_timelock.isEmergencyProtectionEnabled());
            assertFalse(_timelock.isEmergencyModeActive());

            // Check governance set correctly
            ITiebreaker.TiebreakerDetails memory tiebreakerDetails = newDualGovernance.getTiebreakerDetails();
            assertEq(
                tiebreakerDetails.tiebreakerActivationTimeout,
                previousDGDeployConfig.dualGovernance.tiebreakerActivationTimeout
            );
            assertEq(tiebreakerDetails.tiebreakerCommittee, address(newTiebreakerCoreCommittee));
            assertEq(tiebreakerDetails.sealableWithdrawalBlockers.length, 2);
            assertEq(
                tiebreakerDetails.sealableWithdrawalBlockers[0],
                previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[0]
            );
            assertEq(
                tiebreakerDetails.sealableWithdrawalBlockers[1],
                previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[1]
            );

            assertEq(newDualGovernance.getProposers().length, 1);
            Proposers.Proposer memory proposer = newDualGovernance.getProposer(address(_lido.voting));
            assertEq(proposer.executor, _getAdminExecutor());
            assertEq(proposer.account, address(_lido.voting));

            assertEq(newDualGovernance.getProposalsCanceller(), address(_lido.voting));

            assertEq(
                newDualGovernance.getResealCommittee(), address(previousDGDeployConfig.dualGovernance.resealCommittee)
            );
            assertEq(_timelock.getGovernance(), address(newDualGovernance));
        }

        _step("6. DAO operates as usually");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposalByAdminProposer(regularStaffCalls, "DAO performs regular stuff");

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _assertCanSchedule(proposalId, false);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }

        _step("7. Emergency Committee activates emergency mode if needed");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }
    }

    function testFork_DualGovernanceUpgradeAndNewConfigForOldDualGovernanceInNormalMode() external {
        _step("1. DAO operates as usual");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO performs regular stuff on a potentially dangerous contract"
            );

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _assertCanSchedule(proposalId, false);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }

        _step("2. Vetoer vetoes 50% of the 1st seal");
        {
            _lockStETHUpTo(_VETOER, PercentsD16.fromBasisPoints(50));
        }

        _step("3. Deploy new Dual Governance and Tiebreaker");
        DualGovernance newDualGovernance;
        TiebreakerCoreCommittee newTiebreakerCoreCommittee;
        DGSetupDeployConfig.Context memory previousDGDeployConfig;
        ImmutableDualGovernanceConfigProvider newImmutableDualGovernanceConfigProvider;
        {
            DGSetupDeployArtifacts.Context memory deployArtifact =
                DGSetupDeployArtifacts.load(vm.envString("DEPLOY_ARTIFACT_FILE_NAME"));

            previousDGDeployConfig = deployArtifact.deployConfig;

            // Deploy new Dual Governance
            DualGovernance.DualGovernanceComponents memory components = DualGovernance.DualGovernanceComponents({
                timelock: deployArtifact.deployedContracts.timelock,
                resealManager: deployArtifact.deployedContracts.resealManager,
                configProvider: deployArtifact.deployedContracts.dualGovernanceConfigProvider
            });

            newDualGovernance = new DualGovernance(
                components,
                previousDGDeployConfig.dualGovernance.signallingTokens,
                previousDGDeployConfig.dualGovernance.sanityCheckParams
            );

            TiebreakerDeployConfig.Context memory tiebreakerConfig = deployArtifact.deployConfig.tiebreaker;
            tiebreakerConfig.chainId = deployArtifact.deployConfig.chainId;
            tiebreakerConfig.owner = address(deployArtifact.deployedContracts.adminExecutor);
            tiebreakerConfig.dualGovernance = address(newDualGovernance);

            // Deploying new Tiebreaker
            TiebreakerDeployedContracts.Context memory tiebreakerDeployedContracts =
                ContractsDeployment.deployTiebreaker(tiebreakerConfig, address(this));

            newTiebreakerCoreCommittee = tiebreakerDeployedContracts.tiebreakerCoreCommittee;

            // Deploying new ImmutableDualGovernanceConfigProvider with thresholds set to 100%
            DualGovernanceConfig.Context memory newDualGovernanceConfigForOldDualGovernance = DualGovernanceConfig
                .Context({
                firstSealRageQuitSupport: PercentsD16.from(HUNDRED_PERCENT_D16 - 1),
                secondSealRageQuitSupport: PercentsD16.from(HUNDRED_PERCENT_D16),
                minAssetsLockDuration: Durations.from(1),
                vetoSignallingMinDuration: Durations.from(0),
                vetoSignallingMaxDuration: Durations.from(1),
                vetoSignallingMinActiveDuration: Durations.from(0),
                vetoSignallingDeactivationMaxDuration: Durations.from(0),
                vetoCooldownDuration: Durations.from(0),
                rageQuitExtensionPeriodDuration: Durations.from(0),
                rageQuitEthWithdrawalsMinDelay: Durations.from(0),
                rageQuitEthWithdrawalsMaxDelay: Durations.from(0),
                rageQuitEthWithdrawalsDelayGrowth: Durations.from(0)
            });

            newImmutableDualGovernanceConfigProvider =
                new ImmutableDualGovernanceConfigProvider(newDualGovernanceConfigForOldDualGovernance);
        }

        _step("4. DAO proposes to upgrade the Dual Governance");
        DualGovernance previousDualGovernance;
        {
            ExternalCallsBuilder.Context memory upgradeDGCallsBuilder = ExternalCallsBuilder.create({callsCount: 9});

            // 1. Set Tiebreaker activation timeout
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    ITiebreaker.setTiebreakerActivationTimeout,
                    previousDGDeployConfig.dualGovernance.tiebreakerActivationTimeout
                )
            );

            // 2. Set Tiebreaker committee
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(ITiebreaker.setTiebreakerCommittee, address(newTiebreakerCoreCommittee))
            );

            // 3. Add Accounting Oracle as Tiebreaker withdrawal blocker
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    ITiebreaker.addTiebreakerSealableWithdrawalBlocker,
                    previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[0]
                )
            );

            // 4. Add Validators Exit Bus Oracle as Tiebreaker withdrawal blocker
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    ITiebreaker.addTiebreakerSealableWithdrawalBlocker,
                    previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[1]
                )
            );

            // 5. Register Aragon Voting as admin proposer
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(IDualGovernance.registerProposer, (address(_lido.voting), _getAdminExecutor()))
            );

            // 6. Set Aragon Voting as proposals canceller
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance), abi.encodeCall(IDualGovernance.setProposalsCanceller, address(_lido.voting))
            );

            // 7. Set reseal committee
            upgradeDGCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    IDualGovernance.setResealCommittee, address(previousDGDeployConfig.dualGovernance.resealCommittee)
                )
            );

            // 8. Upgrade Dual Governance
            upgradeDGCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(ITimelock.setGovernance, address(newDualGovernance))
            );

            // 9. Set new ImmutableDualGovernanceConfigProvider
            upgradeDGCallsBuilder.addCall(
                address(_dgDeployedContracts.dualGovernance),
                abi.encodeCall(IDualGovernance.setConfigProvider, newImmutableDualGovernanceConfigProvider)
            );

            uint256 proposalId =
                _submitProposalByAdminProposer(upgradeDGCallsBuilder.getResult(), "Upgrade Dual Governance");
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, upgradeDGCallsBuilder.getResult());

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);

            _wait(_getAfterScheduleDelay());

            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);

            previousDualGovernance = _dgDeployedContracts.dualGovernance;

            _dgDeployedContracts.dualGovernance = DualGovernance(newDualGovernance);
            _dgDeployedContracts.tiebreakerCoreCommittee = TiebreakerCoreCommittee(newTiebreakerCoreCommittee);
            _dgDeployedContracts.escrowMasterCopy = Escrow(
                payable(address(Escrow(payable(newDualGovernance.getVetoSignallingEscrow())).ESCROW_MASTER_COPY()))
            );

            address[] memory tiebreakerSubCommitteesAddresses =
                _dgDeployedContracts.tiebreakerCoreCommittee.getMembers();

            _dgDeployedContracts.tiebreakerSubCommittees =
                new TiebreakerSubCommittee[](tiebreakerSubCommitteesAddresses.length);

            for (uint256 i = 0; i < tiebreakerSubCommitteesAddresses.length; ++i) {
                _dgDeployedContracts.tiebreakerSubCommittees[i] =
                    TiebreakerSubCommittee(tiebreakerSubCommitteesAddresses[i]);
            }
        }

        _step("5. Check Dual Governance state");
        {
            // Check emergency protection
            assertTrue(_timelock.isEmergencyProtectionEnabled());
            assertFalse(_timelock.isEmergencyModeActive());

            // Check governance set correctly
            ITiebreaker.TiebreakerDetails memory tiebreakerDetails = newDualGovernance.getTiebreakerDetails();
            assertEq(
                tiebreakerDetails.tiebreakerActivationTimeout,
                previousDGDeployConfig.dualGovernance.tiebreakerActivationTimeout
            );
            assertEq(tiebreakerDetails.tiebreakerCommittee, address(newTiebreakerCoreCommittee));
            assertEq(tiebreakerDetails.sealableWithdrawalBlockers.length, 2);
            assertEq(
                tiebreakerDetails.sealableWithdrawalBlockers[0],
                previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[0]
            );
            assertEq(
                tiebreakerDetails.sealableWithdrawalBlockers[1],
                previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[1]
            );

            assertEq(newDualGovernance.getProposers().length, 1);
            Proposers.Proposer memory proposer = newDualGovernance.getProposer(address(_lido.voting));
            assertEq(proposer.executor, _getAdminExecutor());
            assertEq(proposer.account, address(_lido.voting));

            assertEq(newDualGovernance.getProposalsCanceller(), address(_lido.voting));

            assertEq(
                newDualGovernance.getResealCommittee(), address(previousDGDeployConfig.dualGovernance.resealCommittee)
            );
            assertEq(_timelock.getGovernance(), address(newDualGovernance));

            assertEq(
                address(previousDualGovernance.getConfigProvider()), address(newImmutableDualGovernanceConfigProvider)
            );

            Escrow oldEscrow = Escrow(payable(previousDualGovernance.getVetoSignallingEscrow()));
            assertEq(oldEscrow.getMinAssetsLockDuration(), Durations.from(1));
        }

        _step("6. DAO operates as usually");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposalByAdminProposer(regularStaffCalls, "DAO performs regular stuff");

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _assertCanSchedule(proposalId, false);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }

        _step("7. Emergency Committee activates emergency mode if needed");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }
    }

    function testFork_DualGovernanceUpgradeWithEmergencyMode() external {
        _step("1. DAO operates as usual");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO performs regular stuff on a potentially dangerous contract"
            );

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _assertCanSchedule(proposalId, false);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }

        _step("2. Vetoer vetoes 50% of the 1st seal");
        {
            _lockStETHUpTo(_VETOER, PercentsD16.fromBasisPoints(50));
        }

        // Emergency committee activates emergency mode
        _step("3. Activate emergency mode");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }

        _step("4. Deploy new Dual Governance and Tiebreaker");
        DualGovernance newDualGovernance;
        TiebreakerCoreCommittee newTiebreakerCoreCommittee;
        DGSetupDeployConfig.Context memory previousDGDeployConfig;
        {
            DGSetupDeployArtifacts.Context memory deployArtifact =
                DGSetupDeployArtifacts.load(vm.envString("DEPLOY_ARTIFACT_FILE_NAME"));

            previousDGDeployConfig = deployArtifact.deployConfig;

            // Deploy new Dual Governance
            DualGovernance.DualGovernanceComponents memory components = DualGovernance.DualGovernanceComponents({
                timelock: deployArtifact.deployedContracts.timelock,
                resealManager: deployArtifact.deployedContracts.resealManager,
                configProvider: deployArtifact.deployedContracts.dualGovernanceConfigProvider
            });

            newDualGovernance = new DualGovernance(
                components,
                previousDGDeployConfig.dualGovernance.signallingTokens,
                previousDGDeployConfig.dualGovernance.sanityCheckParams
            );

            TiebreakerDeployConfig.Context memory tiebreakerConfig = deployArtifact.deployConfig.tiebreaker;
            tiebreakerConfig.chainId = deployArtifact.deployConfig.chainId;
            tiebreakerConfig.owner = address(deployArtifact.deployedContracts.adminExecutor);
            tiebreakerConfig.dualGovernance = address(newDualGovernance);

            // Deploying new Tiebreaker
            TiebreakerDeployedContracts.Context memory tiebreakerDeployedContracts =
                ContractsDeployment.deployTiebreaker(tiebreakerConfig, address(this));

            newTiebreakerCoreCommittee = tiebreakerDeployedContracts.tiebreakerCoreCommittee;
        }

        _step("5. DAO proposes to upgrade the Dual Governance");
        address emergencyActivationCommittee;
        address emergencyExecutionCommittee;
        {
            emergencyActivationCommittee = _timelock.getEmergencyActivationCommittee();
            emergencyExecutionCommittee = _timelock.getEmergencyExecutionCommittee();
            Timestamp emergencyModeEndsAfter = Timestamps.from(block.timestamp + 365 days);
            Duration emergencyModeDuration = Durations.from(30 days);

            ExternalCallsBuilder.Context memory upgradeDGAndExtendEmergencyProtectionCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 13});

            // 1. Deactivate emergency mode
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.deactivateEmergencyMode, ())
            );

            // 2. Set emergency protection end date
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyProtectionEndDate, (emergencyModeEndsAfter))
            );

            // 3. Set emergency mode duration for a year
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyModeDuration, (emergencyModeDuration))
            );

            // 4. Set emergency protection activation committee
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setEmergencyProtectionActivationCommittee, (emergencyActivationCommittee))
            );

            // 5. Set emergency protection execution committee
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setEmergencyProtectionExecutionCommittee, (emergencyExecutionCommittee))
            );

            // 6. Set Tiebreaker activation timeout
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    ITiebreaker.setTiebreakerActivationTimeout,
                    (previousDGDeployConfig.dualGovernance.tiebreakerActivationTimeout)
                )
            );

            // 7. Set Tiebreaker committee
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(ITiebreaker.setTiebreakerCommittee, address(newTiebreakerCoreCommittee))
            );

            // 8. Add Accounting Oracle as Tiebreaker withdrawal blocker
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    ITiebreaker.addTiebreakerSealableWithdrawalBlocker,
                    previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[0]
                )
            );

            // 9. Add Validators Exit Bus Oracle as Tiebreaker withdrawal blocker
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    ITiebreaker.addTiebreakerSealableWithdrawalBlocker,
                    previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[1]
                )
            );

            // 10. Register Aragon Voting as admin proposer
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(IDualGovernance.registerProposer, (address(_lido.voting), _getAdminExecutor()))
            );

            // 11. Set Aragon Voting as proposals canceller
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(newDualGovernance), abi.encodeCall(IDualGovernance.setProposalsCanceller, address(_lido.voting))
            );

            // 12. Set reseal committee
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(newDualGovernance),
                abi.encodeCall(
                    IDualGovernance.setResealCommittee, address(previousDGDeployConfig.dualGovernance.resealCommittee)
                )
            );

            // 13. Upgrade Dual Governance
            upgradeDGAndExtendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(ITimelock.setGovernance, address(newDualGovernance))
            );

            uint256 proposalId = _submitProposalByAdminProposer(
                upgradeDGAndExtendEmergencyProtectionCallsBuilder.getResult(),
                "Upgrade Dual Governance and extend emergency protection"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, upgradeDGAndExtendEmergencyProtectionCallsBuilder.getResult());

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);

            _wait(_getAfterScheduleDelay());

            //Proposal can't be executed, because emergency mode is active
            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(proposalId);

            //Emergency committee executes the proposal
            _emergencyExecute(proposalId);
            _assertProposalExecuted(proposalId);

            _dgDeployedContracts.dualGovernance = DualGovernance(newDualGovernance);
            _dgDeployedContracts.tiebreakerCoreCommittee = TiebreakerCoreCommittee(newTiebreakerCoreCommittee);
            _dgDeployedContracts.escrowMasterCopy = Escrow(
                payable(address(Escrow(payable(newDualGovernance.getVetoSignallingEscrow())).ESCROW_MASTER_COPY()))
            );

            address[] memory tiebreakerSubCommitteesAddresses =
                _dgDeployedContracts.tiebreakerCoreCommittee.getMembers();

            _dgDeployedContracts.tiebreakerSubCommittees =
                new TiebreakerSubCommittee[](tiebreakerSubCommitteesAddresses.length);

            for (uint256 i = 0; i < tiebreakerSubCommitteesAddresses.length; ++i) {
                _dgDeployedContracts.tiebreakerSubCommittees[i] =
                    TiebreakerSubCommittee(tiebreakerSubCommitteesAddresses[i]);
            }
        }

        _step("6. Check Dual Governance state");
        {
            assertEq(_timelock.getEmergencyActivationCommittee(), emergencyActivationCommittee);
            assertEq(_timelock.getEmergencyExecutionCommittee(), emergencyExecutionCommittee);
            assertTrue(_timelock.isEmergencyProtectionEnabled());
            assertFalse(_timelock.isEmergencyModeActive());

            // Check governance set correctly
            ITiebreaker.TiebreakerDetails memory tiebreakerDetails = newDualGovernance.getTiebreakerDetails();
            assertEq(
                tiebreakerDetails.tiebreakerActivationTimeout,
                previousDGDeployConfig.dualGovernance.tiebreakerActivationTimeout
            );
            assertEq(tiebreakerDetails.tiebreakerCommittee, address(newTiebreakerCoreCommittee));
            assertEq(tiebreakerDetails.sealableWithdrawalBlockers.length, 2);
            assertEq(
                tiebreakerDetails.sealableWithdrawalBlockers[0],
                previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[0]
            );
            assertEq(
                tiebreakerDetails.sealableWithdrawalBlockers[1],
                previousDGDeployConfig.dualGovernance.sealableWithdrawalBlockers[1]
            );

            assertEq(newDualGovernance.getProposers().length, 1);
            Proposers.Proposer memory proposer = newDualGovernance.getProposer(address(_lido.voting));
            assertEq(proposer.executor, _getAdminExecutor());
            assertEq(proposer.account, address(_lido.voting));

            assertEq(newDualGovernance.getProposalsCanceller(), address(_lido.voting));

            assertEq(
                newDualGovernance.getResealCommittee(), address(previousDGDeployConfig.dualGovernance.resealCommittee)
            );
            assertEq(_timelock.getGovernance(), address(newDualGovernance));
        }

        _step("7. DAO operates as usually");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposalByAdminProposer(regularStaffCalls, "DAO performs regular stuff");

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _assertCanSchedule(proposalId, false);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }

        _step("8. Emergency Committee activates emergency mode if needed");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }
    }

    function testFork_ActivationAndExtensionOfEmergencyProtection() external {
        _step("1. DAO operates as usual");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO performs regular stuff on a potentially dangerous contract"
            );

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _assertCanSchedule(proposalId, false);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }

        _step("2. Malicious proposal is submitted");
        uint256 maliciousProposalId;
        {
            // Malicious vote was proposed by the attacker with huge LDO wad (but still not the majority)
            maliciousProposalId = _submitProposalByAdminProposer(_getMaliciousCalls(), "Rug Pool attempt");

            // the call isn't executable until the delay has passed
            _assertProposalSubmitted(maliciousProposalId);
            _assertCanSchedule(maliciousProposalId, false);

            // after the submit delay has passed, the call still may be scheduled, but executed
            // only the emergency committee
            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(maliciousProposalId, true);
            _scheduleProposal(maliciousProposalId);

            _wait(_getAfterScheduleDelay());
        }

        _step("3. Vetoer vetoes 50% of the 1st seal");
        {
            _lockStETHUpTo(_VETOER, PercentsD16.fromBasisPoints(50));
        }

        // Emergency committee activates emergency mode
        _step("4. Activate emergency mode");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }

        _step("5. Malicious proposal can't be executed");
        {
            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(maliciousProposalId);
        }

        _step("6. Emergency committee lifetime is up to end. DAO extends the emergency protection");
        address emergencyActivationCommittee;
        address emergencyExecutionCommittee;
        address emergencyGovernance;
        {
            emergencyActivationCommittee = _timelock.getEmergencyActivationCommittee();
            emergencyExecutionCommittee = _timelock.getEmergencyExecutionCommittee();
            Timestamp emergencyModeEndsAfter = Timestamps.from(block.timestamp + 365 days);
            Duration emergencyModeDuration = _timelock.MAX_EMERGENCY_MODE_DURATION().minusSeconds(1);

            _wait(_getEmergencyProtectionDuration().minusSeconds(5 days));
            assertTrue(_timelock.isEmergencyProtectionEnabled());
            assertTrue(_timelock.isEmergencyModeActive());

            ExternalCallsBuilder.Context memory extendEmergencyProtectionCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 6});

            // Deactivate emergency mode
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.deactivateEmergencyMode, ())
            );

            // Set emergency governance as governance to disable Dual Governance until the decision is made
            emergencyGovernance = _timelock.getEmergencyGovernance();
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setGovernance, (emergencyGovernance))
            );

            // Set emergency protection end date
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyProtectionEndDate, (emergencyModeEndsAfter))
            );

            // Set new emergency mode duration for a year
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyModeDuration, (emergencyModeDuration))
            );

            // Reset emergency protection committees
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setEmergencyProtectionActivationCommittee, (emergencyActivationCommittee))
            );

            // Reset emergency protection execution committee
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setEmergencyProtectionExecutionCommittee, (emergencyExecutionCommittee))
            );

            uint256 proposalId = _submitProposalByAdminProposer(
                extendEmergencyProtectionCallsBuilder.getResult(), "Extend emergency protection"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, extendEmergencyProtectionCallsBuilder.getResult());

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);

            _wait(_getAfterScheduleDelay());

            //Proposal can't be executed, because emergency mode is active
            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(proposalId);

            //Emergency committee executes the proposal
            _emergencyExecute(proposalId);
            _assertProposalExecuted(proposalId);
        }

        _step("7. Check Dual Governance state");
        {
            assertEq(_timelock.getGovernance(), emergencyGovernance);

            // Check that emergency protection is extended
            assertEq(_timelock.getEmergencyActivationCommittee(), emergencyActivationCommittee);
            assertEq(_timelock.getEmergencyExecutionCommittee(), emergencyExecutionCommittee);
            assertTrue(_timelock.isEmergencyProtectionEnabled());
            assertFalse(_timelock.isEmergencyModeActive());

            // Check malicious proposal was cancelled
            _assertProposalCancelled(maliciousProposalId);
        }

        _step("8. DAO operates as usually");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposal(address(_lido.voting), regularStaffCalls, "DAO performs regular stuff");

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _assertCanSchedule(proposalId, false);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }

        _step("9. Emergency Committee activates emergency mode if needed");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }
    }

    // ---
    // Helper methods
    // ---
    function _getActionsToUpdateDualGovernanceImplementation(address newDualGovernanceInstance)
        internal
        view
        returns (ExternalCall[] memory)
    {
        ExternalCallsBuilder.Context memory callsBuilder = ExternalCallsBuilder.create({callsCount: 2});

        callsBuilder.addCall(
            address(newDualGovernanceInstance),
            abi.encodeCall(DualGovernance.registerProposer, (address(_lido.voting), _timelock.getAdminExecutor()))
        );

        callsBuilder.addCall(
            address(_timelock), abi.encodeCall(_timelock.setGovernance, (address(newDualGovernanceInstance)))
        );

        return callsBuilder.getResult();
    }

    function external__submitProposalByAdminProposer(ExternalCall[] memory calls)
        external
        returns (uint256 proposalId)
    {
        proposalId = _submitProposalByAdminProposer(calls);
    }
}
