// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
/* solhint-disable no-console */

import {DeployConfig, LidoContracts} from "scripts/deploy/Config.sol";
import {DGContractsDeployment, DeployedContracts} from "scripts/deploy/ContractsDeployment.sol";
import {DeployVerification} from "scripts/deploy/DeployVerification.sol";

import {ExternalCall, ExternalCallHelpers, ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "test/utils/interfaces/IWithdrawalQueue.sol";
import {IAragonVoting} from "test/utils/interfaces/IAragonVoting.sol";
import {IAragonForwarder} from "test/utils/interfaces/IAragonAgent.sol";

import {ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, DAO_VOTING} from "addresses/mainnet-addresses.sol";

import {LidoUtils} from "test/utils/lido-utils.sol";
import {EvmScriptUtils} from "test/utils/evm-script-utils.sol";

import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {console} from "hardhat/console.sol";

contract DeployHappyPath is ScenarioTestBlueprint {
    using LidoUtils for LidoUtils.Context;

    //Emergency committee
    address internal _committee = makeAddr("committee");
    address[] internal _emptyMembers = new address[](0);
    address[] internal _tiebreakerSubCommitteeMembers = new address[](1);
    uint256[] internal _tiebreakerSubCommitteeQuorums = new uint256[](1);
    DeployConfig internal _config;
    DeployedContracts _dgContracts;
    LidoContracts internal _lidoAddresses;
    DeployVerifier internal _verifier;
    RolesVerifier internal _rolesVerifier;
    DeployVerification.DeployedAddresses internal _deployedAddresses;
    address _emergencyActivationCommitteeMultisig = makeAddr("emergencyActivationCommittee");
    address _emergencyExecutionCommitteeMultisig = makeAddr("emergencyExecutionCommittee");
    address _temporaryEmergencyGovernanceProposer = makeAddr("temporaryEmergencyGovernanceProposer");

    LidoUtils.Context internal lidoUtils = LidoUtils.mainnet();
    address _ldoHolder = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);

    function setUp() external {
        _tiebreakerSubCommitteeMembers[0] = makeAddr("tiebreakerSubCommitteeMember");
        _tiebreakerSubCommitteeQuorums[0] = 1;

        _config = DeployConfig({
            MIN_EXECUTION_DELAY: Durations.from(100),
            AFTER_SUBMIT_DELAY: Durations.from(60),
            MAX_AFTER_SUBMIT_DELAY: Durations.from(120),
            AFTER_SCHEDULE_DELAY: Durations.from(60),
            MAX_AFTER_SCHEDULE_DELAY: Durations.from(120),
            EMERGENCY_MODE_DURATION: Durations.from(60),
            MAX_EMERGENCY_MODE_DURATION: Durations.from(600),
            EMERGENCY_PROTECTION_DURATION: Durations.from(600),
            MAX_EMERGENCY_PROTECTION_DURATION: Durations.from(600),
            EMERGENCY_ACTIVATION_COMMITTEE: _emergencyActivationCommitteeMultisig,
            EMERGENCY_EXECUTION_COMMITTEE: _emergencyExecutionCommitteeMultisig,
            TIEBREAKER_CORE_QUORUM: 1,
            TIEBREAKER_EXECUTION_DELAY: Durations.from(100),
            TIEBREAKER_SUB_COMMITTEES_COUNT: 1,
            TIEBREAKER_SUB_COMMITTEE_1_MEMBERS: _tiebreakerSubCommitteeMembers,
            TIEBREAKER_SUB_COMMITTEE_2_MEMBERS: _emptyMembers,
            TIEBREAKER_SUB_COMMITTEE_3_MEMBERS: _emptyMembers,
            TIEBREAKER_SUB_COMMITTEE_4_MEMBERS: _emptyMembers,
            TIEBREAKER_SUB_COMMITTEE_5_MEMBERS: _emptyMembers,
            TIEBREAKER_SUB_COMMITTEE_6_MEMBERS: _emptyMembers,
            TIEBREAKER_SUB_COMMITTEE_7_MEMBERS: _emptyMembers,
            TIEBREAKER_SUB_COMMITTEE_8_MEMBERS: _emptyMembers,
            TIEBREAKER_SUB_COMMITTEE_9_MEMBERS: _emptyMembers,
            TIEBREAKER_SUB_COMMITTEE_10_MEMBERS: _emptyMembers,
            TIEBREAKER_SUB_COMMITTEES_QUORUMS: _tiebreakerSubCommitteeQuorums,
            RESEAL_COMMITTEE: _committee,
            MIN_WITHDRAWALS_BATCH_SIZE: 1,
            MIN_TIEBREAKER_ACTIVATION_TIMEOUT: Durations.from(60),
            TIEBREAKER_ACTIVATION_TIMEOUT: Durations.from(600),
            MAX_TIEBREAKER_ACTIVATION_TIMEOUT: Durations.from(36000),
            MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT: 120,
            FIRST_SEAL_RAGE_QUIT_SUPPORT: PercentsD16.fromBasisPoints(120),
            SECOND_SEAL_RAGE_QUIT_SUPPORT: PercentsD16.fromBasisPoints(220),
            MIN_ASSETS_LOCK_DURATION: Durations.from(60),
            MAX_MIN_ASSETS_LOCK_DURATION: Durations.from(3600),
            VETO_SIGNALLING_MIN_DURATION: Durations.from(60),
            VETO_SIGNALLING_MAX_DURATION: Durations.from(3600),
            VETO_SIGNALLING_MIN_ACTIVE_DURATION: Durations.from(60),
            VETO_SIGNALLING_DEACTIVATION_MAX_DURATION: Durations.from(3600),
            VETO_COOLDOWN_DURATION: Durations.from(60),
            RAGE_QUIT_EXTENSION_PERIOD_DURATION: Durations.from(60),
            RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY: Durations.from(60),
            RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY: Durations.from(3600),
            RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH: Durations.from(60),
            // Address of multisig that will be used for temporary governance
            // in post-deployment phase
            TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER: _temporaryEmergencyGovernanceProposer
        });

        _lidoAddresses = LidoContracts({
            chainId: 1,
            stETH: IStETH(ST_ETH),
            wstETH: IWstETH(WST_ETH),
            withdrawalQueue: IWithdrawalQueue(WITHDRAWAL_QUEUE),
            voting: DAO_VOTING
        });

        _verifier = new DeployVerifier();
    }

    function testFork_dualGovernance_deployment_and_activation() external {
        // Deploy Dual Governance contracts

        _dgContracts = DGContractsDeployment.deployDualGovernanceSetup(_config, _lidoAddresses, address(this));

        // Verify deployment
        _verifier.verify(_config, _lidoAddresses, _dgContracts, false);

        // Activate Dual Governance Emergency Mode
        vm.prank(_emergencyActivationCommitteeMultisig);
        _dgContracts.timelock.activateEmergencyMode();

        assertEq(_dgContracts.timelock.isEmergencyModeActive(), true, "Emergency mode is not active");

        // Emergency Committee execute emergencyReset()

        vm.prank(_emergencyExecutionCommitteeMultisig);
        _dgContracts.timelock.emergencyReset();

        assertEq(
            _dgContracts.timelock.getGovernance(),
            address(_dgContracts.temporaryEmergencyGovernance),
            "Incorrect governance address in EmergencyProtectedTimelock"
        );

        // Propose to set Governance, Activation Committee, Execution Committee,  Emergency Mode End Date and Emergency Mode Duration
        ExternalCall[] memory calls;
        uint256 emergencyProtectionEndsAfter = block.timestamp + _config.EMERGENCY_PROTECTION_DURATION.toSeconds();
        calls = ExternalCallHelpers.create(
            [
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _dgContracts.timelock.setGovernance.selector, address(_dgContracts.dualGovernance)
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _dgContracts.timelock.setEmergencyGovernance.selector, address(_dgContracts.emergencyGovernance)
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _dgContracts.timelock.setEmergencyProtectionActivationCommittee.selector,
                        _emergencyActivationCommitteeMultisig
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _dgContracts.timelock.setEmergencyProtectionExecutionCommittee.selector,
                        _emergencyExecutionCommitteeMultisig
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _dgContracts.timelock.setEmergencyProtectionEndDate.selector, emergencyProtectionEndsAfter
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        _dgContracts.timelock.setEmergencyModeDuration.selector, _config.EMERGENCY_MODE_DURATION
                    )
                })
            ]
        );
        console.log("Calls to set DG state:");
        console.logBytes(abi.encode(calls));

        console.log("Submit proposal to set DG state calldata");
        console.logBytes(
            abi.encodeWithSelector(
                _dgContracts.temporaryEmergencyGovernance.submitProposal.selector,
                calls,
                "Reset emergency mode and set original DG as governance"
            )
        );
        vm.prank(_temporaryEmergencyGovernanceProposer);
        uint256 proposalId = _dgContracts.temporaryEmergencyGovernance.submitProposal(
            calls, "Reset emergency mode and set original DG as governance"
        );

        // Schedule and execute the proposal
        _wait(_config.AFTER_SUBMIT_DELAY);
        _dgContracts.temporaryEmergencyGovernance.scheduleProposal(proposalId);
        _wait(_config.AFTER_SCHEDULE_DELAY);
        _dgContracts.timelock.execute(proposalId);

        // Verify state after proposal execution
        assertEq(
            _dgContracts.timelock.getGovernance(),
            address(_dgContracts.dualGovernance),
            "Incorrect governance address in EmergencyProtectedTimelock"
        );
        assertEq(
            _dgContracts.timelock.getEmergencyGovernance(),
            address(_dgContracts.emergencyGovernance),
            "Incorrect governance address in EmergencyProtectedTimelock"
        );
        assertEq(_dgContracts.timelock.isEmergencyModeActive(), false, "Emergency mode is not active");
        assertEq(
            _dgContracts.timelock.getEmergencyActivationCommittee(),
            _emergencyActivationCommitteeMultisig,
            "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
        );
        assertEq(
            _dgContracts.timelock.getEmergencyExecutionCommittee(),
            _emergencyExecutionCommitteeMultisig,
            "Incorrect emergencyExecutionCommittee address in EmergencyProtectedTimelock"
        );

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
            _dgContracts.timelock.getEmergencyProtectionDetails();
        assertEq(
            details.emergencyModeDuration,
            _config.EMERGENCY_MODE_DURATION,
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
        pauseRoleHolders[1] = address(_dgContracts.resealManager);
        address[] memory resumeRoleHolders = new address[](1);
        resumeRoleHolders[0] = address(_dgContracts.resealManager);

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
                })
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
                    payload: abi.encodeWithSelector(IAragonForwarder.forward.selector, _encodeExternalCalls(roleGrantingCalls))
                }),
                // Call verifier to verify deployment at the end of the vote
                ExternalCall({
                    target: address(_verifier),
                    value: 0,
                    payload: abi.encodeWithSelector(DeployVerifier.verify.selector, _config, _lidoAddresses, _dgContracts, true)
                }),
                // TODO: Draft of role verification
                ExternalCall({
                    target: address(_rolesVerifier),
                    value: 0,
                    payload: abi.encodeWithSelector(RolesVerifier.verifyOZRoles.selector)
                })
            ]
        );

        // Create and execute vote to activate Dual Governance
        uint256 voteId = lidoUtils.adoptVote("Dual Governance activation vote", _encodeExternalCalls(activateCalls));
        lidoUtils.executeVote(voteId);

        // TODO: Check that voting cant call Agent forward
    }

    function _encodeExternalCalls(ExternalCall[] memory calls) internal pure returns (bytes memory result) {
        result = abi.encodePacked(bytes4(uint32(1)));

        for (uint256 i = 0; i < calls.length; ++i) {
            ExternalCall memory call = calls[i];
            result = abi.encodePacked(result, bytes20(call.target), bytes4(uint32(call.payload.length)), call.payload);
        }
    }
}

contract DeployVerifier {
    using DeployVerification for DeployVerification.DeployedAddresses;

    function verify(
        DeployConfig memory config,
        LidoContracts memory lidoAddresses,
        DeployedContracts memory _dgContracts,
        bool onchainVotingCheck
    ) external view {
        address[] memory _tiebreakerSubCommittees = new address[](_dgContracts.tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < _dgContracts.tiebreakerSubCommittees.length; ++i) {
            _tiebreakerSubCommittees[i] = address(_dgContracts.tiebreakerSubCommittees[i]);
        }

        DeployVerification.DeployedAddresses memory dgDeployedAddresses = DeployVerification.DeployedAddresses({
            adminExecutor: payable(address(_dgContracts.adminExecutor)),
            timelock: address(_dgContracts.timelock),
            emergencyGovernance: address(_dgContracts.emergencyGovernance),
            resealManager: address(_dgContracts.resealManager),
            dualGovernance: address(_dgContracts.dualGovernance),
            tiebreakerCoreCommittee: address(_dgContracts.tiebreakerCoreCommittee),
            tiebreakerSubCommittees: _tiebreakerSubCommittees,
            temporaryEmergencyGovernance: address(_dgContracts.temporaryEmergencyGovernance)
        });

        dgDeployedAddresses.verify(config, lidoAddresses, onchainVotingCheck);
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
