// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations} from "contracts/types/Duration.sol";
import {Executor} from "contracts/Executor.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IEscrowBase} from "contracts/interfaces/IEscrowBase.sol";
import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {Escrow} from "contracts/Escrow.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {State} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {IWithdrawalQueue} from "test/utils/interfaces/IWithdrawalQueue.sol";

import {IAragonForwarder} from "test/utils/interfaces/IAragonAgent.sol";

import {DeployConfig, LidoContracts} from "../deploy/Config.sol";
import {DGDeployJSONConfigProvider} from "../deploy/JsonConfig.s.sol";
import {DeployVerification} from "../deploy/DeployVerification.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

contract Produvka is Script {
    using DeployVerification for DeployVerification.DeployedAddresses;

    DeployConfig internal config;
    LidoContracts internal lidoAddresses;

    function run() external {
        string memory chainName = vm.envString("CHAIN");
        string memory configFilePath = vm.envString("DEPLOY_CONFIG_FILE_PATH");
        string memory deployedAddressesFilePath = vm.envString("DEPLOYED_ADDRESSES_FILE_PATH");
        uint256 step = vm.envUint("STEP");

        DGDeployJSONConfigProvider configProvider = new DGDeployJSONConfigProvider(configFilePath);
        config = configProvider.loadAndValidate();
        lidoAddresses = configProvider.getLidoAddresses(chainName);

        DeployVerification.DeployedAddresses memory res = loadDeployedAddresses(deployedAddressesFilePath);

        printAddresses(res);

        console.log("========= Step ", step, " =========");
        IEmergencyProtectedTimelock timelock = IEmergencyProtectedTimelock(res.timelock);

        uint256 proposalId;
        RolesVerifier _rolesVerifier;

        // if (step < 1) {
        //     // Verify deployment
        //     // Expect to revert because of temporary emergencyGovernance address in EmergencyProtectedTimelock set
        //     vm.expectRevert("Incorrect emergencyGovernance address in EmergencyProtectedTimelock");
        //     res.verify(config, lidoAddresses);
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
                timelock.getGovernance() == res.temporaryEmergencyGovernance,
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
                        payload: abi.encodeWithSelector(timelock.setGovernance.selector, address(res.dualGovernance))
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyGovernance.selector, address(res.emergencyGovernance)
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
            proposalId = TimelockedGovernance(res.temporaryEmergencyGovernance).submitProposal(
                calls, "Reset emergency mode and set original DG as governance"
            );

            console.log("Proposal submitted");

            console.log("Proposal ID", proposalId);
        }

        if (step < 5) {
            console.log("STEP 4 - Execute proposal");
            // Schedule and execute the proposal
            vm.warp(block.timestamp + config.AFTER_SUBMIT_DELAY.toSeconds());
            TimelockedGovernance(res.temporaryEmergencyGovernance).scheduleProposal(proposalId);
            vm.warp(block.timestamp + config.AFTER_SCHEDULE_DELAY.toSeconds());
            timelock.execute(proposalId);

            console.log("Proposal executed");
        }

        if (step < 6) {
            console.log("STEP 5 - Verify DG state");
            // Verify state after proposal execution
            require(
                timelock.getGovernance() == res.dualGovernance,
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(
                timelock.getEmergencyGovernance() == res.emergencyGovernance,
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
            require(
                details.emergencyModeEndsAfter.toSeconds() == 0,
                "Incorrect emergencyModeEndsAfter in EmergencyProtectedTimelock"
            );
            // require(
            //     details.emergencyProtectionEndsAfter.toSeconds() == config.EMERGENCY_PROTECTION_DURATION + block.timestamp,
            //     "Incorrect emergencyProtectionEndsAfter in EmergencyProtectedTimelock"
            // );

            // Activate Dual Governance with DAO Voting

            // // Prepare RolesVerifier
            // address[] memory ozContracts = new address[](1);
            // RolesVerifier.OZRoleInfo[] memory roles = new RolesVerifier.OZRoleInfo[](2);
            // address[] memory pauseRoleHolders = new address[](2);
            // pauseRoleHolders[0] = address(0x79243345eDbe01A7E42EDfF5900156700d22611c);
            // pauseRoleHolders[1] = address(res.resealManager);
            // address[] memory resumeRoleHolders = new address[](1);
            // resumeRoleHolders[0] = address(res.resealManager);

            // ozContracts[0] = address(lidoAddresses.withdrawalQueue);

            // roles[0] = RolesVerifier.OZRoleInfo({
            //     role: IWithdrawalQueue(address(lidoAddresses.withdrawalQueue)).PAUSE_ROLE(),
            //     accounts: pauseRoleHolders
            // });
            // roles[1] = RolesVerifier.OZRoleInfo({
            //     role: IWithdrawalQueue(address(lidoAddresses.withdrawalQueue)).RESUME_ROLE(),
            //     accounts: resumeRoleHolders
            // });

            // _rolesVerifier = new RolesVerifier(ozContracts, roles);

            // // Prepare calls to execute by Agent
            // ExternalCall[] memory roleGrantingCalls;
            // roleGrantingCalls = ExternalCallHelpers.create(
            //     [
            //         ExternalCall({
            //             target: address(_lidoAddresses.withdrawalQueue),
            //             value: 0,
            //             payload: abi.encodeWithSelector(
            //                 IAccessControl.grantRole.selector,
            //                 IWithdrawalQueue(WITHDRAWAL_QUEUE).PAUSE_ROLE(),
            //                 address(res.resealManager)
            //             )
            //         }),
            //         ExternalCall({
            //             target: address(_lidoAddresses.withdrawalQueue),
            //             value: 0,
            //             payload: abi.encodeWithSelector(
            //                 IAccessControl.grantRole.selector,
            //                 IWithdrawalQueue(WITHDRAWAL_QUEUE).RESUME_ROLE(),
            //                 address(res.resealManager)
            //             )
            //         })
            //         // TODO: Add more role granting calls here
            //     ]
            // );

            // // Prepare calls to execute Voting
            // ExternalCall[] memory activateCalls;
            // activateCalls = ExternalCallHelpers.create(
            //     [
            //         ExternalCall({
            //             target: address(lidoUtils.agent),
            //             value: 0,
            //             payload: abi.encodeWithSelector(
            //                 IAragonForwarder.forward.selector, _encodeExternalCalls(roleGrantingCalls)
            //             )
            //         }),
            //         // Call verifier to verify deployment at the end of the vote
            //         // ExternalCall({
            //         //     target: address(_verifier),
            //         //     value: 0,
            //         //     payload: abi.encodeWithSelector(DeployVerifier.verify.selector, _config, _lidoAddresses, _dgContracts)
            //         // }),
            //         // TODO: Draft of role verification
            //         ExternalCall({
            //             target: address(_rolesVerifier),
            //             value: 0,
            //             payload: abi.encodeWithSelector(RolesVerifier.verifyOZRoles.selector)
            //         })
            //     ]
            // );

            // // Create and execute vote to activate Dual Governance
            // uint256 voteId = lidoUtils.adoptVote("Dual Governance activation vote", _encodeExternalCalls(activateCalls));
            // lidoUtils.executeVote(voteId);

            // TODO: Check that voting cant call Agent forward
        }
    }

    function printExternalCalls(ExternalCall[] memory calls) internal pure {
        console.log("[");
        for (uint256 i = 0; i < calls.length; i++) {
            string memory hexPayload = toHexString(calls[i].payload);

            if (i < calls.length - 1) {
                console.log("[\"%s\", %s, \"0x%s\"],", calls[i].target, calls[i].value, hexPayload);
            } else {
                console.log("[\"%s\", %s, \"0x%s\"]", calls[i].target, calls[i].value, hexPayload);
            }
        }
        console.log("]");
    }

    function toHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            str[i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[1 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

    function loadDeployedAddresses(string memory deployedAddressesFilePath)
        internal
        view
        returns (DeployVerification.DeployedAddresses memory)
    {
        string memory deployedAddressesJson = loadDeployedAddressesFile(deployedAddressesFilePath);

        return DeployVerification.DeployedAddresses({
            adminExecutor: payable(stdJson.readAddress(deployedAddressesJson, ".ADMIN_EXECUTOR")),
            timelock: stdJson.readAddress(deployedAddressesJson, ".TIMELOCK"),
            emergencyGovernance: stdJson.readAddress(deployedAddressesJson, ".EMERGENCY_GOVERNANCE"),
            resealManager: stdJson.readAddress(deployedAddressesJson, ".RESEAL_MANAGER"),
            dualGovernance: stdJson.readAddress(deployedAddressesJson, ".DUAL_GOVERNANCE"),
            tiebreakerCoreCommittee: stdJson.readAddress(deployedAddressesJson, ".TIEBREAKER_CORE_COMMITTEE"),
            tiebreakerSubCommittees: stdJson.readAddressArray(deployedAddressesJson, ".TIEBREAKER_SUB_COMMITTEES"),
            temporaryEmergencyGovernance: stdJson.readAddress(deployedAddressesJson, ".TEMPORARY_EMERGENCY_GOVERNANCE")
        });
    }

    function printAddresses(DeployVerification.DeployedAddresses memory res) internal pure {
        console.log("Using the following DG contracts addresses");
        console.log("DualGovernance address", res.dualGovernance);
        console.log("ResealManager address", res.resealManager);
        console.log("TiebreakerCoreCommittee address", res.tiebreakerCoreCommittee);

        for (uint256 i = 0; i < res.tiebreakerSubCommittees.length; ++i) {
            console.log("TiebreakerSubCommittee #", i, "address", res.tiebreakerSubCommittees[i]);
        }

        console.log("AdminExecutor address", res.adminExecutor);
        console.log("EmergencyProtectedTimelock address", res.timelock);
        console.log("EmergencyGovernance address", res.emergencyGovernance);
    }

    function loadDeployedAddressesFile(string memory deployedAddressesFilePath)
        internal
        view
        returns (string memory deployedAddressesJson)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", deployedAddressesFilePath);
        deployedAddressesJson = vm.readFile(path);
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
