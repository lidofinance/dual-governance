// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LidoAddressesHolesky} from "./LidoAddressesHolesky.sol";

import {AragonRoles} from "../libraries/AragonRoles.sol";
import {OZRoles} from "../libraries/OZRoles.sol";
import {IWithdrawalVaultProxy} from "../interfaces/IWithdrawalVaultProxy.sol";
import {RolesValidatorBase} from "../RolesValidatorBase.sol";

contract RolesValidatorHolesky is RolesValidatorBase, LidoAddressesHolesky {
    using OZRoles for OZRoles.Context;
    using AragonRoles for AragonRoles.Context;

    error InvalidWithdrawalsVaultProxyAdmin(address actual, address expected);

    address public immutable ADMIN_EXECUTOR;
    address public immutable RESEAL_MANAGER;

    // Additional grantee of the Agent.RUN_SCRIPT_ROLE, which may be used
    // for development purposes or as a fallback recovery mechanism.
    address public immutable AGENT_MANAGER;

    constructor(address adminExecutor, address resealManager, address agentManager) RolesValidatorBase(ACL) {
        ADMIN_EXECUTOR = adminExecutor;
        RESEAL_MANAGER = resealManager;
        AGENT_MANAGER = agentManager;
    }

    function validate() external {
        // ACL
        _validate(ACL, "CREATE_PERMISSIONS_ROLE", AragonRoles.manager(AGENT).revoked(VOTING).granted(AGENT));

        // Lido
        _validate(LIDO, "STAKING_CONTROL_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(LIDO, "RESUME_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(LIDO, "PAUSE_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(LIDO, "UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE", AragonRoles.manager(address(0)).revoked(VOTING));
        _validate(LIDO, "STAKING_PAUSE_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));

        // DAOKernel
        _validate(KERNEL, "APP_MANAGER_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));

        // TokenManager
        _validate(TOKEN_MANAGER, "ISSUE_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "BURN_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "MINT_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "REVOKE_VESTINGS_ROLE", AragonRoles.manager(VOTING).granted(VOTING));

        // Finance
        _validate(FINANCE, "CHANGE_PERIOD_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(FINANCE, "CHANGE_BUDGETS_ROLE", AragonRoles.manager(VOTING).granted(VOTING));

        // Aragon EVMScriptRegistry
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_MANAGER_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_ADD_EXECUTOR_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));

        // CuratedModule
        _validate(CURATED_MODULE, "STAKING_ROUTER_ROLE", AragonRoles.manager(AGENT));
        _validate(CURATED_MODULE, "MANAGE_NODE_OPERATOR_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(CURATED_MODULE, "SET_NODE_OPERATOR_LIMIT_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(CURATED_MODULE, "MANAGE_SIGNING_KEYS", AragonRoles.manager(AGENT).revoked(VOTING));

        // SDVTModule
        _validate(SDVT_MODULE, "STAKING_ROUTER_ROLE", AragonRoles.manager(AGENT));
        _validate(SDVT_MODULE, "MANAGE_NODE_OPERATOR_ROLE", AragonRoles.manager(AGENT));
        _validate(SDVT_MODULE, "SET_NODE_OPERATOR_LIMIT_ROLE", AragonRoles.manager(AGENT));

        // Agent
        _validate(
            AGENT,
            "RUN_SCRIPT_ROLE",
            AragonRoles.manager(AGENT).granted(ADMIN_EXECUTOR).granted(VOTING).granted(AGENT_MANAGER)
        );
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.manager(AGENT).granted(ADMIN_EXECUTOR).granted(VOTING));

        // WithdrawalQueue
        _validate(WITHDRAWAL_QUEUE, "PAUSE_ROLE", OZRoles.granted(RESEAL_MANAGER));
        _validate(WITHDRAWAL_QUEUE, "RESUME_ROLE", OZRoles.granted(RESEAL_MANAGER));

        // VEBO
        _validate(VEBO, "PAUSE_ROLE", OZRoles.granted(RESEAL_MANAGER));
        _validate(VEBO, "RESUME_ROLE", OZRoles.granted(RESEAL_MANAGER));

        // AllowedTokensRegistry
        _validate(ALLOWED_TOKENS_REGISTRY, "DEFAULT_ADMIN_ROLE", OZRoles.granted(VOTING).revoked(AGENT));
        _validate(ALLOWED_TOKENS_REGISTRY, "ADD_TOKEN_TO_ALLOWED_LIST_ROLE", OZRoles.granted(VOTING).revoked(AGENT));
        _validate(
            ALLOWED_TOKENS_REGISTRY, "REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE", OZRoles.granted(VOTING).revoked(AGENT)
        );

        // WithdrawalVault
        address withdrawalVaultProxyAdmin = IWithdrawalVaultProxy(WITHDRAWAL_VAULT).proxy_getAdmin();
        if (withdrawalVaultProxyAdmin != AGENT) {
            revert InvalidWithdrawalsVaultProxyAdmin(withdrawalVaultProxyAdmin, AGENT);
        }
    }

    function validateAfterDG() external {
        // Agent
        _validate(
            AGENT,
            "RUN_SCRIPT_ROLE",
            AragonRoles.manager(AGENT).revoked(VOTING).granted(ADMIN_EXECUTOR).granted(AGENT_MANAGER)
        );
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.manager(AGENT).revoked(VOTING).granted(ADMIN_EXECUTOR));
    }
}
