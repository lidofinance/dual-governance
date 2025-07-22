// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, custom-errors, reason-string */

import {console} from "forge-std/Test.sol";

import {DeployDualGovernance} from "../DeployDualGovernance.s.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";
import {Escrow} from "contracts/Escrow.sol";

import {Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";

import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";

import {
    ContractsDeployment,
    DGLaunchConfig,
    DGSetupDeployArtifacts,
    DGSetupDeployConfig,
    DGSetupDeployedContracts,
    TiebreakerDeployedContracts,
    TiebreakerDeployConfig
} from "../../utils/contracts-deployment.sol";
import {DeployVerification} from "../../utils/DeployVerification.sol";
import {DGDeployArtifactLoader} from "../../utils/DGDeployArtifactLoader.sol";

import {LidoUtils} from "test/utils/lido-utils.sol";

import {DGUpgradeOmnibus} from "../DGUpgradeOmnibus.sol";
import {DGUpgradeStateVerifier} from "../DGUpgradeStateVerifier.sol";

contract DGUpgradeAcceptance is DGDeployArtifactLoader {
    using LidoUtils for LidoUtils.Context;

    function run() external {
        DGUpgradeStateVerifier dgUpgradeStateVerifier;
        DGUpgradeOmnibus dgUpgradeOmnibus;

        LidoUtils.Context memory _lidoUtils = LidoUtils.hoodi();
        DGSetupDeployArtifacts.Context memory _deployArtifact = _loadEnv();
        DGSetupDeployArtifacts.Context memory _upgradeArtifact;

        uint256 fromStep = vm.envUint("FROM_STEP");
        // TODO: set right value
        require(fromStep <= 10, "Invalid value of env variable FROM_STEP, should not exceed 10");

        console.log("========= Starting from step ", fromStep, " =========");

        if (fromStep == 0) {
            console.log("STEP 0a: Deploying upgrade contracts");

            // Load origin deploy artifact
            _upgradeArtifact.deployedContracts.adminExecutor = _deployArtifact.deployedContracts.adminExecutor;
            _upgradeArtifact.deployedContracts.timelock = _deployArtifact.deployedContracts.timelock;
            _upgradeArtifact.deployedContracts.emergencyGovernance =
                _deployArtifact.deployedContracts.emergencyGovernance;
            _upgradeArtifact.deployedContracts.resealManager = _deployArtifact.deployedContracts.resealManager;
            _upgradeArtifact.deployedContracts.dualGovernanceConfigProvider =
                _deployArtifact.deployedContracts.dualGovernanceConfigProvider;

            // Deploy new DualGovernance
            DualGovernance.DualGovernanceComponents memory components = DualGovernance.DualGovernanceComponents({
                timelock: _deployArtifact.deployedContracts.timelock,
                resealManager: _deployArtifact.deployedContracts.resealManager,
                configProvider: _deployArtifact.deployedContracts.dualGovernanceConfigProvider
            });

            console.log("Deploying DualGovernance...");

            DualGovernance dualGovernance = new DualGovernance(
                components,
                _deployArtifact.deployConfig.dualGovernance.signallingTokens,
                _deployArtifact.deployConfig.dualGovernance.sanityCheckParams
            );

            // Update deploy artifact
            _upgradeArtifact.deployedContracts.dualGovernance = dualGovernance;
            _upgradeArtifact.deployedContracts.escrowMasterCopy = Escrow(
                payable(address(ISignallingEscrow(dualGovernance.getVetoSignallingEscrow()).ESCROW_MASTER_COPY()))
            );

            console.log("DualGovernance deployed at: %s", address(_upgradeArtifact.deployedContracts.dualGovernance));

            // Deploy new Tiebreaker

            TiebreakerDeployConfig.Context memory tiebreakerConfig;
            tiebreakerConfig.chainId = _deployArtifact.deployConfig.chainId;
            tiebreakerConfig.owner = address(_deployArtifact.deployedContracts.adminExecutor);
            tiebreakerConfig.dualGovernance = address(_upgradeArtifact.deployedContracts.dualGovernance);

            tiebreakerConfig.config = _deployArtifact.deployConfig.tiebreaker;

            console.log("Deploying TiebreakerCoreCommittee...");

            TiebreakerDeployedContracts.Context memory tiebreakerDeployedContracts =
                ContractsDeployment.deployTiebreaker(tiebreakerConfig, address(this));

            _upgradeArtifact.deployedContracts.tiebreakerCoreCommittee =
                tiebreakerDeployedContracts.tiebreakerCoreCommittee;
            _upgradeArtifact.deployedContracts.tiebreakerSubCommittees =
                tiebreakerDeployedContracts.tiebreakerSubCommittees;

            // TODO: deploy ImmutableDualGovernanceConfigProvider for old Dual Governance
        } else {
            console.log("STEP 0b: Loading upgrade contracts addresses from artifact");
            string memory upgradeDeployArtifactFileName = vm.envString("UPGRADE_DEPLOY_ARTIFACT_FILE_NAME");
            console.log("Loading upgrade contracts addresses from artifact");
            _upgradeArtifact = DGSetupDeployArtifacts.load(upgradeDeployArtifactFileName);
        }

        if (fromStep <= 1) {
            console.log("STEP 1a: Deploying omnibus contract");

            dgUpgradeStateVerifier = new DGUpgradeStateVerifier(
                address(_lidoUtils.voting),
                address(_upgradeArtifact.deployedContracts.dualGovernance),
                address(_deployArtifact.deployedContracts.timelock),
                address(_deployArtifact.deployedContracts.adminExecutor),
                address(_upgradeArtifact.deployedContracts.tiebreakerCoreCommittee),
                _deployArtifact.deployConfig.dualGovernance.tiebreakerActivationTimeout,
                _deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[0],
                _deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[1],
                address(_deployArtifact.deployedContracts.resealManager)
            );
            vm.label(address(dgUpgradeStateVerifier), "DG_UPGRADE_STATE_VERIFIER");
            console.log("DGUpgradeStateVerifier deployed successfully at ", address(dgUpgradeStateVerifier));

            dgUpgradeOmnibus = new DGUpgradeOmnibus(
                address(_lidoUtils.voting),
                address(_deployArtifact.deployedContracts.dualGovernance),
                address(_upgradeArtifact.deployedContracts.dualGovernance),
                address(_deployArtifact.deployedContracts.timelock),
                address(_deployArtifact.deployedContracts.adminExecutor),
                address(_upgradeArtifact.deployedContracts.tiebreakerCoreCommittee),
                _deployArtifact.deployConfig.dualGovernance.tiebreakerActivationTimeout,
                _deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[0],
                _deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[1],
                address(_deployArtifact.deployedContracts.resealManager),
                address(dgUpgradeStateVerifier)
            );
            vm.label(address(dgUpgradeOmnibus), "DG_UPGRADE_OMNIBUS");
        } else {
            console.log("STEP 1b: Loading omnibus contract");

            c: set addresses
            dgUpgradeStateVerifier = DGUpgradeStateVerifier(address(0));
            dgUpgradeOmnibus = DGUpgradeOmnibus(address(0));
        }

        {
            // Check omnibus contract state
            assert(address(dgUpgradeOmnibus) != address(0));
            assert(dgUpgradeOmnibus.getVoteItems().length == 1);
            assert(dgUpgradeOmnibus.DUAL_GOVERNANCE() == address(_deployArtifact.deployedContracts.dualGovernance));
            assert(dgUpgradeOmnibus.NEW_DUAL_GOVERNANCE() == address(_upgradeArtifact.deployedContracts.dualGovernance));
            assert(dgUpgradeOmnibus.TIMELOCK() == address(_deployArtifact.deployedContracts.timelock));
            assert(dgUpgradeOmnibus.ADMIN_EXECUTOR() == address(_deployArtifact.deployedContracts.adminExecutor));
            assert(dgUpgradeOmnibus.RESEAL_COMMITTEE() == address(_deployArtifact.deployedContracts.resealManager));
            assert(
                dgUpgradeOmnibus.ACCOUNTING_ORACLE()
                    == _deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[0]
            );
            assert(
                dgUpgradeOmnibus.VALIDATORS_EXIT_BUS_ORACLE()
                    == _deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[1]
            );
            assert(dgUpgradeOmnibus.DG_UPGRADE_STATE_VERIFIER() == address(dgUpgradeStateVerifier));
            assert(
                dgUpgradeOmnibus.TIEBREAKER_CORE_COMMITTEE()
                    == address(_upgradeArtifact.deployedContracts.tiebreakerCoreCommittee)
            );
            assert(
                dgUpgradeOmnibus.TIEBREAKER_ACTIVATION_TIMEOUT()
                    == _deployArtifact.deployConfig.dualGovernance.tiebreakerActivationTimeout
            );
            assert(dgUpgradeOmnibus.VOTING() == address(_lidoUtils.voting));
        }

        if (fromStep <= 2) {
            console.log("STEP 2: Submitting DAO Voting proposal to upgrade Dual Governance");
            uint256 voteId = _lidoUtils.adoptVote("Activate Dual Governance", dgUpgradeOmnibus.getEVMScript());
            console.log("Vote ID", voteId);
        } else {
            console.log("STEP 2: SKIPPED - Dual Governance upgrade vote already submitted");
        }

        if (fromStep <= 3) {
            console.log("STEP 3: Enacting DAO Voting proposal to upgrade Dual Governance");
            uint256 voteId;
            if (fromStep == 3) {
                voteId = vm.envUint("OMNIBUS_VOTE_ID");
                _lidoUtils.supportVoteAndWaitTillDecided(voteId);
            } else {
                voteId = _lidoUtils.getLastVoteId();
            }
            console.log("Enacting vote with ID", voteId);
            _lidoUtils.executeVote(voteId);
        } else {
            console.log("STEP 3: SKIPPED - Dual Governance upgrade vote already executed");
        }

        if (fromStep <= 4) {
            console.log("STEP 4 - Wait for Dual Governance after submit delay");

            _wait(_deployArtifact.deployConfig.timelock.afterSubmitDelay);

            uint256 dgProposalId = _deployArtifact.deployedContracts.timelock.getProposalsCount();
            vm.assertTrue(_deployArtifact.deployedContracts.timelock.canSchedule(dgProposalId));

            console.log("Scheduling DG proposal with ID", dgProposalId);
            _deployArtifact.deployedContracts.dualGovernance.scheduleProposal(dgProposalId);

            ITimelock.ProposalDetails memory proposalDetails =
                _deployArtifact.deployedContracts.timelock.getProposalDetails(dgProposalId);
            assert(proposalDetails.status == ProposalStatus.Scheduled);

            console.log("DG Proposal scheduled: ", dgProposalId);
        } else {
            console.log("STEP 4 SKIPPED - Dual Governance proposal already scheduled");
        }

        if (fromStep <= 5) {
            console.log("STEP 5 - Wait for Dual Governance after schedule delay and execute proposal");

            uint256 dgProposalId = _deployArtifact.deployedContracts.timelock.getProposalsCount();
            _wait(_deployArtifact.deployConfig.timelock.afterScheduleDelay);
            vm.assertTrue(_deployArtifact.deployedContracts.timelock.canExecute(dgProposalId));

            console.log("Executing proposal with ID", dgProposalId);
            _deployArtifact.deployedContracts.timelock.execute(dgProposalId);

            ITimelock.ProposalDetails memory proposalDetails =
                _deployArtifact.deployedContracts.timelock.getProposalDetails(dgProposalId);
            assert(proposalDetails.status == ProposalStatus.Executed);

            console.log("DG proposal executed: ", dgProposalId);
        } else {
            console.log("STEP 5 SKIPPED - Dual Governance proposal already executed");
        }

        {
            console.log("Final verification");

            // run on-chain configuration verifier
            dgUpgradeStateVerifier.verify();
            console.log("DGUpgradeStateVerifier completed successfully");
            DeployVerification.verify(_upgradeArtifact, 3);
            console.log("DeployVerification completed successfully");
        }
    }
}
