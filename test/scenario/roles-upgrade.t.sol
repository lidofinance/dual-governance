// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAragonACL} from "../utils/interfaces/IAragonACL.sol";
import {ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";

contract RolesUpgrade is ScenarioTestBlueprint {
    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});
    }

    function testFork_RolesUpgrade() external {
        address voting = address(_lido.voting);
        address adminExecutor = address(_adminExecutor);
        address stETH = address(_lido.stETH);
        address finance = 0xB9E5CBB9CA5b0d659238807E84D0176930753d86;
        address nor = 0x55032650b14df07b85bF18A3a3eC8E0Af2e028d5;
        address sdvt = 0xaE7B191A31f627b4eB1d4DaC64eaB9976995b433;
        address kernel = 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc;
        address aragon_evm_script_registry = 0x853cc0D5917f49B57B8e9F89e491F5E18919093A;
        address aragon_token_manager = 0xf73a1260d222f447210581DDf212D915c09a3249;

        vm.startPrank(voting);

        /// ACL
        /// CREATE_PERMISSIONS_ROLE
        _transferRole(voting, adminExecutor, address(_lido.acl), keccak256("CREATE_PERMISSIONS_ROLE"));
        _transferManager(voting, adminExecutor, address(_lido.acl), keccak256("CREATE_PERMISSIONS_ROLE"));

        /// KERNEL
        /// APP_MANAGER_ROLE
        _transferRole(voting, adminExecutor, kernel, keccak256("APP_MANAGER_ROLE"));
        _transferManager(voting, adminExecutor, kernel, keccak256("APP_MANAGER_ROLE"));

        /// ARAGON_EVMSCRIPT_REGISTRY
        /// REGISTRY_ADD_EXECUTOR_ROLE
        _transferRole(voting, adminExecutor, aragon_evm_script_registry, keccak256("REGISTRY_ADD_EXECUTOR_ROLE"));
        _transferManager(voting, adminExecutor, aragon_evm_script_registry, keccak256("REGISTRY_ADD_EXECUTOR_ROLE"));

        /// REGISTRY_MANAGER_ROLE
        _transferRole(voting, adminExecutor, aragon_evm_script_registry, keccak256("REGISTRY_MANAGER_ROLE"));
        _transferManager(voting, adminExecutor, aragon_evm_script_registry, keccak256("REGISTRY_MANAGER_ROLE"));

        /// ARAGON_TOKEN_MANAGER
        /// ISSUE_ROLE
        _transferManager(voting, adminExecutor, aragon_token_manager, keccak256("ISSUE_ROLE"));

        /// ASSIGN_ROLE
        _transferRole(voting, adminExecutor, aragon_token_manager, keccak256("ASSIGN_ROLE"));
        _transferManager(voting, adminExecutor, aragon_token_manager, keccak256("ASSIGN_ROLE"));

        /// BURN_ROLE
        _transferManager(voting, adminExecutor, aragon_token_manager, keccak256("BURN_ROLE"));

        /// STETH
        /// PAUSE_ROLE
        _transferRole(voting, adminExecutor, stETH, keccak256("PAUSE_ROLE"));
        _transferManager(voting, adminExecutor, stETH, keccak256("PAUSE_ROLE"));

        /// RESUME_ROLE
        _transferRole(voting, adminExecutor, stETH, keccak256("RESUME_ROLE"));
        _transferManager(voting, adminExecutor, stETH, keccak256("RESUME_ROLE"));

        /// STAKING_CONTROL_ROLE
        _transferRole(voting, adminExecutor, stETH, keccak256("STAKING_CONTROL_ROLE"));
        _transferManager(voting, adminExecutor, stETH, keccak256("STAKING_CONTROL_ROLE"));

        /// STAKING_PAUSE_ROLE
        _transferRole(voting, adminExecutor, stETH, keccak256("STAKING_PAUSE_ROLE"));
        _transferManager(voting, adminExecutor, stETH, keccak256("STAKING_PAUSE_ROLE"));

        /// BURN_ROLE
        _transferManager(voting, adminExecutor, stETH, keccak256("BURN_ROLE"));

        /// AGENT
        /// EXECUTE_ROLE
        _transferRole(voting, adminExecutor, address(_lido.agent), keccak256("EXECUTE_ROLE"));
        _transferManager(voting, adminExecutor, address(_lido.agent), keccak256("EXECUTE_ROLE"));

        /// RUN_SCRIPT_ROLE
        _transferRole(voting, adminExecutor, address(_lido.agent), keccak256("RUN_SCRIPT_ROLE"));
        _transferManager(voting, adminExecutor, address(_lido.agent), keccak256("RUN_SCRIPT_ROLE"));

        /// TRANSFER_ROLE
        _transferManager(voting, adminExecutor, address(_lido.agent), keccak256("TRANSFER_ROLE"));

        /// FINANCE
        /// EXECUTE_PAYMENTS_ROLE
        _transferRole(voting, adminExecutor, finance, keccak256("EXECUTE_PAYMENTS_ROLE"));
        _transferManager(voting, adminExecutor, finance, keccak256("EXECUTE_PAYMENTS_ROLE"));

        /// MANAGE_PAYMENTS_ROLE
        _transferRole(voting, adminExecutor, finance, keccak256("MANAGE_PAYMENTS_ROLE"));
        _transferManager(voting, adminExecutor, finance, keccak256("MANAGE_PAYMENTS_ROLE"));

        /// CREATE_PAYMENTS_ROLE
        _transferRole(voting, adminExecutor, finance, keccak256("CREATE_PAYMENTS_ROLE"));
        _transferManager(voting, adminExecutor, finance, keccak256("CREATE_PAYMENTS_ROLE"));

        /// VOTING
        /// MODIFY_QUORUM_ROLE
        _transferRole(voting, adminExecutor, address(_lido.voting), keccak256("MODIFY_QUORUM_ROLE"));
        _transferManager(voting, adminExecutor, address(_lido.voting), keccak256("MODIFY_QUORUM_ROLE"));

        /// MODIFY_SUPPORT_ROLE
        _transferRole(voting, adminExecutor, address(_lido.voting), keccak256("MODIFY_SUPPORT_ROLE"));
        _transferManager(voting, adminExecutor, address(_lido.voting), keccak256("MODIFY_SUPPORT_ROLE"));

        /// CREATE_VOTES_ROLE
        _transferManager(voting, adminExecutor, address(_lido.voting), keccak256("CREATE_VOTES_ROLE"));

        /// UNSAFELY_MODIFY_VOTE_TIME_ROLE
        _transferManager(voting, adminExecutor, address(_lido.voting), keccak256("UNSAFELY_MODIFY_VOTE_TIME_ROLE"));

        /// Node Operators registry
        /// MANAGE_SIGNING_KEYS
        _transferRole(voting, adminExecutor, nor, keccak256("MANAGE_SIGNING_KEYS"));
        _transferManager(voting, adminExecutor, nor, keccak256("MANAGE_SIGNING_KEYS"));

        /// SET_NODE_OPERATOR_LIMIT_ROLE
        _transferRole(voting, adminExecutor, nor, keccak256("SET_NODE_OPERATOR_LIMIT_ROLE"));
        _transferManager(voting, adminExecutor, nor, keccak256("SET_NODE_OPERATOR_LIMIT_ROLE"));

        /// STAKING_ROUTER_ROLE
        _transferManager(voting, adminExecutor, nor, keccak256("STAKING_ROUTER_ROLE"));

        /// MANAGE_NODE_OPERATOR_ROLE
        _transferManager(voting, adminExecutor, nor, keccak256("MANAGE_NODE_OPERATOR_ROLE"));

        /// Simple DVT
        /// STAKING_ROUTER_ROLE
        _transferManager(voting, adminExecutor, sdvt, keccak256("STAKING_ROUTER_ROLE"));
        /// MANAGE_NODE_OPERATOR_ROLE
        _transferManager(voting, adminExecutor, sdvt, keccak256("MANAGE_NODE_OPERATOR_ROLE"));
        /// SET_NODE_OPERATOR_LIMIT_ROLE
        _transferManager(voting, adminExecutor, sdvt, keccak256("SET_NODE_OPERATOR_LIMIT_ROLE"));

        vm.stopPrank();
    }

    function _transferRole(address _from, address _to, address _app, bytes32 _role) internal {
        assertTrue(_lido.acl.hasPermission(_from, _app, _role));
        assertFalse(_lido.acl.hasPermission(_to, _app, _role));

        vm.expectEmit();
        emit IAragonACL.SetPermission(_to, _app, _role, true);
        _lido.acl.grantPermission(_to, _app, _role);
        assertTrue(_lido.acl.hasPermission(_to, _app, _role));

        vm.expectEmit();
        emit IAragonACL.SetPermission(_from, _app, _role, false);
        _lido.acl.revokePermission(_from, _app, _role);
        assertFalse(_lido.acl.hasPermission(_from, _app, _role));
    }

    function _transferManager(address _from, address _to, address _app, bytes32 _role) internal {
        assertEq(_lido.acl.getPermissionManager(_app, _role), _from);

        vm.expectEmit();
        emit IAragonACL.ChangePermissionManager(_app, _role, _to);
        _lido.acl.setPermissionManager(_to, _app, _role);

        assertEq(_lido.acl.getPermissionManager(_app, _role), _to);
    }
}
