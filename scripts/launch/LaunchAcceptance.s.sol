// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/Test.sol";

import {DeployScriptBase} from "./DeployScriptBase.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAragonForwarder} from "test/utils/interfaces/IAragonForwarder.sol";
import {IWithdrawalQueue} from "test/utils/interfaces/IWithdrawalQueue.sol";
import {IAragonACL} from "test/utils/interfaces/IAragonACL.sol";
import {IAragonAgent} from "test/utils/interfaces/IAragonAgent.sol";
import {IGovernance} from "contracts/interfaces/IDualGovernance.sol";

import {DeployVerifier} from "./DeployVerifier.sol";

import {WITHDRAWAL_QUEUE, DAO_AGENT, DAO_VOTING, DAO_ACL} from "addresses/mainnet-addresses.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

contract LaunchAcceptance is DeployScriptBase {
    using LidoUtils for LidoUtils.Context;

    LidoUtils.Context internal lidoUtils = LidoUtils.mainnet();

    function run() external {
        _loadEnv();

        uint256 step = vm.envUint("STEP");

        console.log("========= Step ", step, " =========");

        IEmergencyProtectedTimelock timelock = _dgContracts.timelock;

        uint256 proposalId = 1;
        RolesVerifier _rolesVerifier;

        if (step < 1) {
            // Verify deployment of all contracts before proceeding
            _deployVerifier.verify(_dgContracts, false);
        } else {
            console.log("STEP 0 SKIPPED - All contracts are deployed");
        }

        if (step < 2) {
            console.log("STEP 1 - Activate Emergency Mode");
            // Activate Dual Governance Emergency Mode
            vm.prank(_config.EMERGENCY_ACTIVATION_COMMITTEE);
            timelock.activateEmergencyMode();

            console.log("Emergency mode activated");
        } else {
            console.log("STEP 1 SKIPPED - Emergency Mode already activated");
        }

        if (step < 3) {
            console.log("STEP 2 - Reset Emergency Mode");
            // Check pre-conditions for emergency mode reset
            require(timelock.isEmergencyModeActive() == true, "Emergency mode is not active");

            // Emergency Committee execute emergencyReset()
            vm.prank(_config.EMERGENCY_EXECUTION_COMMITTEE);
            timelock.emergencyReset();

            console.log("Emergency mode reset");
        } else {
            console.log("STEP 2 SKIPPED - Emergency Mode already reset");
        }

        if (step < 4) {
            console.log("STEP 3 - Set DG state");
            require(
                timelock.getGovernance() == address(_dgContracts.temporaryEmergencyGovernance),
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(timelock.isEmergencyModeActive() == false, "Emergency mode is active");

            // Propose to set Governance, Activation Committee, Execution Committee,  Emergency Mode End Date and Emergency Mode Duration
            ExternalCall[] memory calls;
            uint256 emergencyProtectionEndsAfter = block.timestamp + _config.EMERGENCY_PROTECTION_DURATION.toSeconds();
            calls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(timelock.setGovernance.selector, address(_dgContracts.dualGovernance))
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyGovernance.selector, address(_dgContracts.emergencyGovernance)
                        )
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyProtectionActivationCommittee.selector, _config.EMERGENCY_ACTIVATION_COMMITTEE
                        )
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyProtectionExecutionCommittee.selector, _config.EMERGENCY_EXECUTION_COMMITTEE
                        )
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyProtectionEndDate.selector, emergencyProtectionEndsAfter
                        )
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyModeDuration.selector, _config.EMERGENCY_MODE_DURATION
                        )
                    })
                ]
            );

            if (step == 3) {
                console.log("Calls to set DG state:");
                console.logBytes(abi.encode(calls));

                console.log("Calls encoded:");
                console.logBytes(abi.encode(calls));

                console.log("Submit proposal to set DG state calldata");
                console.logBytes(
                    abi.encodeWithSelector(
                        IGovernance.submitProposal.selector,
                        calls,
                        "Reset emergency mode and set original DG as governance"
                    )
                );
            }

            vm.prank(_config.TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER);
            proposalId = _dgContracts.temporaryEmergencyGovernance.submitProposal(
                calls, "Reset emergency mode and set original DG as governance"
            );

            console.log("Proposal submitted");

            console.log("Proposal ID", proposalId);
        } else {
            console.log("STEP 3 SKIPPED - DG state proposal already submitted");
        }

        if (step < 5) {
            console.log("STEP 4 - Execute proposal");
            // Schedule and execute the proposal
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY.toSeconds());
            _dgContracts.temporaryEmergencyGovernance.scheduleProposal(proposalId);
            vm.warp(block.timestamp + _config.AFTER_SCHEDULE_DELAY.toSeconds());
            timelock.execute(proposalId);

            console.log("Proposal executed");
        } else {
            console.log("STEP 4 SKIPPED - Proposal to set DG state already executed");
        }

        if (step < 6) {
            console.log("STEP 5 - Verify DG state");
            // Verify state after proposal execution
            require(
                timelock.getGovernance() == address(_dgContracts.dualGovernance),
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(
                timelock.getEmergencyGovernance() == address(_dgContracts.emergencyGovernance),
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(timelock.isEmergencyModeActive() == false, "Emergency mode is not active");
            require(
                timelock.getEmergencyActivationCommittee() == _config.EMERGENCY_ACTIVATION_COMMITTEE,
                "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
            );
            require(
                timelock.getEmergencyExecutionCommittee() == _config.EMERGENCY_EXECUTION_COMMITTEE,
                "Incorrect emergencyExecutionCommittee address in EmergencyProtectedTimelock"
            );
            IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
                timelock.getEmergencyProtectionDetails();
            require(
                details.emergencyModeDuration == _config.EMERGENCY_MODE_DURATION,
                "Incorrect emergencyModeDuration in EmergencyProtectedTimelock"
            );
            // require(
            //     details.emergencyProtectionEndsAfter.toSeconds() == _config.EMERGENCY_PROTECTION_DURATION + block.timestamp,
            //     "Incorrect emergencyProtectionEndsAfter in EmergencyProtectedTimelock"
            // );

            // Activate Dual Governance with DAO Voting

            // Verify deployment
            _deployVerifier.verify(_dgContracts, true);
        } else {
            console.log("STEP 5 SKIPPED - DG state already verified");
        }

        if (step < 7) {
            console.log("STEP 6 - Submitting DAO Voting proposal to activate Dual Governance");

            // Prepare RolesVerifier
            // TODO: Sync with the actual voting script roles checker
            address[] memory ozContracts = new address[](1);
            RolesVerifier.OZRoleInfo[] memory roles = new RolesVerifier.OZRoleInfo[](2);
            address[] memory pauseRoleHolders = new address[](2);
            pauseRoleHolders[0] = address(0x79243345eDbe01A7E42EDfF5900156700d22611c);
            pauseRoleHolders[1] = address(_dgContracts.resealManager);
            address[] memory resumeRoleHolders = new address[](1);
            resumeRoleHolders[0] = address(_dgContracts.resealManager);

            ozContracts[0] = address(_lidoAddresses.withdrawalQueue);

            roles[0] = RolesVerifier.OZRoleInfo({
                role: IWithdrawalQueue(address(_lidoAddresses.withdrawalQueue)).PAUSE_ROLE(),
                accounts: pauseRoleHolders
            });
            roles[1] = RolesVerifier.OZRoleInfo({
                role: IWithdrawalQueue(address(_lidoAddresses.withdrawalQueue)).RESUME_ROLE(),
                accounts: resumeRoleHolders
            });

            _rolesVerifier = new RolesVerifier(ozContracts, roles);

            // DAO Voting to activate Dual Governance
            // Prepare calls to execute by Agent
            ExternalCall[] memory roleGrantingCalls;
            roleGrantingCalls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(_lidoAddresses.withdrawalQueue),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAccessControl.grantRole.selector,
                            IWithdrawalQueue(WITHDRAWAL_QUEUE).PAUSE_ROLE(),
                            address(_dgContracts.resealManager)
                        )
                    }),
                    ExternalCall({
                        target: address(_lidoAddresses.withdrawalQueue),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAccessControl.grantRole.selector,
                            IWithdrawalQueue(WITHDRAWAL_QUEUE).RESUME_ROLE(),
                            address(_dgContracts.resealManager)
                        )
                    }),
                    ExternalCall({
                        target: address(DAO_ACL),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAragonACL.grantPermission.selector,
                            address(_dgContracts.adminExecutor),
                            DAO_AGENT,
                            IAragonAgent(DAO_AGENT).RUN_SCRIPT_ROLE()
                        )
                    })
                ]
            );

            // Propose to revoke Agent forward permission from Voting
            ExternalCall[] memory revokeAgentForwardCall;
            revokeAgentForwardCall = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(DAO_ACL),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAragonACL.revokePermission.selector,
                            DAO_VOTING,
                            DAO_AGENT,
                            IAragonAgent(DAO_AGENT).RUN_SCRIPT_ROLE()
                        )
                    })
                ]
            );

            ExternalCall[] memory revokeAgentForwardCallDualGovernanceProposal;
            revokeAgentForwardCallDualGovernanceProposal = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(lidoUtils.agent),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAragonForwarder.forward.selector, _encodeExternalCalls(revokeAgentForwardCall)
                        )
                    })
                ]
            );

            // Prepare calls to execute Voting
            bytes memory setPermissionPayload = abi.encodeWithSelector(
                IAragonACL.setPermissionManager.selector,
                DAO_AGENT,
                DAO_AGENT,
                IAragonAgent(DAO_AGENT).RUN_SCRIPT_ROLE()
            );

            bytes memory forwardRolePayload =
                abi.encodeWithSelector(IAragonForwarder.forward.selector, _encodeExternalCalls(roleGrantingCalls));

            bytes memory verifyPayload = abi.encodeWithSelector(DeployVerifier.verify.selector, _dgContracts, true);

            bytes memory verifyOZRolesPayload = abi.encodeWithSelector(RolesVerifier.verifyOZRoles.selector);

            bytes memory submitProposalPayload = abi.encodeWithSelector(
                IGovernance.submitProposal.selector,
                revokeAgentForwardCallDualGovernanceProposal,
                "Revoke Agent forward permission from Voting"
            );

            ExternalCall[] memory activateCalls = ExternalCallHelpers.create(
                [
                    ExternalCall({target: address(DAO_ACL), value: 0, payload: setPermissionPayload}),
                    ExternalCall({target: address(DAO_AGENT), value: 0, payload: forwardRolePayload}),
                    ExternalCall({target: address(_deployVerifier), value: 0, payload: verifyPayload}),
                    // TODO: set real RolesVerifier contract address
                    // ExternalCall({target: address(_rolesVerifier), value: 0, payload: verifyOZRolesPayload}),
                    ExternalCall({target: address(_dgContracts.dualGovernance), value: 0, payload: submitProposalPayload})
                ]
            );
            uint256 voteId = lidoUtils.adoptVote("Dual Governance activation vote", _encodeExternalCalls(activateCalls));
            console.log("Vote ID", voteId);
        } else {
            console.log("STEP 6 SKIPPED - Dual Governance activation vote already submitted");
        }

        if (step < 8) {
            uint256 voteId = 0;
            require(voteId != 0);
            console.log("STEP 7 - Enacting DAO Voting proposal to activate Dual Governance");
            lidoUtils.executeVote(voteId);
        } else {
            console.log("STEP 7 SKIPPED - Dual Governance activation vote already executed");
        }

        if (step < 9) {
            console.log("STEP 8 - Wait for Dual Governance after submit delay and envacting proposal");

            uint256 expectedProposalId = 2;

            // Schedule and execute the proposal
            _wait(_config.AFTER_SUBMIT_DELAY);
            _dgContracts.dualGovernance.scheduleProposal(expectedProposalId);
            _wait(_config.AFTER_SCHEDULE_DELAY);
            timelock.execute(expectedProposalId);
        } else {
            console.log("STEP 8 SKIPPED - Dual Governance proposal already executed");
        }

        if (step < 10) {
            console.log("STEP 9 - Verify DAO has no agent forward permission from Voting");
            // Verify that Voting has no permission to forward to Agent
            ExternalCall[] memory someAgentForwardCall;
            someAgentForwardCall = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(DAO_ACL),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAragonACL.revokePermission.selector,
                            address(_dgContracts.adminExecutor),
                            DAO_AGENT,
                            IAragonAgent(DAO_AGENT).RUN_SCRIPT_ROLE()
                        )
                    })
                ]
            );

            vm.expectRevert("AGENT_CAN_NOT_FORWARD");
            vm.prank(DAO_VOTING);
            IAragonForwarder(DAO_AGENT).forward(_encodeExternalCalls(someAgentForwardCall));
        } else {
            console.log("STEP 9 SKIPPED - Agent forward permission already revoked");
        }
    }
}

contract RolesVerifier {
    struct OZRoleInfo {
        bytes32 role;
        address[] accounts;
    }

    mapping(address => OZRoleInfo[]) public ozContractRoles;
    address[] private _ozContracts;

    constructor(address[] memory ozContracts, OZRoleInfo[] memory roles) {
        _ozContracts = ozContracts;

        for (uint256 i = 0; i < ozContracts.length; ++i) {
            for (uint256 r = 0; r < roles.length; ++r) {
                ozContractRoles[ozContracts[i]].push();
                uint256 lastIndex = ozContractRoles[ozContracts[i]].length - 1;
                ozContractRoles[ozContracts[i]][lastIndex].role = roles[r].role;
                address[] memory accounts = roles[r].accounts;
                for (uint256 a = 0; a < accounts.length; ++a) {
                    ozContractRoles[ozContracts[i]][lastIndex].accounts.push(accounts[a]);
                }
            }
        }
    }

    function verifyOZRoles() external view {
        for (uint256 i = 0; i < _ozContracts.length; ++i) {
            OZRoleInfo[] storage roles = ozContractRoles[_ozContracts[i]];
            for (uint256 j = 0; j < roles.length; ++j) {
                AccessControlEnumerable accessControl = AccessControlEnumerable(_ozContracts[i]);
                assert(accessControl.getRoleMemberCount(roles[j].role) == roles[j].accounts.length);
                for (uint256 k = 0; k < roles[j].accounts.length; ++k) {
                    assert(accessControl.hasRole(roles[j].role, roles[j].accounts[k]) == true);
                }
            }
        }
    }
}
