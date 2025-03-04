// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AragonRoles} from "./libraries/AragonRoles.sol";
import {OZRoles} from "./libraries/OZRoles.sol";

import {LidoRolesValidator} from "./LidoRolesValidator.sol";

interface IWithdrawalsManagerProxy {
    function proxy_getAdmin() external returns (address);
}

interface IOwnable {
    function owner() external view returns (address);
}

contract MainnetRolesValidator is LidoRolesValidator {
    using OZRoles for OZRoles.Context;
    using AragonRoles for AragonRoles.Context;

    address public constant ACL_ADDRESS = 0x9895F0F17cc1d1891b6f18ee0b483B6f221b37Bb;
    address public constant LIDO = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant KERNEL = 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc;
    address public constant VOTING = 0x2e59A20f205bB85a89C53f1936454680651E618e;
    address public constant TOKEN_MANAGER = 0xf73a1260d222f447210581DDf212D915c09a3249;
    address public constant FINANCE = 0xB9E5CBB9CA5b0d659238807E84D0176930753d86;
    address public constant AGENT = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
    address public constant EVM_SCRIPT_REGISTRY = 0x853cc0D5917f49B57B8e9F89e491F5E18919093A;
    address public constant CURATED_MODULE = 0x55032650b14df07b85bF18A3a3eC8E0Af2e028d5;
    address public constant SDVT_MODULE = 0xaE7B191A31f627b4eB1d4DaC64eaB9976995b433;
    address public constant ALLOWED_TOKENS_REGISTRY = 0x4AC40c34f8992bb1e5E856A448792158022551ca;
    address public constant WITHDRAWAL_VAULT = 0xB9D7934878B5FB9610B3fE8A5e441e8fad7E293f;
    address public constant WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
    address public constant INSURANCE_FUND = 0x8B3f33234ABD88493c0Cd28De33D583B70beDe35;

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
        _validate(TOKEN_MANAGER, "MINT_ROLE", AragonRoles.checkManager(VOTING));
        _validate(TOKEN_MANAGER, "REVOKE_VESTINGS_ROLE", AragonRoles.checkManager(VOTING));

        // Finance
        _validate(FINANCE, "CHANGE_PERIOD_ROLE", AragonRoles.checkManager(VOTING));
        _validate(FINANCE, "CHANGE_BUDGETS_ROLE", AragonRoles.checkManager(VOTING));

        // Aragon EVMScriptRegistry
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_MANAGER_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));
        _validate(EVM_SCRIPT_REGISTRY, "REGISTRY_ADD_EXECUTOR_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));

        // CuratedModule
        _validate(CURATED_MODULE, "STAKING_ROUTER_ROLE", AragonRoles.checkManager(AGENT));
        _validate(CURATED_MODULE, "MANAGE_NODE_OPERATOR_ROLE", AragonRoles.checkManager(AGENT));
        _validate(CURATED_MODULE, "SET_NODE_OPERATOR_LIMIT_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING));
        _validate(CURATED_MODULE, "MANAGE_SIGNING_KEYS", AragonRoles.checkManager(AGENT).revoked(VOTING));

        // SDVTModule
        _validate(CURATED_MODULE, "STAKING_ROUTER_ROLE", AragonRoles.checkManager(AGENT));
        _validate(CURATED_MODULE, "MANAGE_NODE_OPERATOR_ROLE", AragonRoles.checkManager(AGENT));
        _validate(CURATED_MODULE, "SET_NODE_OPERATOR_LIMIT_ROLE", AragonRoles.checkManager(AGENT));

        // Agent
        _validate(AGENT, "RUN_SCRIPT_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING).granted(executor));
        _validate(AGENT, "EXECUTE_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING).granted(executor));

        // ACL
        _validate(ACL_ADDRESS, "CREATE_PERMISSION_ROLE", AragonRoles.checkManager(AGENT).revoked(VOTING).granted(AGENT));

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

        // InsuranceFund
        assert(IOwnable(INSURANCE_FUND).owner() == VOTING);
    }
}
