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

    constructor() RolesValidatorBase(ACL) {}

    function validate(address dualGovernanceExecutor, address resealManager) external {
        // Lido
        _validate(LIDO, "STAKING_CONTROL_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));
        _validate(LIDO, "RESUME_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));
        _validate(LIDO, "PAUSE_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));
        _validate(LIDO, "STAKING_PAUSE_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));

        // Kernel
        _validate(KERNEL, "APP_MANAGER_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));

        // TokenManager
        _validate(TOKEN_MANAGER, "MINT_ROLE", AragonRoles.checkManager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "REVOKE_VESTINGS_ROLE", AragonRoles.checkManager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "BURN_ROLE", AragonRoles.checkManager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "ISSUE_ROLE", AragonRoles.checkManager(VOTING).granted(VOTING));

        // Finance
        _validate(FINANCE, "CHANGE_PERIOD_ROLE", AragonRoles.checkManager(VOTING).granted(VOTING));
        _validate(FINANCE, "CHANGE_BUDGETS_ROLE", AragonRoles.checkManager(VOTING).granted(VOTING));

        // Aragon EVMScriptRegistry
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_MANAGER_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_ADD_EXECUTOR_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));

        // CuratedModule
        _validate(CURATED_MODULE, "STAKING_ROUTER_ROLE", AragonRoles.checkManager(AGENT));
        _validate(CURATED_MODULE, "MANAGE_NODE_OPERATOR_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));
        _validate(CURATED_MODULE, "SET_NODE_OPERATOR_LIMIT_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));
        _validate(CURATED_MODULE, "MANAGE_SIGNING_KEYS", AragonRoles.checkManager(AGENT).revoked(VOTING));

        // SDVTModule
        _validate(SDVT_MODULE, "STAKING_ROUTER_ROLE", AragonRoles.checkManager(AGENT));
        _validate(SDVT_MODULE, "MANAGE_NODE_OPERATOR_ROLE", AragonRoles.checkManager(AGENT));
        _validate(SDVT_MODULE, "SET_NODE_OPERATOR_LIMIT_ROLE", AragonRoles.checkManager(AGENT));

        // Agent
        _validate(
            AGENT,
            "RUN_SCRIPT_ROLE",
            AragonRoles.checkManager(AGENT).granted(dualGovernanceExecutor).granted(VOTING).granted(MANAGER_MULTISIG)
        );
        _validate(
            AGENT, "EXECUTE_ROLE", AragonRoles.checkManager(AGENT).granted(dualGovernanceExecutor).granted(VOTING)
        );

        // ACL
        _validate(ACL, "CREATE_PERMISSIONS_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING).granted(AGENT));

        // WithdrawalQueue
        _validate(WITHDRAWAL_QUEUE, "PAUSE_ROLE", OZRoles.granted(resealManager));
        _validate(WITHDRAWAL_QUEUE, "RESUME_ROLE", OZRoles.granted(resealManager));

        // VEBO
        _validate(VEBO, "PAUSE_ROLE", OZRoles.granted(resealManager));
        _validate(VEBO, "RESUME_ROLE", OZRoles.granted(resealManager));

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

    function validateAfterDG(address executor) external {
        // Agent
        _validate(
            AGENT,
            "RUN_SCRIPT_ROLE",
            AragonRoles.checkManager(AGENT).revoked(VOTING).granted(executor).granted(MANAGER_MULTISIG)
        );
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING).granted(executor));
    }
}
