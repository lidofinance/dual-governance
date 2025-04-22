// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LidoAddressesHolesky} from "./LidoAddressesHolesky.sol";

import {AragonRoles} from "../libraries/AragonRoles.sol";
import {OZRoles} from "../libraries/OZRoles.sol";
import {IRolesValidator} from "../interfaces/IRolesValidator.sol";
import {IWithdrawalVaultProxy} from "../interfaces/IWithdrawalVaultProxy.sol";
import {RolesValidatorBase} from "../RolesValidatorBase.sol";

contract RolesValidatorHolesky is RolesValidatorBase, LidoAddressesHolesky, IRolesValidator {
    using OZRoles for OZRoles.Context;
    using AragonRoles for AragonRoles.Context;

    error InvalidWithdrawalsVaultProxyAdmin(address actual, address expected);

    address public immutable ADMIN_EXECUTOR;
    address public immutable RESEAL_MANAGER;

    constructor(address adminExecutor, address resealManager) RolesValidatorBase(ACL) {
        ADMIN_EXECUTOR = adminExecutor;
        RESEAL_MANAGER = resealManager;
    }

    function validateVotingLaunchPhase() external {
        // Lido
        _validate(
            LIDO,
            "STAKING_CONTROL_ROLE",
            AragonRoles.manager(AGENT).revoked(VOTING).granted(DEV_EOA_1).granted(UNLIMITED_STAKE)
        );
        _validate(LIDO, "RESUME_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(LIDO, "PAUSE_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(LIDO, "UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(LIDO, "STAKING_PAUSE_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));

        // DAOKernel
        _validate(KERNEL, "APP_MANAGER_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));

        // TokenManager
        _validate(TOKEN_MANAGER, "MINT_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "REVOKE_VESTINGS_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "BURN_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "ISSUE_ROLE", AragonRoles.manager(VOTING).granted(VOTING));

        // Finance
        _validate(FINANCE, "CHANGE_PERIOD_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(FINANCE, "CHANGE_BUDGETS_ROLE", AragonRoles.manager(VOTING).granted(VOTING));

        // Aragon EVMScriptRegistry
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_MANAGER_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_ADD_EXECUTOR_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));

        // CuratedModule
        _validate(
            CURATED_MODULE,
            "MANAGE_NODE_OPERATOR_ROLE",
            AragonRoles.manager(AGENT).revoked(VOTING).granted(DEV_EOA_2).granted(DEV_EOA_1)
        );
        _validate(
            CURATED_MODULE,
            "SET_NODE_OPERATOR_LIMIT_ROLE",
            AragonRoles.manager(AGENT).revoked(VOTING).granted(DEV_EOA_1).granted(DEV_EOA_2).granted(
                EVM_SCRIPT_EXECUTOR
            )
        );
        _validate(CURATED_MODULE, "MANAGE_SIGNING_KEYS", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(
            CURATED_MODULE,
            "STAKING_ROUTER_ROLE",
            AragonRoles.manager(AGENT).granted(STAKING_ROUTER).granted(DEV_EOA_2).granted(DEV_EOA_1)
        );

        // SDVTModule
        _validate(
            SDVT_MODULE,
            "STAKING_ROUTER_ROLE",
            AragonRoles.manager(AGENT).granted(STAKING_ROUTER).granted(EVM_SCRIPT_EXECUTOR).granted(DEV_EOA_3)
        );
        _validate(
            SDVT_MODULE,
            "MANAGE_NODE_OPERATOR_ROLE",
            AragonRoles.manager(AGENT).granted(EVM_SCRIPT_EXECUTOR).granted(DEV_EOA_3)
        );
        _validate(
            SDVT_MODULE,
            "SET_NODE_OPERATOR_LIMIT_ROLE",
            AragonRoles.manager(AGENT).granted(EVM_SCRIPT_EXECUTOR).granted(DEV_EOA_3)
        );

        // ACL
        _validate(ACL, "CREATE_PERMISSIONS_ROLE", AragonRoles.manager(AGENT).revoked(VOTING).granted(AGENT));

        // Agent

        // The `revoked(VOTING)` check is intentionally replaced with `granted(VOTING) in the checks below.
        // At the time of vote execution, this permission is still granted to Voting and is intended to be revoked
        // via a DualGovernance proposal. The corresponding validation is performed in `validateDGProposalLaunchPhase()`
        // as the final step of the Dual Governance launch process.
        _validate(
            AGENT,
            "RUN_SCRIPT_ROLE",
            AragonRoles.manager(AGENT).granted(VOTING).granted(ADMIN_EXECUTOR).granted(AGENT_MANAGER)
        );
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.manager(AGENT).granted(VOTING).granted(ADMIN_EXECUTOR));

        // WithdrawalQueue
        _validate(WITHDRAWAL_QUEUE, "PAUSE_ROLE", OZRoles.granted(RESEAL_MANAGER).granted(ORACLES_GATE_SEAL));
        _validate(WITHDRAWAL_QUEUE, "RESUME_ROLE", OZRoles.granted(RESEAL_MANAGER).granted(AGENT));

        // VEBO
        _validate(VEBO, "PAUSE_ROLE", OZRoles.granted(RESEAL_MANAGER).granted(ORACLES_GATE_SEAL));
        _validate(VEBO, "RESUME_ROLE", OZRoles.granted(RESEAL_MANAGER).granted(AGENT));

        // AllowedTokensRegistry
        _validate(ALLOWED_TOKENS_REGISTRY, "DEFAULT_ADMIN_ROLE", OZRoles.revoked(AGENT).granted(VOTING));
        _validate(ALLOWED_TOKENS_REGISTRY, "ADD_TOKEN_TO_ALLOWED_LIST_ROLE", OZRoles.revoked(AGENT).granted(VOTING));
        _validate(
            ALLOWED_TOKENS_REGISTRY, "REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE", OZRoles.revoked(AGENT).granted(VOTING)
        );

        // WithdrawalVault
        address withdrawalVaultProxyAdmin = IWithdrawalVaultProxy(WITHDRAWAL_VAULT).proxy_getAdmin();
        if (withdrawalVaultProxyAdmin != AGENT) {
            revert InvalidWithdrawalsVaultProxyAdmin(withdrawalVaultProxyAdmin, AGENT);
        }
    }

    function validateDGProposalLaunchPhase() external {
        // Agent
        _validate(
            AGENT,
            "RUN_SCRIPT_ROLE",
            AragonRoles.manager(AGENT).revoked(VOTING).granted(ADMIN_EXECUTOR).granted(AGENT_MANAGER)
        );
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.manager(AGENT).revoked(VOTING).granted(ADMIN_EXECUTOR));
    }
}
