// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LidoAddressesMainnet} from "./LidoAddressesMainnet.sol";

import {AragonRoles} from "../libraries/AragonRoles.sol";
import {OZRoles} from "../libraries/OZRoles.sol";
import {IRolesValidator} from "../interfaces/IRolesValidator.sol";
import {IWithdrawalVaultProxy} from "../interfaces/IWithdrawalVaultProxy.sol";
import {IInsuranceFund} from "../interfaces/IInsuranceFund.sol";
import {RolesValidatorBase} from "../RolesValidatorBase.sol";

contract DGRolesValidatorMainnet is RolesValidatorBase, LidoAddressesMainnet, IRolesValidator {
    using OZRoles for OZRoles.Context;
    using AragonRoles for AragonRoles.Context;

    error InvalidWithdrawalsVaultProxyAdmin(address actual, address expected);
    error InvalidInsuranceFundOwner(address actual, address expected);

    address public immutable ADMIN_EXECUTOR;
    address public immutable RESEAL_MANAGER;

    constructor(address adminExecutor, address resealManager) RolesValidatorBase(ACL) {
        ADMIN_EXECUTOR = adminExecutor;
        RESEAL_MANAGER = resealManager;
    }

    function validateVotingLaunchPhase() external {
        // Lido
        _validate(LIDO, "STAKING_CONTROL_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(LIDO, "RESUME_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(LIDO, "PAUSE_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(LIDO, "STAKING_PAUSE_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));

        // DAOKernel
        _validate(KERNEL, "APP_MANAGER_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));

        // TokenManager
        _validate(TOKEN_MANAGER, "MINT_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(TOKEN_MANAGER, "REVOKE_VESTINGS_ROLE", AragonRoles.manager(VOTING).granted(VOTING));

        // Finance
        _validate(FINANCE, "CHANGE_PERIOD_ROLE", AragonRoles.manager(VOTING).granted(VOTING));
        _validate(FINANCE, "CHANGE_BUDGETS_ROLE", AragonRoles.manager(VOTING).granted(VOTING));

        // Aragon EVMScriptRegistry
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_ADD_EXECUTOR_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_MANAGER_ROLE", AragonRoles.manager(AGENT).revoked(VOTING));

        // CuratedModule
        _validate(CURATED_MODULE, "STAKING_ROUTER_ROLE", AragonRoles.manager(AGENT).granted(STAKING_ROUTER));
        _validate(CURATED_MODULE, "MANAGE_NODE_OPERATOR_ROLE", AragonRoles.manager(AGENT).granted(AGENT));
        _validate(
            CURATED_MODULE,
            "SET_NODE_OPERATOR_LIMIT_ROLE",
            AragonRoles.manager(AGENT).revoked(VOTING).granted(EVM_SCRIPT_EXECUTOR)
        );
        _validate(CURATED_MODULE, "MANAGE_SIGNING_KEYS", AragonRoles.manager(AGENT).revoked(VOTING));

        // SimpleDVT Module
        _validate(
            SDVT_MODULE,
            "STAKING_ROUTER_ROLE",
            AragonRoles.manager(AGENT).granted(STAKING_ROUTER).granted(EVM_SCRIPT_EXECUTOR)
        );
        _validate(SDVT_MODULE, "MANAGE_NODE_OPERATOR_ROLE", AragonRoles.manager(AGENT).granted(EVM_SCRIPT_EXECUTOR));
        _validate(SDVT_MODULE, "SET_NODE_OPERATOR_LIMIT_ROLE", AragonRoles.manager(AGENT).granted(EVM_SCRIPT_EXECUTOR));

        // ACL
        _validate(ACL, "CREATE_PERMISSIONS_ROLE", AragonRoles.manager(AGENT).revoked(VOTING).granted(AGENT));

        // Agent

        // The `revoked(VOTING)` check is intentionally replaced with `granted(VOTING) in the checks below.
        // At the time of vote execution, this permission is still granted to Voting and is intended to be revoked
        // via a DualGovernance proposal. The corresponding validation is performed in `validateDGProposalLaunchPhase()`
        // as the final step of the Dual Governance launch process.
        _validate(AGENT, "RUN_SCRIPT_ROLE", AragonRoles.manager(AGENT).granted(VOTING).granted(ADMIN_EXECUTOR));
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.manager(AGENT).granted(VOTING).granted(ADMIN_EXECUTOR));

        // WithdrawalQueue
        _validate(WITHDRAWAL_QUEUE, "PAUSE_ROLE", OZRoles.granted(RESEAL_MANAGER).granted(ORACLES_GATE_SEAL));
        _validate(WITHDRAWAL_QUEUE, "RESUME_ROLE", OZRoles.granted(RESEAL_MANAGER));

        // VEBO
        _validate(VEBO, "PAUSE_ROLE", OZRoles.granted(RESEAL_MANAGER).granted(ORACLES_GATE_SEAL));
        _validate(VEBO, "RESUME_ROLE", OZRoles.granted(RESEAL_MANAGER));

        // CS Module
        _validate(CS_MODULE, "PAUSE_ROLE", OZRoles.granted(RESEAL_MANAGER).granted(CS_GATE_SEAL));
        _validate(CS_MODULE, "RESUME_ROLE", OZRoles.granted(RESEAL_MANAGER));

        // CS Accounting
        _validate(CS_ACCOUNTING, "PAUSE_ROLE", OZRoles.granted(RESEAL_MANAGER).granted(CS_GATE_SEAL));
        _validate(CS_ACCOUNTING, "RESUME_ROLE", OZRoles.granted(RESEAL_MANAGER));

        // CS Fee Oracle
        _validate(CS_FEE_ORACLE, "PAUSE_ROLE", OZRoles.granted(RESEAL_MANAGER).granted(CS_GATE_SEAL));
        _validate(CS_FEE_ORACLE, "RESUME_ROLE", OZRoles.granted(RESEAL_MANAGER));

        // AllowedTokensRegistry
        _validate(ALLOWED_TOKENS_REGISTRY, "DEFAULT_ADMIN_ROLE", OZRoles.revoked(AGENT).granted(VOTING));
        _validate(ALLOWED_TOKENS_REGISTRY, "ADD_TOKEN_TO_ALLOWED_LIST_ROLE", OZRoles.revoked(AGENT));
        _validate(ALLOWED_TOKENS_REGISTRY, "REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE", OZRoles.revoked(AGENT));

        // WithdrawalVault
        address withdrawalVaultProxyAdmin = IWithdrawalVaultProxy(WITHDRAWAL_VAULT).proxy_getAdmin();
        if (withdrawalVaultProxyAdmin != AGENT) {
            revert InvalidWithdrawalsVaultProxyAdmin(withdrawalVaultProxyAdmin, AGENT);
        }

        // InsuranceFund
        address insuranceFundOwner = IInsuranceFund(INSURANCE_FUND).owner();
        if (insuranceFundOwner != VOTING) {
            revert InvalidInsuranceFundOwner(insuranceFundOwner, VOTING);
        }
    }

    function validateDGProposalLaunchPhase() external {
        // Agent
        _validate(AGENT, "RUN_SCRIPT_ROLE", AragonRoles.manager(AGENT).revoked(VOTING).granted(ADMIN_EXECUTOR));
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.manager(AGENT).revoked(VOTING).granted(ADMIN_EXECUTOR));
    }
}
