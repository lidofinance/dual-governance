// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";
import {ExecutableProposals, Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";

import {
    Duration, Durations, Timestamps, ContractsDeployment, DGRegressionTestSetup
} from "../utils/integration-tests.sol";

import {PercentsD16, PercentD16} from "contracts/types/PercentD16.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";

import {ExternalCallsBuilder, ExternalCall} from "scripts/utils/ExternalCallsBuilder.sol";
import {
    DGSetupDeployArtifacts,
    TiebreakerDeployConfig,
    TiebreakerDeployedContracts
} from "scripts/utils/contracts-deployment.sol";

import {LidoUtils} from "../utils/lido-utils.sol";

contract DGUpgradeScenarioTest is DGRegressionTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;
    using PercentsD16 for PercentD16;
    using LidoUtils for LidoUtils.Context;

    LidoUtils.Context internal lidoUtils;

    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _loadOrDeployDGSetup();
        _setupStETHBalance(_VETOER, PercentsD16.fromBasisPoints(30_00));
        lidoUtils = LidoUtils.mainnet();
    }

    function testFork_DualGovernanceUpgradeWithEmergencyMode() external {
        _step(unicode"1. DAO operates as usually");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
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

        _step(unicode"2. Vetoer vetoes 50% of the 1st seal");
        {
            _lockStETHUpTo(_VETOER, _getFirstSealRageQuitSupport() - PercentsD16.fromBasisPoints(10));
        }

        // Emergency committee activates emergency mode and
        _step(unicode"3. Activate emergency mode");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }
        _step("4. Deploy new Dual Governance");

        DGSetupDeployArtifacts.Context memory deployArtifact =
            DGSetupDeployArtifacts.load(vm.envString("DEPLOY_ARTIFACT_FILE_NAME"));
        {
            // Deploy new Dual Governance
            DualGovernance.DualGovernanceComponents memory components = DualGovernance.DualGovernanceComponents({
                timelock: deployArtifact.deployedContracts.timelock,
                resealManager: deployArtifact.deployedContracts.resealManager,
                configProvider: deployArtifact.deployedContracts.dualGovernanceConfigProvider
            });

            DualGovernance dualGovernance = new DualGovernance(
                components,
                deployArtifact.deployConfig.dualGovernance.signallingTokens,
                deployArtifact.deployConfig.dualGovernance.sanityCheckParams
            );

            deployArtifact.deployedContracts.dualGovernance = dualGovernance;

            TiebreakerDeployConfig.Context memory tiebreakerConfig;
            tiebreakerConfig.chainId = deployArtifact.deployConfig.chainId;
            tiebreakerConfig.owner = address(deployArtifact.deployedContracts.adminExecutor);
            tiebreakerConfig.dualGovernance = address(dualGovernance);

            tiebreakerConfig.config = deployArtifact.deployConfig.tiebreaker;

            //Deploying Tiebreaker
            TiebreakerDeployedContracts.Context memory tiebreakerDeployedContracts =
                ContractsDeployment.deployTiebreaker(tiebreakerConfig, address(this));

            deployArtifact.deployedContracts.tiebreakerCoreCommittee =
                tiebreakerDeployedContracts.tiebreakerCoreCommittee;
            deployArtifact.deployedContracts.tiebreakerSubCommittees =
                tiebreakerDeployedContracts.tiebreakerSubCommittees;
        }

        _step("5. DAO proposes to upgrade the Dual Governance");

        {
            address emergencyActivationCommittee = _timelock.getEmergencyActivationCommittee();
            address emergencyExecutionCommittee = _timelock.getEmergencyExecutionCommittee();
            Timestamp emergencyModeEndsAfter = Timestamps.from(block.timestamp + 365 days);
            Duration emergencyModeDuration = Durations.from(30 days);

            ExternalCallsBuilder.Context memory extendEmergencyProtectionCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 12});

            // 1. Deactivate emergency mode
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.deactivateEmergencyMode, ())
            );

            // 2. Set emergency protection end date
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyProtectionEndDate, (emergencyModeEndsAfter))
            );

            // 3. Set emergency mode duration for a year
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyModeDuration, (emergencyModeDuration))
            );

            // 4. Set emergency protection activation committee
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setEmergencyProtectionActivationCommittee, (emergencyActivationCommittee))
            );

            // 5. Set emergency protection execution committee
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setEmergencyProtectionExecutionCommittee, (emergencyExecutionCommittee))
            );

            // 6. Set Tiebreaker activation timeout
            extendEmergencyProtectionCallsBuilder.addCall(
                address(deployArtifact.deployedContracts.dualGovernance),
                abi.encodeCall(
                    ITiebreaker.setTiebreakerActivationTimeout,
                    deployArtifact.deployConfig.dualGovernance.tiebreakerActivationTimeout
                )
            );

            // 7. Set Tiebreaker committee
            extendEmergencyProtectionCallsBuilder.addCall(
                address(deployArtifact.deployedContracts.dualGovernance),
                abi.encodeCall(
                    ITiebreaker.setTiebreakerCommittee,
                    address(deployArtifact.deployedContracts.tiebreakerCoreCommittee)
                )
            );

            // 8. Add Accounting Oracle as Tiebreaker withdrawal blocker
            extendEmergencyProtectionCallsBuilder.addCall(
                address(deployArtifact.deployedContracts.dualGovernance),
                abi.encodeCall(
                    ITiebreaker.addTiebreakerSealableWithdrawalBlocker,
                    deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[0]
                )
            );

            // 9. Add Validators Exit Bus Oracle as Tiebreaker withdrawal blocker
            extendEmergencyProtectionCallsBuilder.addCall(
                address(deployArtifact.deployedContracts.dualGovernance),
                abi.encodeCall(
                    ITiebreaker.addTiebreakerSealableWithdrawalBlocker,
                    deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[1]
                )
            );

            // 10. Register Aragon Voting as admin proposer
            extendEmergencyProtectionCallsBuilder.addCall(
                address(deployArtifact.deployedContracts.dualGovernance),
                abi.encodeCall(
                    IDualGovernance.registerProposer,
                    (address(lidoUtils.voting), address(deployArtifact.deployedContracts.adminExecutor))
                )
            );

            // 11. Set Aragon Voting as proposals canceller
            extendEmergencyProtectionCallsBuilder.addCall(
                address(deployArtifact.deployedContracts.dualGovernance),
                abi.encodeCall(IDualGovernance.setProposalsCanceller, address(lidoUtils.voting))
            );

            // 12. Set reseal committee
            extendEmergencyProtectionCallsBuilder.addCall(
                address(deployArtifact.deployedContracts.dualGovernance),
                abi.encodeCall(
                    IDualGovernance.setResealCommittee,
                    address(deployArtifact.deployConfig.dualGovernance.resealCommittee)
                )
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

            // Check that emergency protection is extended
            assertEq(_timelock.getEmergencyActivationCommittee(), emergencyActivationCommittee);
            assertEq(_timelock.getEmergencyExecutionCommittee(), emergencyExecutionCommittee);
            assertTrue(_timelock.isEmergencyProtectionEnabled());
            assertFalse(_timelock.isEmergencyModeActive());
        }

        _step(unicode"5. Emergency Committee activates emergency mode if needed");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }
    }

    function testFork_ActivationAndExtensionOfEmergencyProtection() external {
        _step("1. DAO operates as usually");
        {
            ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
            uint256 proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
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
            _lockStETHUpTo(_VETOER, _getFirstSealRageQuitSupport() - PercentsD16.fromBasisPoints(10));
        }

        // Emergency committee activates emergency mode and
        _step("3. Activate emergency mode");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }

        _step("4. Malicious proposal is submitted");
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

            // but the call still not executable
            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(maliciousProposalId);
        }

        _step("4. Emergency committee lifetime is up to end. DAO extends the emergency protection");
        {
            address emergencyActivationCommittee = _timelock.getEmergencyActivationCommittee();
            address emergencyExecutionCommittee = _timelock.getEmergencyExecutionCommittee();
            Timestamp emergencyModeEndsAfter = Timestamps.from(block.timestamp + 365 days);
            Duration emergencyModeDuration = Durations.from(365 days);

            _wait(_getEmergencyProtectionDuration().minusSeconds(5 days));
            assertTrue(_timelock.isEmergencyProtectionEnabled());

            ExternalCallsBuilder.Context memory extendEmergencyProtectionCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 5});

            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.deactivateEmergencyMode, ())
            );
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyProtectionEndDate, (emergencyModeEndsAfter))
            );

            // Set new emergency mode duration for a year
            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyModeDuration, (emergencyModeDuration))
            );

            extendEmergencyProtectionCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setEmergencyProtectionActivationCommittee, (emergencyActivationCommittee))
            );
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

            // Check that emergency protection is extended
            assertEq(_timelock.getEmergencyActivationCommittee(), emergencyActivationCommittee);
            assertEq(_timelock.getEmergencyExecutionCommittee(), emergencyExecutionCommittee);
            assertTrue(_timelock.isEmergencyProtectionEnabled());
            assertFalse(_timelock.isEmergencyModeActive());

            // Check malicious proposal was cancelled
            _assertProposalCancelled(maliciousProposalId);
        }

        _step("5. Emergency Committee activates emergency mode if needed");
        {
            _activateEmergencyMode();
            assertTrue(_timelock.isEmergencyModeActive());
        }
    }
}
