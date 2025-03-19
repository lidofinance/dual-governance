// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LidoMainnetAddresses} from "../LidoMainnetAddresses.sol";
import {AragonRoles} from "./libraries/AragonRoles.sol";
import {OZRoles} from "./libraries/OZRoles.sol";

import {RolesValidator} from "./RolesValidator.sol";

interface IWithdrawalsManagerProxy {
    function proxy_getAdmin() external returns (address);
}

interface IOwnable {
    function owner() external view returns (address);
}

contract MainnetRolesAndOwnershipsValidator is RolesValidator {
    using OZRoles for OZRoles.Context;
    using AragonRoles for AragonRoles.Context;

    error InvalidWithdrawalsVaultProxyAdmin(address actual, address expected);
    error InvalidInsuranceFundOwner(address actual, address expected);

    constructor() RolesValidator(LidoMainnetAddresses.ACL) {}

    function validate(address dualGovernanceExecutor, address resealManager) external {
        // Lido
        _validate(
            LidoMainnetAddresses.LIDO,
            "STAKING_CONTROL_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING)
        );
        _validate(
            LidoMainnetAddresses.LIDO,
            "RESUME_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING)
        );
        _validate(
            LidoMainnetAddresses.LIDO,
            "PAUSE_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING)
        );
        _validate(
            LidoMainnetAddresses.LIDO,
            "STAKING_PAUSE_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING)
        );

        // DAOKernel
        _validate(
            LidoMainnetAddresses.KERNEL,
            "APP_MANAGER_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING)
        );

        // TokenManager
        _validate(
            LidoMainnetAddresses.TOKEN_MANAGER,
            "MINT_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.VOTING).granted(LidoMainnetAddresses.VOTING)
        );
        _validate(
            LidoMainnetAddresses.TOKEN_MANAGER,
            "REVOKE_VESTINGS_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.VOTING).granted(LidoMainnetAddresses.VOTING)
        );

        // Finance
        _validate(
            LidoMainnetAddresses.FINANCE,
            "CHANGE_PERIOD_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.VOTING).granted(LidoMainnetAddresses.VOTING)
        );
        _validate(
            LidoMainnetAddresses.FINANCE,
            "CHANGE_BUDGETS_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.VOTING).granted(LidoMainnetAddresses.VOTING)
        );

        // Aragon EVMScriptRegistry
        _validate(
            LidoMainnetAddresses.EVM_SCRIPT_REGISTRY,
            "REGISTRY_MANAGER_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING)
        );
        _validate(
            LidoMainnetAddresses.EVM_SCRIPT_REGISTRY,
            "REGISTRY_ADD_EXECUTOR_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING)
        );

        // CuratedModule
        _validate(
            LidoMainnetAddresses.CURATED_MODULE,
            "STAKING_ROUTER_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT)
        );
        _validate(
            LidoMainnetAddresses.CURATED_MODULE,
            "MANAGE_NODE_OPERATOR_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT)
        );
        _validate(
            LidoMainnetAddresses.CURATED_MODULE,
            "SET_NODE_OPERATOR_LIMIT_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING)
        );
        _validate(
            LidoMainnetAddresses.CURATED_MODULE,
            "MANAGE_SIGNING_KEYS",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING)
        );

        // SDVTModule
        _validate(
            LidoMainnetAddresses.CURATED_MODULE,
            "STAKING_ROUTER_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT)
        );
        _validate(
            LidoMainnetAddresses.CURATED_MODULE,
            "MANAGE_NODE_OPERATOR_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT)
        );
        _validate(
            LidoMainnetAddresses.CURATED_MODULE,
            "SET_NODE_OPERATOR_LIMIT_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT)
        );

        // Agent
        // RUN_SCRIPT_ROLE and EXECUTE_ROLE at this moment are grantd to the both: Voting and DualGovernanceExecutor.
        // This is intended behavior to have a safe if dual governance proposal won't be executed for some reason.
        _validate(
            LidoMainnetAddresses.AGENT,
            "RUN_SCRIPT_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).granted(dualGovernanceExecutor)
        );
        _validate(
            LidoMainnetAddresses.AGENT,
            "EXECUTE_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).granted(dualGovernanceExecutor)
        );

        // ACL
        _validate(
            LidoMainnetAddresses.ACL,
            "CREATE_PERMISSIONS_ROLE",
            AragonRoles.checkManager(LidoMainnetAddresses.AGENT).revoked(LidoMainnetAddresses.VOTING).granted(
                LidoMainnetAddresses.AGENT
            )
        );

        // WithdrawalQueue
        _validate(LidoMainnetAddresses.WITHDRAWAL_QUEUE, "PAUSE_ROLE", OZRoles.granted(resealManager));
        _validate(LidoMainnetAddresses.WITHDRAWAL_QUEUE, "RESUME_ROLE", OZRoles.granted(resealManager));

        // VEBO
        _validate(LidoMainnetAddresses.VEBO, "PAUSE_ROLE", OZRoles.granted(resealManager));
        _validate(LidoMainnetAddresses.VEBO, "RESUME_ROLE", OZRoles.granted(resealManager));

        // AllowedTokensRegistry
        _validate(
            LidoMainnetAddresses.ALLOWED_TOKENS_REGISTRY,
            "DEFAULT_ADMIN_ROLE",
            OZRoles.granted(LidoMainnetAddresses.VOTING).revoked(LidoMainnetAddresses.AGENT)
        );
        _validate(
            LidoMainnetAddresses.ALLOWED_TOKENS_REGISTRY,
            "ADD_TOKEN_TO_ALLOWED_LIST_ROLE",
            OZRoles.granted(LidoMainnetAddresses.VOTING).revoked(LidoMainnetAddresses.AGENT)
        );
        _validate(
            LidoMainnetAddresses.ALLOWED_TOKENS_REGISTRY,
            "REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE",
            OZRoles.granted(LidoMainnetAddresses.VOTING).revoked(LidoMainnetAddresses.AGENT)
        );

        // WithdrawalVault
        address withdrawalVaultProxyAdmin =
            IWithdrawalsManagerProxy(LidoMainnetAddresses.WITHDRAWAL_VAULT).proxy_getAdmin();
        if (withdrawalVaultProxyAdmin != LidoMainnetAddresses.AGENT) {
            revert InvalidWithdrawalsVaultProxyAdmin(withdrawalVaultProxyAdmin, LidoMainnetAddresses.AGENT);
        }

        // InsuranceFund
        address insuranceFundOwner = IOwnable(LidoMainnetAddresses.INSURANCE_FUND).owner();
        if (insuranceFundOwner != LidoMainnetAddresses.VOTING) {
            revert InvalidInsuranceFundOwner(insuranceFundOwner, LidoMainnetAddresses.VOTING);
        }
    }

    function validateAfterDG(address dualGovernanceExecutor) external {
        _validate(
            LidoMainnetAddresses.AGENT,
            "RUN_SCRIPT_ROLE",
            AragonRoles.revoked(LidoMainnetAddresses.VOTING).granted(dualGovernanceExecutor)
        );
        _validate(
            LidoMainnetAddresses.AGENT,
            "EXECUTE_ROLE",
            AragonRoles.revoked(LidoMainnetAddresses.VOTING).granted(dualGovernanceExecutor)
        );
    }
}
