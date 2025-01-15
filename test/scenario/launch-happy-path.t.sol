// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
/* solhint-disable no-console */

import {DeployConfig, LidoContracts} from "scripts/deploy/Config.sol";
import {DeployedContracts} from "scripts/deploy/DeployedContractsSet.sol";
import {DeployVerification} from "scripts/deploy/DeployVerification.sol";
import {DeployVerifier} from "scripts/launch/DeployVerifier.sol";

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";

import {IWithdrawalQueue} from "test/utils/interfaces/IWithdrawalQueue.sol";
import {IAragonVoting} from "test/utils/interfaces/IAragonVoting.sol";
import {IAragonAgent, IAragonForwarder} from "test/utils/interfaces/IAragonAgent.sol";
import {IAragonACL} from "test/utils/interfaces/IAragonACL.sol";

import {ExternalCall, ExternalCallHelpers, ScenarioTestBlueprint} from "test/utils/scenario-test-blueprint.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";
import {EvmScriptUtils} from "test/utils/evm-script-utils.sol";

import {ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, DAO_VOTING, DAO_ACL, DAO_AGENT} from "addresses/mainnet-addresses.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {console} from "forge-std/console.sol";

contract DeployHappyPath is ScenarioTestBlueprint {
    using LidoUtils for LidoUtils.Context;

    //Emergency committee
    LidoUtils.Context internal lidoUtils = LidoUtils.mainnet();
    address _ldoHolder = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    DeployVerifier internal _verifier;
    RolesVerifier internal _rolesVerifier;

    function setUp() external {
        _deployDualGovernanceSetup(true, true);
    }

    function testFork_dualGovernance_deployment_and_activation() external {
        // Deploy Dual Governance contracts

        _verifier = new DeployVerifier(_dgDeployConfig, _lidoAddresses);

        // Verify deployment
        _verifier.verify(_contracts, false);

        // Activate Dual Governance Emergency Mode
        vm.prank(_emergencyActivationCommittee);
        _contracts.timelock.activateEmergencyMode();

        assertEq(_contracts.timelock.isEmergencyModeActive(), true, "Emergency mode is not active");

        // Emergency Committee execute emergencyReset()

        vm.prank(_emergencyExecutionCommittee);
        _contracts.timelock.emergencyReset();

        assertEq(
            _contracts.timelock.getGovernance(),
            address(_contracts.temporaryEmergencyGovernance),
            "Incorrect governance address in EmergencyProtectedTimelock"
        );

        // Propose to set Governance, Activation Committee, Execution Committee,  Emergency Mode End Date and Emergency Mode Duration
        ExternalCall[] memory calls;
        uint256 emergencyProtectionEndsAfter =
            block.timestamp + _dgDeployConfig.EMERGENCY_PROTECTION_DURATION.toSeconds();
        calls = ExternalCallHelpers.create(
            [
                ExternalCall({
                    target: address(_contracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _contracts.timelock.setGovernance.selector, address(_contracts.dualGovernance)
                    )
                }),
                ExternalCall({
                    target: address(_contracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _contracts.timelock.setEmergencyGovernance.selector, address(_contracts.emergencyGovernance)
                    )
                }),
                ExternalCall({
                    target: address(_contracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _contracts.timelock.setEmergencyProtectionActivationCommittee.selector, _emergencyActivationCommittee
                    )
                }),
                ExternalCall({
                    target: address(_contracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _contracts.timelock.setEmergencyProtectionExecutionCommittee.selector, _emergencyExecutionCommittee
                    )
                }),
                ExternalCall({
                    target: address(_contracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _contracts.timelock.setEmergencyProtectionEndDate.selector, emergencyProtectionEndsAfter
                    )
                }),
                ExternalCall({
                    target: address(_contracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _contracts.timelock.setEmergencyModeDuration.selector, _dgDeployConfig.EMERGENCY_MODE_DURATION
                    )
                })
            ]
        );
        console.log("Calls to set DG state:");
        console.logBytes(abi.encode(calls));

        console.log("Submit proposal to set DG state calldata");
        console.logBytes(
            abi.encodeWithSelector(
                _contracts.temporaryEmergencyGovernance.submitProposal.selector,
                calls,
                "Reset emergency mode and set original DG as governance"
            )
        );
        vm.prank(_temporaryEmergencyGovernanceProposer);
        uint256 proposalId = _contracts.temporaryEmergencyGovernance.submitProposal(
            calls, "Reset emergency mode and set original DG as governance"
        );

        // Schedule and execute the proposal
        _wait(_dgDeployConfig.AFTER_SUBMIT_DELAY);
        _contracts.temporaryEmergencyGovernance.scheduleProposal(proposalId);
        _wait(_dgDeployConfig.AFTER_SCHEDULE_DELAY);
        _contracts.timelock.execute(proposalId);

        // Verify state after proposal execution
        assertEq(
            _contracts.timelock.getGovernance(),
            address(_contracts.dualGovernance),
            "Incorrect governance address in EmergencyProtectedTimelock"
        );
        assertEq(
            _contracts.timelock.getEmergencyGovernance(),
            address(_contracts.emergencyGovernance),
            "Incorrect governance address in EmergencyProtectedTimelock"
        );
        assertEq(_contracts.timelock.isEmergencyModeActive(), false, "Emergency mode is not active");
        assertEq(
            _contracts.timelock.getEmergencyActivationCommittee(),
            _emergencyActivationCommittee,
            "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
        );
        assertEq(
            _contracts.timelock.getEmergencyExecutionCommittee(),
            _emergencyExecutionCommittee,
            "Incorrect emergencyExecutionCommittee address in EmergencyProtectedTimelock"
        );

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
            _contracts.timelock.getEmergencyProtectionDetails();
        assertEq(
            details.emergencyModeDuration,
            _dgDeployConfig.EMERGENCY_MODE_DURATION,
            "Incorrect emergencyModeDuration in EmergencyProtectedTimelock"
        );
        assertEq(
            details.emergencyModeEndsAfter.toSeconds(),
            0,
            "Incorrect emergencyModeEndsAfter in EmergencyProtectedTimelock"
        );
        assertEq(
            details.emergencyProtectionEndsAfter.toSeconds(),
            emergencyProtectionEndsAfter,
            "Incorrect emergencyProtectionEndsAfter in EmergencyProtectedTimelock"
        );

        // Activate Dual Governance with DAO Voting

        // Prepare RolesVerifier
        address[] memory ozContracts = new address[](1);
        RolesVerifier.OZRoleInfo[] memory roles = new RolesVerifier.OZRoleInfo[](2);
        address[] memory pauseRoleHolders = new address[](2);
        pauseRoleHolders[0] = address(0x79243345eDbe01A7E42EDfF5900156700d22611c);
        pauseRoleHolders[1] = address(_contracts.resealManager);
        address[] memory resumeRoleHolders = new address[](1);
        resumeRoleHolders[0] = address(_contracts.resealManager);

        ozContracts[0] = WITHDRAWAL_QUEUE;

        roles[0] = RolesVerifier.OZRoleInfo({
            role: IWithdrawalQueue(WITHDRAWAL_QUEUE).PAUSE_ROLE(),
            accounts: pauseRoleHolders
        });
        roles[1] = RolesVerifier.OZRoleInfo({
            role: IWithdrawalQueue(WITHDRAWAL_QUEUE).RESUME_ROLE(),
            accounts: resumeRoleHolders
        });

        _rolesVerifier = new RolesVerifier(ozContracts, roles);

        // DAO Voting to activate Dual Governance
        {
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
                            address(_contracts.resealManager)
                        )
                    }),
                    ExternalCall({
                        target: address(_lidoAddresses.withdrawalQueue),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAccessControl.grantRole.selector,
                            IWithdrawalQueue(WITHDRAWAL_QUEUE).RESUME_ROLE(),
                            address(_contracts.resealManager)
                        )
                    }),
                    ExternalCall({
                        target: address(DAO_ACL),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAragonACL.grantPermission.selector,
                            _contracts.adminExecutor,
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

            bytes memory verifyPayload = abi.encodeWithSelector(DeployVerifier.verify.selector, _contracts, true);

            bytes memory verifyOZRolesPayload = abi.encodeWithSelector(RolesVerifier.verifyOZRoles.selector);

            bytes memory submitProposalPayload = abi.encodeWithSelector(
                IGovernance.submitProposal.selector,
                revokeAgentForwardCallDualGovernanceProposal,
                "Revoke Agent forward permission from Voting"
            );

            ExternalCall[] memory activateCalls = ExternalCallHelpers.create(
                [
                    ExternalCall({target: address(DAO_ACL), value: 0, payload: setPermissionPayload}),
                    ExternalCall({target: address(lidoUtils.agent), value: 0, payload: forwardRolePayload}),
                    ExternalCall({target: address(_verifier), value: 0, payload: verifyPayload}),
                    ExternalCall({target: address(_rolesVerifier), value: 0, payload: verifyOZRolesPayload}),
                    ExternalCall({target: address(_contracts.dualGovernance), value: 0, payload: submitProposalPayload})
                ]
            );

            // Create and execute vote to activate Dual Governance
            uint256 voteId = lidoUtils.adoptVote("Dual Governance activation vote", _encodeExternalCalls(activateCalls));
            lidoUtils.executeVote(voteId);

            uint256 expectedProposalId = 2;

            // Schedule and execute the proposal
            _wait(_dgDeployConfig.AFTER_SUBMIT_DELAY);
            _contracts.dualGovernance.scheduleProposal(expectedProposalId);
            _wait(_dgDeployConfig.AFTER_SCHEDULE_DELAY);
            _contracts.timelock.execute(expectedProposalId);

            // Verify that Voting has no permission to forward to Agent
            ExternalCall[] memory someAgentForwardCall;
            someAgentForwardCall = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(DAO_ACL),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAragonACL.revokePermission.selector,
                            _contracts.adminExecutor,
                            DAO_AGENT,
                            IAragonAgent(DAO_AGENT).RUN_SCRIPT_ROLE()
                        )
                    })
                ]
            );

            vm.expectRevert("AGENT_CAN_NOT_FORWARD");
            vm.prank(DAO_VOTING);
            IAragonForwarder(DAO_AGENT).forward(_encodeExternalCalls(someAgentForwardCall));
        }
    }

    function _encodeExternalCalls(ExternalCall[] memory calls) internal pure returns (bytes memory result) {
        result = abi.encodePacked(bytes4(uint32(1)));

        for (uint256 i = 0; i < calls.length; ++i) {
            ExternalCall memory call = calls[i];
            result = abi.encodePacked(result, bytes20(call.target), bytes4(uint32(call.payload.length)), call.payload);
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
