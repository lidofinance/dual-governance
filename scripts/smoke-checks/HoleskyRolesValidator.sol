// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AragonRoles} from "./libraries/AragonRoles.sol";
import {OZRoles} from "./libraries/OZRoles.sol";

import {LidoRolesValidator} from "./LidoRolesValidator.sol";

interface IWithdrawalsManagerProxy {
    function proxy_getAdmin() external returns (address);
}

contract HoleskyRolesValidator is LidoRolesValidator {
    using OZRoles for OZRoles.Context;
    using AragonRoles for AragonRoles.Context;

    address public constant ACL_ADDRESS = 0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC;
    address public constant LIDO = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address public constant KERNEL = 0x3b03f75Ec541Ca11a223bB58621A3146246E1644;
    address public constant VOTING = 0xdA7d2573Df555002503F29aA4003e398d28cc00f;
    address public constant TOKEN_MANAGER = 0xFaa1692c6eea8eeF534e7819749aD93a1420379A;
    address public constant FINANCE = 0xf0F281E5d7FBc54EAFcE0dA225CDbde04173AB16;
    address public constant AGENT = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d;
    address public constant EVM_SCRIPT_REGISTRY = 0xE1200ae048163B67D69Bc0492bF5FddC3a2899C0;
    address public constant CURATED_MODULE = 0x595F64Ddc3856a3b5Ff4f4CC1d1fb4B46cFd2bAC;
    address public constant SDVT_MODULE = 0x11a93807078f8BB880c1BD0ee4C387537de4b4b6;
    address public constant ALLOWED_TOKENS_REGISTRY = 0x091C0eC8B4D54a9fcB36269B5D5E5AF43309e666;
    address public constant WITHDRAWAL_VAULT = 0xF0179dEC45a37423EAD4FaD5fCb136197872EAd9;
    address public constant WITHDRAWAL_QUEUE = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;

    constructor() LidoRolesValidator(ACL_ADDRESS) {}

    function validate(address executor, address resealManager) external {
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
        _validate(AGENT, "RUN_SCRIPT_ROLE", AragonRoles.checkManager(AGENT).granted(executor).granted(VOTING));
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.checkManager(AGENT).granted(executor).granted(VOTING));

        // ACL
        _validate(
            ACL_ADDRESS, "CREATE_PERMISSIONS_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING).granted(AGENT)
        );

        // WithdrawalQueue
        _validate(WITHDRAWAL_QUEUE, "PAUSE_ROLE", OZRoles.granted(resealManager));
        _validate(WITHDRAWAL_QUEUE, "RESUME_ROLE", OZRoles.granted(resealManager));

        // AllowedTokensRegistry
        _validate(ALLOWED_TOKENS_REGISTRY, "DEFAULT_ADMIN_ROLE", OZRoles.granted(VOTING).revoked(AGENT));
        _validate(ALLOWED_TOKENS_REGISTRY, "ADD_TOKEN_TO_ALLOWED_LIST_ROLE", OZRoles.granted(VOTING).revoked(AGENT));
        _validate(
            ALLOWED_TOKENS_REGISTRY, "REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE", OZRoles.granted(VOTING).revoked(AGENT)
        );

        // WithdrawalVault
        assert(IWithdrawalsManagerProxy(WITHDRAWAL_VAULT).proxy_getAdmin() == AGENT);
    }

    function validateAfterDG() external {
        // Agent
        _validate(AGENT, "RUN_SCRIPT_ROLE", AragonRoles.revoked(VOTING));
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.revoked(VOTING));
    }
}
