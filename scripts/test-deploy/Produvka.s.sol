// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {DeployScriptBase} from "./DeployScriptBase.sol";

contract Produvka is DeployScriptBase {
    function run() external {
        _loadEnv();
        uint256 step = vm.envUint("STEP");

        console.log("========= Step ", step, " =========");
        IEmergencyProtectedTimelock timelock = IEmergencyProtectedTimelock(_dgContracts.timelock);

        uint256 proposalId = 1;
        RolesVerifier _rolesVerifier;

        // if (step < 1) {
        //     // Verify deployment
        //     // Expect to revert because of temporary emergencyGovernance address in EmergencyProtectedTimelock set
        //     vm.expectRevert("Incorrect emergencyGovernance address in EmergencyProtectedTimelock");
        //     dgContracts.verify(config, lidoAddresses);
        // }

        if (step < 2) {
            console.log("STEP 1 - Activate Emergency Mode");
            // Activate Dual Governance Emergency Mode
            vm.prank(config.EMERGENCY_ACTIVATION_COMMITTEE);
            timelock.activateEmergencyMode();

            console.log("Emergency mode activated");
        }

        if (step < 3) {
            console.log("STEP 2 - Reset Emergency Mode");
            // Check pre-conditions for emergency mode reset
            require(timelock.isEmergencyModeActive() == true, "Emergency mode is not active");

            // Emergency Committee execute emergencyReset()
            vm.prank(config.EMERGENCY_EXECUTION_COMMITTEE);
            timelock.emergencyReset();

            console.log("Emergency mode reset");
        }

        if (step < 4) {
            console.log("STEP 3 - Set DG state");
            require(
                timelock.getGovernance() == _dgContracts.temporaryEmergencyGovernance,
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(timelock.isEmergencyModeActive() == false, "Emergency mode is active");

            // Propose to set Governance, Activation Committee, Execution Committee,  Emergency Mode End Date and Emergency Mode Duration
            ExternalCall[] memory calls;
            uint256 emergencyProtectionEndsAfter = block.timestamp + config.EMERGENCY_PROTECTION_DURATION.toSeconds();
            calls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(timelock.setGovernance.selector, _dgContracts.dualGovernance)
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyGovernance.selector, _dgContracts.emergencyGovernance
                        )
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyProtectionActivationCommittee.selector, config.EMERGENCY_ACTIVATION_COMMITTEE
                        )
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyProtectionExecutionCommittee.selector, config.EMERGENCY_EXECUTION_COMMITTEE
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
                            timelock.setEmergencyModeDuration.selector, config.EMERGENCY_MODE_DURATION
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
                        TimelockedGovernance.submitProposal.selector,
                        calls,
                        "Reset emergency mode and set original DG as governance"
                    )
                );
            }

            vm.prank(config.TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER);
            proposalId = TimelockedGovernance(dgContracts.temporaryEmergencyGovernance).submitProposal(
                calls, "Reset emergency mode and set original DG as governance"
            );

            console.log("Proposal submitted");

            console.log("Proposal ID", proposalId);
        }

        if (step < 5) {
            console.log("STEP 4 - Execute proposal");
            // Schedule and execute the proposal
            vm.warp(block.timestamp + config.AFTER_SUBMIT_DELAY.toSeconds());
            TimelockedGovernance(dgContracts.temporaryEmergencyGovernance).scheduleProposal(proposalId);
            vm.warp(block.timestamp + config.AFTER_SCHEDULE_DELAY.toSeconds());
            timelock.execute(proposalId);

            console.log("Proposal executed");
        }

        if (step < 6) {
            console.log("STEP 5 - Verify DG state");
            // Verify state after proposal execution
            require(
                timelock.getGovernance() == dgContracts.dualGovernance,
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(
                timelock.getEmergencyGovernance() == dgContracts.emergencyGovernance,
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(timelock.isEmergencyModeActive() == false, "Emergency mode is not active");
            require(
                timelock.getEmergencyActivationCommittee() == config.EMERGENCY_ACTIVATION_COMMITTEE,
                "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
            );
            require(
                timelock.getEmergencyExecutionCommittee() == config.EMERGENCY_EXECUTION_COMMITTEE,
                "Incorrect emergencyExecutionCommittee address in EmergencyProtectedTimelock"
            );
            IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
                timelock.getEmergencyProtectionDetails();
            require(
                details.emergencyModeDuration == config.EMERGENCY_MODE_DURATION,
                "Incorrect emergencyModeDuration in EmergencyProtectedTimelock"
            );
            // require(
            //     details.emergencyProtectionEndsAfter.toSeconds() == config.EMERGENCY_PROTECTION_DURATION + block.timestamp,
            //     "Incorrect emergencyProtectionEndsAfter in EmergencyProtectedTimelock"
            // );

            // Activate Dual Governance with DAO Voting

            // Prepare RolesVerifier
            address[] memory ozContracts = new address[](1);
            RolesVerifier.OZRoleInfo[] memory roles = new RolesVerifier.OZRoleInfo[](2);
            address[] memory pauseRoleHolders = new address[](2);
            pauseRoleHolders[0] = address(0x79243345eDbe01A7E42EDfF5900156700d22611c);
            pauseRoleHolders[1] = address(dgContracts.resealManager);
            address[] memory resumeRoleHolders = new address[](1);
            resumeRoleHolders[0] = address(dgContracts.resealManager);

            ozContracts[0] = address(lidoAddresses.withdrawalQueue);

            roles[0] = RolesVerifier.OZRoleInfo({
                role: IWithdrawalQueue(address(lidoAddresses.withdrawalQueue)).PAUSE_ROLE(),
                accounts: pauseRoleHolders
            });
            roles[1] = RolesVerifier.OZRoleInfo({
                role: IWithdrawalQueue(address(lidoAddresses.withdrawalQueue)).RESUME_ROLE(),
                accounts: resumeRoleHolders
            });

            _rolesVerifier = new RolesVerifier(ozContracts, roles);

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
                            address(dgContracts.resealManager)
                        )
                    }),
                    ExternalCall({
                        target: address(_lidoAddresses.withdrawalQueue),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAccessControl.grantRole.selector,
                            IWithdrawalQueue(WITHDRAWAL_QUEUE).RESUME_ROLE(),
                            address(dgContracts.resealManager)
                        )
                    })
                    // Grant agent forward to DG Executor
                    // TODO: Add more role granting calls here
                ]
            );

            // Prepare calls to execute Voting
            ExternalCall[] memory activateCalls;
            activateCalls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(lidoUtils.agent),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAragonForwarder.forward.selector, _encodeExternalCalls(roleGrantingCalls)
                        )
                    }),
                    // Call verifier to verify deployment at the end of the vote
                    // ExternalCall({
                    //     target: address(_verifier),
                    //     value: 0,
                    //     payload: abi.encodeWithSelector(DeployVerifier.verify.selector, _config, _lidoAddresses, _dgContracts)
                    // }),
                    // TODO: Draft of role verification
                    ExternalCall({
                        target: address(_rolesVerifier),
                        value: 0,
                        payload: abi.encodeWithSelector(RolesVerifier.verifyOZRoles.selector)
                    })
                    // DG.submit(revokeAgentForwardRoleFromVoting)
                ]
            );

            // Create and execute vote to activate Dual Governance
            uint256 voteId = lidoUtils.adoptVote("Dual Governance activation vote", _encodeExternalCalls(activateCalls));
            lidoUtils.executeVote(voteId);

            // TODO: Check that voting cant call Agent forward
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
