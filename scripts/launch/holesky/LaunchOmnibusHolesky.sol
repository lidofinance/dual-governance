// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations} from "contracts/types/Duration.sol";
import {IGovernance} from "contracts/interfaces/IGovernance.sol";

import {IWithdrawalVaultProxy} from "../interfaces/IWithdrawalVaultProxy.sol";
import {IRolesValidator} from "../interfaces/IRolesValidator.sol";
import {ITimeConstraints} from "../interfaces/ITimeConstraints.sol";
import {IDGLaunchVerifier} from "../interfaces/IDGLaunchVerifier.sol";
import {IOZ} from "../interfaces/IOZ.sol";
import {IACL} from "../interfaces/IACL.sol";

import {LidoAddressesHolesky} from "./LidoAddressesHolesky.sol";
import {OmnibusBase} from "scripts/utils/OmnibusBase.sol";

import {ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";

/// @title LaunchOmnibusHolesky
/// @notice Script for migrating Lido to Dual Governance on Holesky testnet
///
/// @dev This contract prepares the complete transition of the Lido protocol
/// critical roles and ownerships from direct Aragon Voting control to Dual Governance
/// on the Holesky testnet. It contains 55 items that includes:
///     1. Revoking critical permissions from Voting and transferring permission management to Agent
///     2. Transferring ownerships to Agent over critical protocol contracts
///     4. Validating the roles transfer to ensure proper role configuration
///     5. Submitting the first proposal through the Dual Governance
///     6. Verifying the successful launch of Dual Governance
contract LaunchOmnibusHolesky is OmnibusBase, LidoAddressesHolesky {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    bytes32 private constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 private constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 private constant RUN_SCRIPT_ROLE = keccak256("RUN_SCRIPT_ROLE");
    bytes32 private constant EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    bytes32 private constant STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE");
    bytes32 private constant SET_NODE_OPERATOR_LIMIT_ROLE = keccak256("SET_NODE_OPERATOR_LIMIT_ROLE");
    bytes32 private constant MANAGE_NODE_OPERATOR_ROLE = keccak256("MANAGE_NODE_OPERATOR_ROLE");

    uint256 public constant VOTE_ITEMS_COUNT = 55;
    uint256 public constant DG_PROPOSAL_CALLS_COUNT = 5;

    address public immutable DUAL_GOVERNANCE;
    address public immutable ADMIN_EXECUTOR;
    address public immutable RESEAL_MANAGER;
    address public immutable ROLES_VALIDATOR;
    address public immutable LAUNCH_VERIFIER;
    address public immutable TIME_CONSTRAINTS;

    constructor(
        address dualGovernance,
        address adminExecutor,
        address resealManager,
        address rolesValidator,
        address launchVerifier,
        address timeConstraints
    ) OmnibusBase(VOTING) {
        DUAL_GOVERNANCE = dualGovernance;
        ADMIN_EXECUTOR = adminExecutor;
        RESEAL_MANAGER = resealManager;
        ROLES_VALIDATOR = rolesValidator;
        LAUNCH_VERIFIER = launchVerifier;
        TIME_CONSTRAINTS = timeConstraints;
    }

    function getVoteItems() public view override returns (VoteItem[] memory voteItems) {
        voteItems = new VoteItem[](VOTE_ITEMS_COUNT);
        uint256 index = 0;

        // Lido Permissions Transition
        {
            bytes32 STAKING_CONTROL_ROLE = keccak256("STAKING_CONTROL_ROLE");
            bytes32 STAKING_PAUSE_ROLE = keccak256("STAKING_PAUSE_ROLE");
            bytes32 UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE = keccak256("UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE");

            voteItems[index++] = VoteItem({
                description: "1. Revoke STAKING_CONTROL_ROLE permission from Voting on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, LIDO, STAKING_CONTROL_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "2. Set STAKING_CONTROL_ROLE manager to Agent on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, LIDO, STAKING_CONTROL_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "3. Revoke RESUME_ROLE permission from Voting on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, LIDO, RESUME_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "4. Set RESUME_ROLE manager to Agent on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, LIDO, RESUME_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "5. Revoke PAUSE_ROLE permission from Voting on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, LIDO, PAUSE_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "6. Set PAUSE_ROLE manager to Agent on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, LIDO, PAUSE_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "7. Revoke UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE permission from Voting on Lido",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, LIDO, UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "8. Set UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE manager to Agent on Lido",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, LIDO, UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "9. Revoke STAKING_PAUSE_ROLE permission from Voting on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, LIDO, STAKING_PAUSE_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "10. Set STAKING_PAUSE_ROLE manager to Agent on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, LIDO, STAKING_PAUSE_ROLE)))
            });
        }

        // DAOKernel Permissions Transition
        {
            bytes32 APP_MANAGER_ROLE = keccak256("APP_MANAGER_ROLE");

            voteItems[index++] = VoteItem({
                description: "11. Revoke APP_MANAGER_ROLE permission from Voting on DAOKernel",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, KERNEL, APP_MANAGER_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "12. Set APP_MANAGER_ROLE manager to Agent on DAOKernel",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, KERNEL, APP_MANAGER_ROLE)))
            });
        }

        // TokenManager Permissions Transition
        {
            bytes32 MINT_ROLE = keccak256("MINT_ROLE");
            bytes32 BURN_ROLE = keccak256("BURN_ROLE");
            bytes32 ISSUE_ROLE = keccak256("ISSUE_ROLE");
            bytes32 REVOKE_VESTINGS_ROLE = keccak256("REVOKE_VESTINGS_ROLE");

            voteItems[index++] = VoteItem({
                description: "13. Create MINT_ROLE permission on TokenManager with manager Voting and grant it to Voting",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, MINT_ROLE, VOTING)))
            });

            voteItems[index++] = VoteItem({
                description: "14. Create REVOKE_VESTINGS_ROLE permission on TokenManager with manager Voting and grant it to Voting",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, REVOKE_VESTINGS_ROLE, VOTING))
                )
            });

            voteItems[index++] = VoteItem({
                description: "15. Create BURN_ROLE permission on TokenManager with manager Voting and grant it to Voting",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, BURN_ROLE, VOTING)))
            });

            voteItems[index++] = VoteItem({
                description: "16. Create ISSUE_ROLE permission on TokenManager with manager Voting and grant it to Voting",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, ISSUE_ROLE, VOTING)))
            });
        }

        // Finance Permissions Transition
        {
            bytes32 CHANGE_PERIOD_ROLE = keccak256("CHANGE_PERIOD_ROLE");
            bytes32 CHANGE_BUDGETS_ROLE = keccak256("CHANGE_BUDGETS_ROLE");

            voteItems[index++] = VoteItem({
                description: "17. Create CHANGE_PERIOD_ROLE permission on Finance with manager Voting and grant it to Voting",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, FINANCE, CHANGE_PERIOD_ROLE, VOTING)))
            });

            voteItems[index++] = VoteItem({
                description: "18. Create CHANGE_BUDGETS_ROLE permission on Finance with manager Voting and grant it to Voting",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.createPermission, (VOTING, FINANCE, CHANGE_BUDGETS_ROLE, VOTING))
                )
            });
        }

        // EVMScriptRegistry Permissions Transition
        {
            bytes32 REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");
            bytes32 REGISTRY_ADD_EXECUTOR_ROLE = keccak256("REGISTRY_ADD_EXECUTOR_ROLE");

            voteItems[index++] = VoteItem({
                description: "19. Revoke REGISTRY_MANAGER_ROLE permission from Voting on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "20. Set REGISTRY_MANAGER_ROLE manager to Agent on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "21. Revoke REGISTRY_ADD_EXECUTOR_ROLE permission from Voting on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "22. Set REGISTRY_ADD_EXECUTOR_ROLE manager to Agent on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE))
                )
            });
        }

        // CuratedModule Permissions Transition
        {
            bytes32 MANAGE_SIGNING_KEYS = keccak256("MANAGE_SIGNING_KEYS");

            voteItems[index++] = VoteItem({
                description: "23. Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, STAKING_ROUTER_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "24. Revoke MANAGE_NODE_OPERATOR_ROLE permission from Voting on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "25. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "26. Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "27. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "28. Revoke MANAGE_SIGNING_KEYS permission from Voting on CuratedModule",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, CURATED_MODULE, MANAGE_SIGNING_KEYS)))
            });

            voteItems[index++] = VoteItem({
                description: "29. Set MANAGE_SIGNING_KEYS manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, MANAGE_SIGNING_KEYS))
                )
            });
        }

        // Simple DVT Module Permissions Transition
        {
            voteItems[index++] = VoteItem({
                description: "30. Set STAKING_ROUTER_ROLE manager to Agent on Simple DVT Module",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, SDVT_MODULE, STAKING_ROUTER_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "31. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on Simple DVT Module",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "32. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on Simple DVT Module",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE))
                )
            });
        }

        // ACL Permissions Transition
        {
            bytes32 CREATE_PERMISSIONS_ROLE = keccak256("CREATE_PERMISSIONS_ROLE");

            voteItems[index++] = VoteItem({
                description: "33. Grant CREATE_PERMISSIONS_ROLE permission to Agent on ACL",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (AGENT, ACL, CREATE_PERMISSIONS_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "34. Revoke CREATE_PERMISSIONS_ROLE permission from Voting on ACL",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, ACL, CREATE_PERMISSIONS_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "35. Set CREATE_PERMISSIONS_ROLE manager to Agent on ACL",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, ACL, CREATE_PERMISSIONS_ROLE)))
            });
        }

        // Agent Permissions Transition
        {
            voteItems[index++] = VoteItem({
                description: "36. Grant RUN_SCRIPT_ROLE permission to DualGovernance Executor on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (ADMIN_EXECUTOR, AGENT, RUN_SCRIPT_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "37. Grant RUN_SCRIPT_ROLE permission to DevAgentManager on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (AGENT_MANAGER, AGENT, RUN_SCRIPT_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "38. Set RUN_SCRIPT_ROLE manager to Agent on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, AGENT, RUN_SCRIPT_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "39. Grant EXECUTE_ROLE to DualGovernance Executor on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (ADMIN_EXECUTOR, AGENT, EXECUTE_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "40. Set EXECUTE_ROLE manager to Agent on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, AGENT, EXECUTE_ROLE)))
            });
        }

        // WithdrawalQueue Roles Transition
        {
            voteItems[index++] = VoteItem({
                description: "41. Grant PAUSE_ROLE to ResealManager on WithdrawalQueue",
                call: _forwardCall(AGENT, WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
            });

            voteItems[index++] = VoteItem({
                description: "42. Grant RESUME_ROLE to ResealManager on WithdrawalQueue",
                call: _forwardCall(AGENT, WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
            });
        }

        // VEBO Roles Transition
        {
            voteItems[index++] = VoteItem({
                description: "43. Grant PAUSE_ROLE to ResealManager on VEBO",
                call: _forwardCall(AGENT, VEBO, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
            });

            voteItems[index++] = VoteItem({
                description: "44. Grant RESUME_ROLE to ResealManager on VEBO",
                call: _forwardCall(AGENT, VEBO, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
            });
        }

        // AllowedTokensRegistry Roles Transition
        {
            bytes32 DEFAULT_ADMIN_ROLE = bytes32(0);
            bytes32 ADD_TOKEN_TO_ALLOWED_LIST_ROLE = keccak256("ADD_TOKEN_TO_ALLOWED_LIST_ROLE");
            bytes32 REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE = keccak256("REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE");

            voteItems[index++] = VoteItem({
                description: "45. Grant DEFAULT_ADMIN_ROLE to Voting on AllowedTokensRegistry",
                call: _forwardCall(
                    AGENT, ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (DEFAULT_ADMIN_ROLE, VOTING))
                )
            });

            voteItems[index++] = VoteItem({
                description: "46. Revoke DEFAULT_ADMIN_ROLE from Agent on AllowedTokensRegistry",
                call: _votingCall(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (DEFAULT_ADMIN_ROLE, AGENT)))
            });

            voteItems[index++] = VoteItem({
                description: "47. Grant ADD_TOKEN_TO_ALLOWED_LIST_ROLE to Voting on AllowedTokensRegistry",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (ADD_TOKEN_TO_ALLOWED_LIST_ROLE, VOTING))
                )
            });

            voteItems[index++] = VoteItem({
                description: "48. Revoke ADD_TOKEN_TO_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (ADD_TOKEN_TO_ALLOWED_LIST_ROLE, AGENT))
                )
            });

            voteItems[index++] = VoteItem({
                description: "49. Grant REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE to Voting on AllowedTokensRegistry",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, VOTING))
                )
            });

            voteItems[index++] = VoteItem({
                description: "50. Revoke REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, AGENT))
                )
            });
        }

        // WithdrawalVault Roles Transition
        {
            voteItems[index++] = VoteItem({
                description: "51. Set admin to Agent on WithdrawalVault",
                call: _votingCall(WITHDRAWAL_VAULT, abi.encodeCall(IWithdrawalVaultProxy.proxy_changeAdmin, (AGENT)))
            });
        }

        // Validate transferred roles
        {
            voteItems[index++] = VoteItem({
                description: "52. Validate transferred roles",
                call: _votingCall(ROLES_VALIDATOR, abi.encodeCall(IRolesValidator.validateVotingLaunchPhase, ()))
            });
        }

        // Submit first dual governance proposal
        {
            ExternalCallsBuilder.Context memory dgProposalCallsBuilder =
                ExternalCallsBuilder.create({callsCount: DG_PROPOSAL_CALLS_COUNT});

            // 1. Execution is allowed before Wednesday, 30 April 2025 00:00:00
            dgProposalCallsBuilder.addCall(
                TIME_CONSTRAINTS,
                abi.encodeCall(ITimeConstraints.checkTimeBeforeTimestamp, (Timestamps.from(1745971200)))
            );

            // 2. Execution is allowed since 04:00 to 22:00 UTC
            dgProposalCallsBuilder.addCall(
                TIME_CONSTRAINTS,
                abi.encodeCall(
                    ITimeConstraints.checkTimeWithinDayTime, (Durations.from(4 hours), Durations.from(22 hours))
                )
            );

            // 3. Revoke RUN_SCRIPT_ROLE permission from Voting on Agent
            dgProposalCallsBuilder.addForwardCall(
                AGENT, ACL, abi.encodeCall(IACL.revokePermission, (VOTING, AGENT, RUN_SCRIPT_ROLE))
            );

            // 4. Revoke EXECUTE_ROLE permission from Voting on Agent
            dgProposalCallsBuilder.addForwardCall(
                AGENT, ACL, abi.encodeCall(IACL.revokePermission, (VOTING, AGENT, EXECUTE_ROLE))
            );

            // 5. Validate roles were updated correctly
            dgProposalCallsBuilder.addForwardCall(
                AGENT, ROLES_VALIDATOR, abi.encodeCall(IRolesValidator.validateDGProposalLaunchPhase, ())
            );

            voteItems[index++] = VoteItem({
                description: "53. Submit a proposal to the Dual Governance to revoke RUN_SCRIPT_ROLE and EXECUTE_ROLE from Aragon Voting",
                call: _votingCall(
                    DUAL_GOVERNANCE,
                    abi.encodeCall(
                        IGovernance.submitProposal,
                        (
                            dgProposalCallsBuilder.getResult(),
                            string("Revoke RUN_SCRIPT_ROLE and EXECUTE_ROLE from Aragon Voting")
                        )
                    )
                )
            });
        }

        // Verify state of the DG after launch
        {
            voteItems[index++] = VoteItem({
                description: "54. Verify Dual Governance launch state",
                call: _votingCall(LAUNCH_VERIFIER, abi.encodeCall(IDGLaunchVerifier.verify, ()))
            });
        }

        // Add "expiration date" to the omnibus
        {
            voteItems[index++] = VoteItem({
                description: "55. Introduce an expiration deadline after which the omnibus can no longer be enacted",
                call: _votingCall(
                    TIME_CONSTRAINTS,
                    // 1745971200 is Wednesday, 30 April 2025 00:00:00
                    abi.encodeCall(ITimeConstraints.checkTimeBeforeTimestamp, (Timestamps.from(1745971200)))
                )
            });
        }
    }
}
