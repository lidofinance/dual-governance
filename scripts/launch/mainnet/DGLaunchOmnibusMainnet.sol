// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamp} from "contracts/types/Timestamp.sol";
import {Duration} from "contracts/types/Duration.sol";
import {IGovernance} from "contracts/interfaces/IGovernance.sol";

import {IWithdrawalVaultProxy} from "../interfaces/IWithdrawalVaultProxy.sol";
import {IRolesValidator} from "../interfaces/IRolesValidator.sol";
import {ITimeConstraints} from "../interfaces/ITimeConstraints.sol";
import {IDGLaunchVerifier} from "../interfaces/IDGLaunchVerifier.sol";
import {IInsuranceFund} from "../interfaces/IInsuranceFund.sol";
import {IOZ} from "../interfaces/IOZ.sol";
import {IACL} from "../interfaces/IACL.sol";

import {LidoAddressesMainnet} from "./LidoAddressesMainnet.sol";
import {OmnibusBase} from "scripts/utils/OmnibusBase.sol";

import {ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";

/// @title LaunchOmnibusMainnet
/// @notice Contains vote items for execution via Aragon Voting to migrate control of Lido’s critical roles,
/// permissions, and contracts to Dual Governance. Provides a mechanism for validating an Aragon vote
/// against the actions in this contract, by passing the vote ID.
///
/// @dev This contract defines the complete set of governance actions required to migrate Lido protocol control
/// from Aragon Voting to the Dual Governance on Ethereum Mainnet.
///
/// It provides:
/// - A list of 54 vote items that must be submitted and executed through an Aragon vote to perform the migration.
/// - Includes:
///     1. Reassigning critical permissions and permission managers from the Aragon Voting to the Aragon Agent
///     2. Creating permissions needed for Aragon Voting to operate under Dual Governance
///     3. Transferring ownership of WithdrawalVault contract to Aragon Agent
///     4. Transferring ownership of InsuranceFund contract to Aragon Voting
///     5. Validating that all role, ownership and permission migrations were completed correctly
///     6. Submitting the first proposal to Dual Governance to finalize migration
///     7. Enforcing time constraints on enactment and execution
///
/// Additionally, the contract provides a mechanism to validate whether an existing Aragon vote corresponds
/// exactly to the migration actions defined here. This ensures consistency and guards against
/// misconfigured or malicious votes.
///
/// Note: The contract is intended to be used as a reference and validation tool for constructing
/// a governance vote that initiates the migration of critical roles, permissions and ownerships to Dual Governance.
/// It must be used by the Aragon Voting and couldn't be executed directly.
contract DGLaunchOmnibusMainnet is OmnibusBase, LidoAddressesMainnet {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    uint256 public constant VOTE_ITEMS_COUNT = 54;
    uint256 public constant DG_PROPOSAL_CALLS_COUNT = 5;

    Timestamp public constant OMNIBUS_EXPIRATION_TIMESTAMP = Timestamp.wrap(1753466400); // Friday, 25 July 2025 18:00:00 UTC
    Timestamp public constant DG_PROPOSAL_EXPIRATION_TIMESTAMP = Timestamp.wrap(1754071200); // Friday, 1 August 2025 18:00:00 UTC
    Duration public constant DG_PROPOSAL_EXECUTABLE_FROM_DAY_TIME = Duration.wrap(6 hours); // 06:00 UTC
    Duration public constant DG_PROPOSAL_EXECUTABLE_TILL_DAY_TIME = Duration.wrap(18 hours); // 18:00 UTC

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

        bytes32 PAUSE_ROLE = keccak256("PAUSE_ROLE");
        bytes32 RESUME_ROLE = keccak256("RESUME_ROLE");
        bytes32 RUN_SCRIPT_ROLE = keccak256("RUN_SCRIPT_ROLE");
        bytes32 EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
        bytes32 STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE");
        bytes32 SET_NODE_OPERATOR_LIMIT_ROLE = keccak256("SET_NODE_OPERATOR_LIMIT_ROLE");
        bytes32 MANAGE_NODE_OPERATOR_ROLE = keccak256("MANAGE_NODE_OPERATOR_ROLE");

        // Lido Permissions Transition
        {
            bytes32 STAKING_CONTROL_ROLE = keccak256("STAKING_CONTROL_ROLE");
            bytes32 STAKING_PAUSE_ROLE = keccak256("STAKING_PAUSE_ROLE");

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
                description: "7. Revoke STAKING_PAUSE_ROLE permission from Voting on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, LIDO, STAKING_PAUSE_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "8. Set STAKING_PAUSE_ROLE manager to Agent on Lido",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, LIDO, STAKING_PAUSE_ROLE)))
            });
        }

        // DAOKernel Permissions Transition
        {
            bytes32 APP_MANAGER_ROLE = keccak256("APP_MANAGER_ROLE");

            voteItems[index++] = VoteItem({
                description: "9. Revoke APP_MANAGER_ROLE permission from Voting on DAOKernel",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, KERNEL, APP_MANAGER_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "10. Set APP_MANAGER_ROLE manager to Agent on DAOKernel",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, KERNEL, APP_MANAGER_ROLE)))
            });
        }

        // TokenManager Permissions Transition
        {
            bytes32 MINT_ROLE = keccak256("MINT_ROLE");
            bytes32 REVOKE_VESTINGS_ROLE = keccak256("REVOKE_VESTINGS_ROLE");

            voteItems[index++] = VoteItem({
                description: "11. Create MINT_ROLE permission on TokenManager with manager Voting and grant it to Voting",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, MINT_ROLE, VOTING)))
            });

            voteItems[index++] = VoteItem({
                description: "12. Create REVOKE_VESTINGS_ROLE permission on TokenManager with manager Voting and grant it to Voting",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, REVOKE_VESTINGS_ROLE, VOTING))
                )
            });
        }

        // Finance Permissions Transition
        {
            bytes32 CHANGE_PERIOD_ROLE = keccak256("CHANGE_PERIOD_ROLE");
            bytes32 CHANGE_BUDGETS_ROLE = keccak256("CHANGE_BUDGETS_ROLE");

            voteItems[index++] = VoteItem({
                description: "13. Create CHANGE_PERIOD_ROLE permission on Finance with manager Voting and grant it to Voting",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, FINANCE, CHANGE_PERIOD_ROLE, VOTING)))
            });

            voteItems[index++] = VoteItem({
                description: "14. Create CHANGE_BUDGETS_ROLE permission on Finance with manager Voting and grant it to Voting",
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
                description: "15. Revoke REGISTRY_ADD_EXECUTOR_ROLE permission from Voting on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "16. Set REGISTRY_ADD_EXECUTOR_ROLE manager to Agent on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "17. Revoke REGISTRY_MANAGER_ROLE permission from Voting on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "18. Set REGISTRY_MANAGER_ROLE manager to Agent on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE))
                )
            });
        }

        // CuratedModule Permissions Transition
        {
            bytes32 MANAGE_SIGNING_KEYS = keccak256("MANAGE_SIGNING_KEYS");

            voteItems[index++] = VoteItem({
                description: "19. Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, STAKING_ROUTER_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "20. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "21. Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "22. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "23. Revoke MANAGE_SIGNING_KEYS permission from Voting on CuratedModule",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, CURATED_MODULE, MANAGE_SIGNING_KEYS)))
            });

            voteItems[index++] = VoteItem({
                description: "24. Set MANAGE_SIGNING_KEYS manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, MANAGE_SIGNING_KEYS))
                )
            });
        }

        // Simple DVT Module Permissions Transition
        {
            voteItems[index++] = VoteItem({
                description: "25. Set STAKING_ROUTER_ROLE manager to Agent on SimpleDVT",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, SDVT_MODULE, STAKING_ROUTER_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "26. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on SimpleDVT",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "27. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on SimpleDVT",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE))
                )
            });
        }

        // ACL Permissions Transition
        {
            bytes32 CREATE_PERMISSIONS_ROLE = keccak256("CREATE_PERMISSIONS_ROLE");

            voteItems[index++] = VoteItem({
                description: "28. Grant CREATE_PERMISSIONS_ROLE permission to Agent on ACL",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (AGENT, ACL, CREATE_PERMISSIONS_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "29. Revoke CREATE_PERMISSIONS_ROLE permission from Voting on ACL",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, ACL, CREATE_PERMISSIONS_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "30. Set CREATE_PERMISSIONS_ROLE manager to Agent on ACL",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, ACL, CREATE_PERMISSIONS_ROLE)))
            });
        }

        // Agent Permissions Transition
        {
            voteItems[index++] = VoteItem({
                description: "31. Grant RUN_SCRIPT_ROLE permission to DGAdminExecutor on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (ADMIN_EXECUTOR, AGENT, RUN_SCRIPT_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "32. Set RUN_SCRIPT_ROLE manager to Agent on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, AGENT, RUN_SCRIPT_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "33. Grant EXECUTE_ROLE permission to DGAdminExecutor on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (ADMIN_EXECUTOR, AGENT, EXECUTE_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "34. Set EXECUTE_ROLE manager to Agent on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, AGENT, EXECUTE_ROLE)))
            });
        }

        // WithdrawalQueue Roles Transition
        {
            voteItems[index++] = VoteItem({
                description: "35. Grant PAUSE_ROLE to ResealManager on WithdrawalQueueERC721",
                call: _forwardCall(AGENT, WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
            });

            voteItems[index++] = VoteItem({
                description: "36. Grant RESUME_ROLE to ResealManager on WithdrawalQueueERC721",
                call: _forwardCall(AGENT, WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
            });
        }

        // VEBO Roles Transition
        {
            voteItems[index++] = VoteItem({
                description: "37. Grant PAUSE_ROLE to ResealManager on ValidatorsExitBusOracle",
                call: _forwardCall(AGENT, VEBO, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
            });

            voteItems[index++] = VoteItem({
                description: "38. Grant RESUME_ROLE to ResealManager on ValidatorsExitBusOracle",
                call: _forwardCall(AGENT, VEBO, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
            });
        }

        // CS Module Roles Transition
        {
            voteItems[index++] = VoteItem({
                description: "39. Grant PAUSE_ROLE to ResealManager on CSModule",
                call: _forwardCall(AGENT, CS_MODULE, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
            });

            voteItems[index++] = VoteItem({
                description: "40. Grant RESUME_ROLE to ResealManager on CSModule",
                call: _forwardCall(AGENT, CS_MODULE, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
            });
        }

        // CS Accounting Roles Transition
        {
            voteItems[index++] = VoteItem({
                description: "41. Grant PAUSE_ROLE to ResealManager on CSAccounting",
                call: _forwardCall(AGENT, CS_ACCOUNTING, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
            });

            voteItems[index++] = VoteItem({
                description: "42. Grant RESUME_ROLE to ResealManager on CSAccounting",
                call: _forwardCall(AGENT, CS_ACCOUNTING, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
            });
        }

        // CS Fee Oracle Roles Transition
        {
            voteItems[index++] = VoteItem({
                description: "43. Grant PAUSE_ROLE to ResealManager on CSFeeOracle",
                call: _forwardCall(AGENT, CS_FEE_ORACLE, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
            });

            voteItems[index++] = VoteItem({
                description: "44. Grant RESUME_ROLE to ResealManager on CSFeeOracle",
                call: _forwardCall(AGENT, CS_FEE_ORACLE, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
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
                description: "47. Revoke ADD_TOKEN_TO_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (ADD_TOKEN_TO_ALLOWED_LIST_ROLE, AGENT))
                )
            });

            voteItems[index++] = VoteItem({
                description: "48. Revoke REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, AGENT))
                )
            });
        }

        // WithdrawalVault admin transition
        {
            voteItems[index++] = VoteItem({
                description: "49. Set admin to Agent on WithdrawalVault",
                call: _votingCall(WITHDRAWAL_VAULT, abi.encodeCall(IWithdrawalVaultProxy.proxy_changeAdmin, (AGENT)))
            });
        }

        // InsuranceFund owner transition
        {
            voteItems[index++] = VoteItem({
                description: "50. Set owner to Voting on InsuranceFund",
                call: _forwardCall(AGENT, INSURANCE_FUND, abi.encodeCall(IInsuranceFund.transferOwnership, (VOTING)))
            });
        }

        // Validate transferred roles
        {
            voteItems[index++] = VoteItem({
                description: "51. Validate transferred roles",
                call: _votingCall(ROLES_VALIDATOR, abi.encodeCall(IRolesValidator.validateVotingLaunchPhase, ()))
            });
        }

        // Submit first dual governance proposal
        {
            ExternalCallsBuilder.Context memory dgProposalCallsBuilder =
                ExternalCallsBuilder.create({callsCount: DG_PROPOSAL_CALLS_COUNT});

            // 1. Add the "expiration date" to the Dual Governance proposal
            dgProposalCallsBuilder.addCall(
                TIME_CONSTRAINTS,
                abi.encodeCall(ITimeConstraints.checkTimeBeforeTimestampAndEmit, DG_PROPOSAL_EXPIRATION_TIMESTAMP)
            );

            // 2. Add the "execution time window" to the Dual Governance proposal
            dgProposalCallsBuilder.addCall(
                TIME_CONSTRAINTS,
                abi.encodeCall(
                    ITimeConstraints.checkTimeWithinDayTimeAndEmit,
                    (DG_PROPOSAL_EXECUTABLE_FROM_DAY_TIME, DG_PROPOSAL_EXECUTABLE_TILL_DAY_TIME)
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
            dgProposalCallsBuilder.addCall(
                ROLES_VALIDATOR, abi.encodeCall(IRolesValidator.validateDGProposalLaunchPhase, ())
            );

            voteItems[index++] = VoteItem({
                description: "52. Submit a proposal to the Dual Governance to revoke RUN_SCRIPT_ROLE and EXECUTE_ROLE from Aragon Voting",
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
                description: "53. Verify Dual Governance launch state",
                call: _votingCall(LAUNCH_VERIFIER, abi.encodeCall(IDGLaunchVerifier.verify, ()))
            });
        }

        // Add the "expiration date" to the omnibus
        {
            voteItems[index++] = VoteItem({
                description: "54. Introduce an expiration deadline after which the omnibus can no longer be enacted",
                call: _votingCall(
                    TIME_CONSTRAINTS,
                    abi.encodeCall(ITimeConstraints.checkTimeBeforeTimestampAndEmit, OMNIBUS_EXPIRATION_TIMESTAMP)
                )
            });
        }
    }
}
