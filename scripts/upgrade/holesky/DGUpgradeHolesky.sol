// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGovernance} from "contracts/interfaces/IGovernance.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {EvmScriptUtils} from "test/utils/evm-script-utils.sol";

import {LidoAddressesHolesky} from "./LidoAddressesHolesky.sol";
import {OmnibusBase} from "../OmnibusBase.sol";

import {IOZ} from "../interfaces/IOZ.sol";
import {IACL} from "../interfaces/IACL.sol";
import {IWithdrawalVaultProxy} from "../interfaces/IWithdrawalVaultProxy.sol";
import {IRolesValidator, IDGLaunchVerifier, ITimeConstraints} from "../interfaces/utils.sol";

contract DGUpgradeHolesky is OmnibusBase, LidoAddressesHolesky {
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant STAKING_CONTROL_ROLE = keccak256("STAKING_CONTROL_ROLE");
    bytes32 public constant STAKING_PAUSE_ROLE = keccak256("STAKING_PAUSE_ROLE");
    bytes32 public constant APP_MANAGER_ROLE = keccak256("APP_MANAGER_ROLE");
    bytes32 public constant REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");
    bytes32 public constant REGISTRY_ADD_EXECUTOR_ROLE = keccak256("REGISTRY_ADD_EXECUTOR_ROLE");
    bytes32 public constant SET_NODE_OPERATOR_LIMIT_ROLE = keccak256("SET_NODE_OPERATOR_LIMIT_ROLE");
    bytes32 public constant MANAGE_SIGNING_KEYS = keccak256("MANAGE_SIGNING_KEYS");
    bytes32 public constant CREATE_PERMISSIONS_ROLE = keccak256("CREATE_PERMISSIONS_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant ISSUE_ROLE = keccak256("ISSUE_ROLE");
    bytes32 public constant ADD_TOKEN_TO_ALLOWED_LIST_ROLE = keccak256("ADD_TOKEN_TO_ALLOWED_LIST_ROLE");
    bytes32 public constant REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE = keccak256("REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE");
    bytes32 public constant RUN_SCRIPT_ROLE = keccak256("RUN_SCRIPT_ROLE");
    bytes32 public constant EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    bytes32 public constant STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE");
    bytes32 public constant MANAGE_NODE_OPERATOR_ROLE = keccak256("MANAGE_NODE_OPERATOR_ROLE");
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant REVOKE_VESTINGS_ROLE = keccak256("REVOKE_VESTINGS_ROLE");
    bytes32 public constant CHANGE_PERIOD_ROLE = keccak256("CHANGE_PERIOD_ROLE");
    bytes32 public constant CHANGE_BUDGETS_ROLE = keccak256("CHANGE_BUDGETS_ROLE");

    address public immutable DUAL_GOVERNANCE;
    address public immutable ADMIN_EXECUTOR;
    address public immutable RESEAL_MANAGER;
    address public immutable ROLES_VALIDATOR;
    address public immutable LAUNCH_VERIFIER;

    uint256 public constant VOTE_ITEMS_COUNT = 51;

    constructor(
        address dualGovernance,
        address adminExecutor,
        address resealManager,
        address rolesValidator,
        address launchVerifier
    ) {
        DUAL_GOVERNANCE = dualGovernance;
        ADMIN_EXECUTOR = adminExecutor;
        RESEAL_MANAGER = resealManager;
        ROLES_VALIDATOR = rolesValidator;
        LAUNCH_VERIFIER = launchVerifier;
    }

    function getVoteItems() public view override returns (VoteItem[] memory voteItems) {
        voteItems = new VoteItem[](VOTE_ITEMS_COUNT);
        uint256 index = 0;

        // Lido
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

        // Kernel
        voteItems[index++] = VoteItem({
            description: "9. Revoke APP_MANAGER_ROLE permission from Voting on Kernel",
            call: _votingCall(ACL, abi.encodeCall(IACL.revokePermission, (VOTING, KERNEL, APP_MANAGER_ROLE)))
        });
        voteItems[index++] = VoteItem({
            description: "10. Set APP_MANAGER_ROLE manager to Agent on Kernel",
            call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, KERNEL, APP_MANAGER_ROLE)))
        });

        // TokenManager
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

        // Finance
        voteItems[index++] = VoteItem({
            description: "15. Set CHANGE_PERIOD_ROLE manager to Voting on Finance",
            call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, FINANCE, CHANGE_PERIOD_ROLE, VOTING)))
        });
        voteItems[index++] = VoteItem({
            description: "16. Set CHANGE_BUDGETS_ROLE manager to Voting on Finance",
            call: _votingCall(ACL, abi.encodeCall(IACL.createPermission, (VOTING, FINANCE, CHANGE_BUDGETS_ROLE, VOTING)))
        });

        // EVMScriptRegistry
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

        // CuratedModule
        voteItems[index++] = VoteItem({
            description: "21. Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule",
            call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, STAKING_ROUTER_ROLE)))
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
            call: _votingCall(ACL, abi.encodeCall(IACL.setPermissionManager, (AGENT, CURATED_MODULE, MANAGE_SIGNING_KEYS)))
        });

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

        // ACL
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

        // WithdrawalQueue
        voteItems[index++] = VoteItem({
            description: "34. Grant PAUSE_ROLE on WithdrawalQueue to ResealManager",
            call: _forwardCall(AGENT, WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
        });
        voteItems[index++] = VoteItem({
            description: "35. Grant RESUME_ROLE on WithdrawalQueue to ResealManager",
            call: _forwardCall(AGENT, WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
        });

        // VEBO
        voteItems[index++] = VoteItem({
            description: "36. Grant PAUSE_ROLE on VEBO to ResealManager",
            call: _forwardCall(AGENT, VEBO, abi.encodeCall(IOZ.grantRole, (PAUSE_ROLE, RESEAL_MANAGER)))
        });
        voteItems[index++] = VoteItem({
            description: "37. Grant RESUME_ROLE on VEBO to ResealManager",
            call: _forwardCall(AGENT, VEBO, abi.encodeCall(IOZ.grantRole, (RESUME_ROLE, RESEAL_MANAGER)))
        });

        // AllowedTokensRegistry
        voteItems[index++] = VoteItem({
            description: "38. Grant DEFAULT_ADMIN_ROLE on AllowedTokensRegistry to Voting",
            call: _forwardCall(AGENT, ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (DEFAULT_ADMIN_ROLE, VOTING)))
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

        // WithdrawalVault
        voteItems[index++] = VoteItem({
            description: "44. Set admin to Agent on WithdrawalVault",
            call: _votingCall(WITHDRAWAL_VAULT, abi.encodeCall(IWithdrawalVaultProxy.proxy_changeAdmin, (AGENT)))
        });

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

        // Validate transferred roles
        voteItems[index++] = VoteItem({
            description: "49. Validate transferred roles",
            call: _votingCall(ROLES_VALIDATOR, abi.encodeCall(IRolesValidator.validate, (ADMIN_EXECUTOR, RESEAL_MANAGER)))
        });

        // Submit first dual governance proposal
        ExternalCall[] memory executorCalls = new ExternalCall[](3);
        executorCalls[0] = _forwardCallFromExecutor(
            AGENT, ACL, abi.encodeCall(IACL.revokePermission, (VOTING, AGENT, RUN_SCRIPT_ROLE))
        );
        executorCalls[1] =
            _forwardCallFromExecutor(AGENT, ACL, abi.encodeCall(IACL.revokePermission, (VOTING, AGENT, EXECUTE_ROLE)));
        executorCalls[2] = _forwardCallFromExecutor(
            AGENT, ROLES_VALIDATOR, abi.encodeCall(IRolesValidator.validateAfterDG, (ADMIN_EXECUTOR))
        );
        voteItems[index++] = VoteItem({
            description: "50. Submit first proposal",
            call: _votingCall(
                DUAL_GOVERNANCE,
                abi.encodeCall(IGovernance.submitProposal, (executorCalls, string("First dual governance proposal")))
            )
        });

        // Verify state of the DG after launch
        voteItems[index++] = VoteItem({
            description: "51. Verify dual governance launch",
            call: _votingCall(LAUNCH_VERIFIER, abi.encodeCall(IDGLaunchVerifier.verify, ()))
        });
    }

    function getVoteItemsCount() internal pure override returns (uint256) {
        return VOTE_ITEMS_COUNT;
    }

    function validateVote(uint256 voteId) external view returns (bool) {
        return super.validateVote(VOTING, voteId);
    }
}
