// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations} from "contracts/types/Duration.sol";
import {IGovernance} from "contracts/interfaces/IGovernance.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {EvmScriptUtils} from "test/utils/evm-script-utils.sol";

import {LidoAddressesHolesky} from "./LidoAddressesHolesky.sol";
import {OmnibusBase} from "../OmnibusBase.sol";

import {IOZ} from "../interfaces/IOZ.sol";
import {IACL} from "../interfaces/IACL.sol";
import {IWithdrawalVaultProxy} from "../interfaces/IWithdrawalVaultProxy.sol";
import {IRolesValidator, IDGLaunchVerifier, ITimeConstraints} from "../interfaces/utils.sol";

/**
 * @title DGUpgradeHolesky
 * @notice Script for migrating Lido to Dual Governance on Holesky testnet
 *
 * @dev This contract prepares the complete transition of the Lido protocol
 * critical roles and ownerships from direct Aragon Voting control to Dual Governance
 * on the Holesky testnet. It contains 51 items that includes:
 *
 * 1. Revoking critical permissions from Voting and transferring permission management to Agent
 * 2. Transferring ownerships to Agent over critical protocol contracts
 * 4. Validating the roles transfer to ensure proper role configuration
 * 5. Submitting the first proposal through the Dual Governance
 * 6. Verifying the successful launch of Dual Governance
 */
contract DGUpgradeHolesky is OmnibusBase, LidoAddressesHolesky {
    bytes32 private constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 private constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 private constant RUN_SCRIPT_ROLE = keccak256("RUN_SCRIPT_ROLE");
    bytes32 private constant EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    bytes32 private constant STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE");
    bytes32 private constant SET_NODE_OPERATOR_LIMIT_ROLE = keccak256("SET_NODE_OPERATOR_LIMIT_ROLE");
    bytes32 private constant MANAGE_NODE_OPERATOR_ROLE = keccak256("MANAGE_NODE_OPERATOR_ROLE");

    uint256 public constant VOTE_ITEMS_COUNT = 53;

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
    ) {
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

        {
            // Lido
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

        {
            // DAOKernel
            bytes32 APP_MANAGER_ROLE = keccak256("APP_MANAGER_ROLE");

            voteItems[index++] = VoteItem({
                description: "9. Revoke APP_MANAGER_ROLE permission from Voting on Kernel",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, KERNEL, APP_MANAGER_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "10. Set APP_MANAGER_ROLE manager to Agent on Kernel",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, KERNEL, APP_MANAGER_ROLE)))
            });
        }

        {
            // TokenManager
            bytes32 MINT_ROLE = keccak256("MINT_ROLE");
            bytes32 BURN_ROLE = keccak256("BURN_ROLE");
            bytes32 ISSUE_ROLE = keccak256("ISSUE_ROLE");
            bytes32 REVOKE_VESTINGS_ROLE = keccak256("REVOKE_VESTINGS_ROLE");

            voteItems[index++] = VoteItem({
                description: "11. Set MINT_ROLE manager and grant role to Voting on TokenManager",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, MINT_ROLE, VOTING)))
            });

            voteItems[index++] = VoteItem({
                description: "12. Set REVOKE_VESTINGS_ROLE manager and grant role to Voting on TokenManager",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, REVOKE_VESTINGS_ROLE, VOTING))
                )
            });

            voteItems[index++] = VoteItem({
                description: "13. Set BURN_ROLE manager and grant role to Voting on TokenManager",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, BURN_ROLE, VOTING)))
            });

            voteItems[index++] = VoteItem({
                description: "14. Set ISSUE_ROLE manager and grant role to Voting on TokenManager",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, TOKEN_MANAGER, ISSUE_ROLE, VOTING)))
            });
        }

        {
            // Finance
            bytes32 CHANGE_PERIOD_ROLE = keccak256("CHANGE_PERIOD_ROLE");
            bytes32 CHANGE_BUDGETS_ROLE = keccak256("CHANGE_BUDGETS_ROLE");

            voteItems[index++] = VoteItem({
                description: "15. Set CHANGE_PERIOD_ROLE manager to Voting on Finance",
                call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, FINANCE, CHANGE_PERIOD_ROLE, VOTING)))
            });

            voteItems[index++] = VoteItem({
                description: "16. Set CHANGE_BUDGETS_ROLE manager to Voting on Finance",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.createPermission, (VOTING, FINANCE, CHANGE_BUDGETS_ROLE, VOTING))
                )
            });
        }

        {
            // EVMScriptRegistry
            bytes32 REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");
            bytes32 REGISTRY_ADD_EXECUTOR_ROLE = keccak256("REGISTRY_ADD_EXECUTOR_ROLE");

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

            voteItems[index++] = VoteItem({
                description: "19. Revoke REGISTRY_ADD_EXECUTOR_ROLE permission from Voting on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "20. Set REGISTRY_ADD_EXECUTOR_ROLE manager to Agent on EVMScriptRegistry",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE))
                )
            });
        }

        {
            // CuratedModule
            bytes32 MANAGE_SIGNING_KEYS = keccak256("MANAGE_SIGNING_KEYS");

            voteItems[index++] = VoteItem({
                description: "21. Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, STAKING_ROUTER_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "22. Revoke MANAGE_NODE_OPERATOR_ROLE permission from Voting on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "23. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "24. Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.revokePermission, (VOTING, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "25. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "26. Revoke MANAGE_SIGNING_KEYS permission from Voting on CuratedModule",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, CURATED_MODULE, MANAGE_SIGNING_KEYS)))
            });

            voteItems[index++] = VoteItem({
                description: "27. Set MANAGE_SIGNING_KEYS manager to Agent on CuratedModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, MANAGE_SIGNING_KEYS))
                )
            });
        }

        {
            // SDVTModule
            voteItems[index++] = VoteItem({
                description: "28. Set STAKING_ROUTER_ROLE manager to Agent on SDVTModule",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, SDVT_MODULE, STAKING_ROUTER_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "29. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on SDVTModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE))
                )
            });

            voteItems[index++] = VoteItem({
                description: "30. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on SDVTModule",
                call: _votingCall(
                    ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE))
                )
            });
        }

        {
            // ACL
            bytes32 CREATE_PERMISSIONS_ROLE = keccak256("CREATE_PERMISSIONS_ROLE");

            voteItems[index++] = VoteItem({
                description: "31. Grant CREATE_PERMISSIONS_ROLE permission to Agent on ACL",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (AGENT, ACL, CREATE_PERMISSIONS_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "32. Revoke CREATE_PERMISSIONS_ROLE permission from Voting on ACL",
                call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, ACL, CREATE_PERMISSIONS_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "33. Set CREATE_PERMISSIONS_ROLE manager to Agent on ACL",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, ACL, CREATE_PERMISSIONS_ROLE)))
            });
        }

        {
            // WithdrawalQueue
            voteItems[index++] = VoteItem({
                description: "34. Grant PAUSE_ROLE on WithdrawalQueue to ResealManager",
                call: _forwardCall(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
            });

            voteItems[index++] = VoteItem({
                description: "35. Grant RESUME_ROLE on WithdrawalQueue to ResealManager",
                call: _forwardCall(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
            });
        }

        {
            // VEBO
            voteItems[index++] = VoteItem({
                description: "36. Grant PAUSE_ROLE on VEBO to ResealManager",
                call: _forwardCall(VEBO, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
            });

            voteItems[index++] = VoteItem({
                description: "37. Grant RESUME_ROLE on VEBO to ResealManager",
                call: _forwardCall(VEBO, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
            });
        }

        {
            // AllowedTokensRegistry
            bytes32 DEFAULT_ADMIN_ROLE = bytes32(0);
            bytes32 ADD_TOKEN_TO_ALLOWED_LIST_ROLE = keccak256("ADD_TOKEN_TO_ALLOWED_LIST_ROLE");
            bytes32 REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE = keccak256("REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE");

            voteItems[index++] = VoteItem({
                description: "38. Grant DEFAULT_ADMIN_ROLE on AllowedTokensRegistry to Voting",
                call: _forwardCall(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (DEFAULT_ADMIN_ROLE, VOTING)))
            });

            voteItems[index++] = VoteItem({
                description: "39. Revoke DEFAULT_ADMIN_ROLE on AllowedTokensRegistry from AGENT",
                call: _votingCall(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (DEFAULT_ADMIN_ROLE, AGENT)))
            });

            voteItems[index++] = VoteItem({
                description: "40. Grant ADD_TOKEN_TO_ALLOWED_LIST_ROLE on AllowedTokensRegistry to Voting",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (ADD_TOKEN_TO_ALLOWED_LIST_ROLE, VOTING))
                )
            });

            voteItems[index++] = VoteItem({
                description: "41. Revoke ADD_TOKEN_TO_ALLOWED_LIST_ROLE on AllowedTokensRegistry from AGENT",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (ADD_TOKEN_TO_ALLOWED_LIST_ROLE, AGENT))
                )
            });

            voteItems[index++] = VoteItem({
                description: "42. Grant REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE on AllowedTokensRegistry to Voting",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, VOTING))
                )
            });

            voteItems[index++] = VoteItem({
                description: "43. Revoke REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE on AllowedTokensRegistry from AGENT",
                call: _votingCall(
                    ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, AGENT))
                )
            });
        }

        {
            // WithdrawalVault
            voteItems[index++] = VoteItem({
                description: "44. Set admin to Agent on WithdrawalVault",
                call: _votingCall(WITHDRAWAL_VAULT, abi.encodeCall(IWithdrawalVaultProxy.proxy_changeAdmin, (AGENT)))
            });
        }

        {
            // Agent
            voteItems[index++] = VoteItem({
                description: "45. Grant RUN_SCRIPT_ROLE to DualGovernance Executor on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (ADMIN_EXECUTOR, AGENT, RUN_SCRIPT_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "46. Set RUN_SCRIPT_ROLE manager to Agent on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, AGENT, RUN_SCRIPT_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "47. Grant EXECUTE_ROLE to DualGovernance Executor on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.grantPermission, (ADMIN_EXECUTOR, AGENT, EXECUTE_ROLE)))
            });

            voteItems[index++] = VoteItem({
                description: "48. Set EXECUTE_ROLE manager to Agent on Agent",
                call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, AGENT, EXECUTE_ROLE)))
            });
        }

        {
            // Manager multisig
            voteItems[index++] = VoteItem({
                description: "49. Grant RUN_SCRIPT_ROLE to Manager multisig on Agent",
                call: _forwardCall(ACL, abi.encodeCall(IACL.grantPermission, (MANAGER_MULTISIG, AGENT, RUN_SCRIPT_ROLE)))
            });
        }

        {
            // Validate transferred roles
            voteItems[index++] = VoteItem({
                description: "50. Validate transferred roles",
                call: _votingCall(
                    ROLES_VALIDATOR, abi.encodeCall(IRolesValidator.validate, (ADMIN_EXECUTOR, RESEAL_MANAGER))
                )
            });
        }

        {
            // Submit first dual governance proposal
            ExternalCall[] memory executorCalls = new ExternalCall[](5);
            uint256 executorCallsIndex = 0;

            executorCalls[executorCallsIndex++] = _executorCall(
                TIME_CONSTRAINTS,
                // Execution is allowed before Wednesday, 30 April 2025 00:00:00
                abi.encodeCall(ITimeConstraints.checkExecuteBeforeTimestamp, (Timestamps.from(1745971200)))
            );

            executorCalls[executorCallsIndex++] = _executorCall(
                TIME_CONSTRAINTS,
                // Execution is allowed since 04:00 to 22:00
                abi.encodeCall(
                    ITimeConstraints.checkExecuteWithinDayTime, (Durations.from(4 hours), Durations.from(22 hours))
                )
            );

            executorCalls[executorCallsIndex++] =
                _forwardCallFromExecutor(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, AGENT, RUN_SCRIPT_ROLE)));

            executorCalls[executorCallsIndex++] =
                _forwardCallFromExecutor(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, AGENT, EXECUTE_ROLE)));

            executorCalls[executorCallsIndex++] = _forwardCallFromExecutor(
                ROLES_VALIDATOR, abi.encodeCall(IRolesValidator.validateAfterDG, (ADMIN_EXECUTOR))
            );

            voteItems[index++] = VoteItem({
                description: "51. Submit a proposal to the Dual Governance to revoke RUN_SCRIPT_ROLE and EXECUTE_ROLE from Aragon Voting",
                call: _votingCall(
                    DUAL_GOVERNANCE,
                    abi.encodeCall(
                        IGovernance.submitProposal,
                        (executorCalls, string("Revoke RUN_SCRIPT_ROLE and EXECUTE_ROLE from Aragon Voting"))
                    )
                )
            });
        }

        {
            // Verify state of the DG after launch
            voteItems[index++] = VoteItem({
                description: "52. Verify dual governance launch",
                call: _votingCall(LAUNCH_VERIFIER, abi.encodeCall(IDGLaunchVerifier.verify, ()))
            });
        }

        {
            // Verify state of the DG after launch
            voteItems[index++] = VoteItem({
                description: "53. Verify dual governance launch",
                call: _votingCall(
                    TIME_CONSTRAINTS,
                    // 1745971200 is Wednesday, 30 April 2025 00:00:00
                    abi.encodeCall(ITimeConstraints.checkExecuteBeforeTimestamp, (Timestamps.from(1745971200)))
                )
            });
        }
    }

    function _voting() internal pure override returns (address) {
        return VOTING;
    }

    function _forwarder() internal pure override returns (address) {
        return AGENT;
    }

    function _voteItemsCount() internal pure override returns (uint256) {
        return VOTE_ITEMS_COUNT;
    }
}
