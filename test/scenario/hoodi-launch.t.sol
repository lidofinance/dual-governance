// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    Durations,
    Timestamps,
    ContractsDeployment,
    DGScenarioTestSetup,
    HOODI_CHAIN_ID
} from "test/utils/integration-tests.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";

import {TimeConstraints} from "scripts/launch/TimeConstraints.sol";
import {DGLaunchStateVerifier} from "scripts/launch/DGLaunchStateVerifier.sol";
import {LaunchOmnibusHoodi} from "scripts/launch/hoodi/LaunchOmnibusHoodi.sol";
import {LidoAddressesHoodi} from "scripts/launch/hoodi/LidoAddressesHoodi.sol";
import {RolesValidatorHoodi} from "scripts/launch/hoodi/RolesValidatorHoodi.sol";

import {IWithdrawalVaultProxy} from "scripts/launch/interfaces/IWithdrawalVaultProxy.sol";
import {IOZ} from "scripts/launch/interfaces/IOZ.sol";
import {IACL} from "scripts/launch/interfaces/IACL.sol";

contract HoodiLaunch is DGScenarioTestSetup, LidoAddressesHoodi {
    using LidoUtils for LidoUtils.Context;

    LaunchOmnibusHoodi internal launchOmnibus;

    bytes32 internal STAKING_CONTROL_ROLE = keccak256("STAKING_CONTROL_ROLE");
    bytes32 internal RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 internal PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 internal UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE = keccak256("UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE");
    bytes32 internal STAKING_PAUSE_ROLE = keccak256("STAKING_PAUSE_ROLE");
    bytes32 internal APP_MANAGER_ROLE = keccak256("APP_MANAGER_ROLE");
    bytes32 internal REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");
    bytes32 internal REGISTRY_ADD_EXECUTOR_ROLE = keccak256("REGISTRY_ADD_EXECUTOR_ROLE");
    bytes32 internal MANAGE_SIGNING_KEYS = keccak256("MANAGE_SIGNING_KEYS");
    bytes32 internal STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE");
    bytes32 internal SET_NODE_OPERATOR_LIMIT_ROLE = keccak256("SET_NODE_OPERATOR_LIMIT_ROLE");
    bytes32 internal MANAGE_NODE_OPERATOR_ROLE = keccak256("MANAGE_NODE_OPERATOR_ROLE");
    bytes32 internal CREATE_PERMISSIONS_ROLE = keccak256("CREATE_PERMISSIONS_ROLE");
    bytes32 internal RUN_SCRIPT_ROLE = keccak256("RUN_SCRIPT_ROLE");
    bytes32 internal EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    bytes32 internal DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 internal REVOKE_VESTINGS_ROLE = keccak256("REVOKE_VESTINGS_ROLE");
    bytes32 internal BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 internal ISSUE_ROLE = keccak256("ISSUE_ROLE");
    bytes32 internal ADD_TOKEN_TO_ALLOWED_LIST_ROLE = keccak256("ADD_TOKEN_TO_ALLOWED_LIST_ROLE");
    bytes32 internal REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE = keccak256("REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE");
    bytes32 internal UNSAFELY_MODIFY_VOTE_TIME_ROLE = keccak256("UNSAFELY_MODIFY_VOTE_TIME_ROLE");
    bytes32 internal CHANGE_PERIOD_ROLE = keccak256("CHANGE_PERIOD_ROLE");
    bytes32 internal CHANGE_BUDGETS_ROLE = keccak256("CHANGE_BUDGETS_ROLE");

    uint256 internal constant VOTE_EXECUTION_BLOCK = 350291;

    function setUp() external {
        string memory hoodiRpcUrl = vm.envOr("HOODI_RPC_URL", string(""));
        if (bytes(hoodiRpcUrl).length == 0) {
            vm.skip(true, "Skipping Hoodi launch test, no HOODI_RPC_URL provided");
        }
        _deployDGSetup({isEmergencyProtectionEnabled: true, chainId: HOODI_CHAIN_ID});
        if (block.number >= VOTE_EXECUTION_BLOCK) {
            vm.skip(true, "Skipping launch test. Vote already executed.");
        }
    }

    function testFork_HoodiLaunch_HappyPath() external {
        {
            // Initialize all necessary contracts for the launch

            TimeConstraints timeConstraints = new TimeConstraints();
            DGLaunchStateVerifier launchVerifier = new DGLaunchStateVerifier(
                DGLaunchStateVerifier.ConstructorParams({
                    timelock: address(_dgDeployedContracts.timelock),
                    dualGovernance: address(_dgDeployedContracts.dualGovernance),
                    emergencyGovernance: address(_dgDeployedContracts.emergencyGovernance),
                    emergencyActivationCommittee: _dgDeployedContracts.timelock.getEmergencyActivationCommittee(),
                    emergencyExecutionCommittee: _dgDeployedContracts.timelock.getEmergencyExecutionCommittee(),
                    emergencyProtectionEndDate: _dgDeployedContracts.timelock.getEmergencyProtectionDetails()
                        .emergencyProtectionEndsAfter,
                    emergencyModeDuration: _dgDeployedContracts.timelock.getEmergencyProtectionDetails()
                        .emergencyModeDuration,
                    proposalsCount: 1
                })
            );

            RolesValidatorHoodi rolesValidator = new RolesValidatorHoodi(
                address(_dgDeployedContracts.adminExecutor), address(_dgDeployedContracts.resealManager)
            );
            launchOmnibus = new LaunchOmnibusHoodi(
                address(_dgDeployedContracts.dualGovernance),
                address(_dgDeployedContracts.adminExecutor),
                address(_dgDeployedContracts.resealManager),
                address(rolesValidator),
                address(launchVerifier),
                address(timeConstraints)
            );
        }

        {
            // Pre-launch roles and permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, STAKING_CONTROL_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, RESUME_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, PAUSE_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, STAKING_PAUSE_ROLE) == VOTING);

            vm.assertTrue(IACL(ACL).hasPermission(VOTING, LIDO, STAKING_CONTROL_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, LIDO, RESUME_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, LIDO, PAUSE_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, LIDO, UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, LIDO, STAKING_PAUSE_ROLE));

            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, STAKING_CONTROL_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, RESUME_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, PAUSE_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, STAKING_PAUSE_ROLE));

            // DAOKernel permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(KERNEL, APP_MANAGER_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, KERNEL, APP_MANAGER_ROLE));

            vm.assertFalse(IACL(ACL).hasPermission(AGENT, KERNEL, APP_MANAGER_ROLE));

            // Voting permissions checks
            vm.assertFalse(IACL(ACL).getPermissionManager(VOTING, UNSAFELY_MODIFY_VOTE_TIME_ROLE) == VOTING);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, VOTING, UNSAFELY_MODIFY_VOTE_TIME_ROLE));

            // TokenManager permissions checks
            vm.assertFalse(IACL(ACL).getPermissionManager(TOKEN_MANAGER, MINT_ROLE) == VOTING);
            vm.assertFalse(IACL(ACL).getPermissionManager(TOKEN_MANAGER, REVOKE_VESTINGS_ROLE) == VOTING);
            vm.assertFalse(IACL(ACL).getPermissionManager(TOKEN_MANAGER, BURN_ROLE) == VOTING);
            vm.assertFalse(IACL(ACL).getPermissionManager(TOKEN_MANAGER, ISSUE_ROLE) == VOTING);

            vm.assertFalse(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, MINT_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, REVOKE_VESTINGS_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, BURN_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, ISSUE_ROLE));

            // Finance permissions checks
            vm.assertFalse(IACL(ACL).getPermissionManager(FINANCE, CHANGE_PERIOD_ROLE) == VOTING);
            vm.assertFalse(IACL(ACL).getPermissionManager(FINANCE, CHANGE_BUDGETS_ROLE) == VOTING);

            vm.assertFalse(IACL(ACL).hasPermission(VOTING, FINANCE, CHANGE_PERIOD_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, FINANCE, CHANGE_BUDGETS_ROLE));

            // EVMScriptRegistry permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE));

            vm.assertFalse(IACL(ACL).hasPermission(AGENT, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE));

            // CuratedModule permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, STAKING_ROUTER_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, MANAGE_SIGNING_KEYS) == VOTING);

            vm.assertFalse(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, STAKING_ROUTER_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, MANAGE_SIGNING_KEYS));

            vm.assertFalse(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, STAKING_ROUTER_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, MANAGE_SIGNING_KEYS));

            // Simple DVT Module permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, STAKING_ROUTER_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE) == VOTING);

            vm.assertTrue(IACL(ACL).hasPermission(VOTING, SDVT_MODULE, STAKING_ROUTER_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));

            // ACL permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(ACL, CREATE_PERMISSIONS_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, ACL, CREATE_PERMISSIONS_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, ACL, CREATE_PERMISSIONS_ROLE));

            // Agent permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(AGENT, RUN_SCRIPT_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(AGENT, EXECUTE_ROLE) == VOTING);

            vm.assertTrue(IACL(ACL).hasPermission(VOTING, AGENT, RUN_SCRIPT_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, AGENT, EXECUTE_ROLE));

            vm.assertFalse(IACL(ACL).hasPermission(address(_dgDeployedContracts.adminExecutor), AGENT, RUN_SCRIPT_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(address(_dgDeployedContracts.adminExecutor), AGENT, EXECUTE_ROLE));

            vm.assertFalse(IACL(ACL).hasPermission(AGENT_MANAGER, AGENT, RUN_SCRIPT_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT_MANAGER, AGENT, EXECUTE_ROLE));

            // WithdrawalQueue and VEBO permissions checks
            vm.assertFalse(IOZ(WITHDRAWAL_QUEUE).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertFalse(IOZ(WITHDRAWAL_QUEUE).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertFalse(IOZ(VEBO).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertFalse(IOZ(VEBO).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // AllowedTokensRegistry permissions checks
            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(DEFAULT_ADMIN_ROLE, AGENT));
            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(ADD_TOKEN_TO_ALLOWED_LIST_ROLE, AGENT));
            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, AGENT));

            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(DEFAULT_ADMIN_ROLE, VOTING));
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(ADD_TOKEN_TO_ALLOWED_LIST_ROLE, VOTING));
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, VOTING));

            // Verify current admin of WithdrawalVault
            address currentAdmin = IWithdrawalVaultProxy(WITHDRAWAL_VAULT).proxy_getAdmin();
            vm.assertEq(currentAdmin, VOTING);
        }

        {
            // Create and pass the aragon vote to launch DualGovernance

            uint256 voteId = _lido.adoptVote("Activate Dual Governance", launchOmnibus.getEVMScript());

            _lido.executeVote(voteId);
            (, bool executed,,,,,,,,,) = _lido.voting.getVote(voteId);
            assertTrue(executed);
        }

        {
            // After aragon voting checks
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, STAKING_CONTROL_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, RESUME_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, PAUSE_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, STAKING_PAUSE_ROLE) == AGENT);

            vm.assertFalse(IACL(ACL).hasPermission(VOTING, LIDO, STAKING_CONTROL_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, LIDO, RESUME_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, LIDO, PAUSE_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, LIDO, UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, LIDO, STAKING_PAUSE_ROLE));

            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, STAKING_CONTROL_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, RESUME_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, PAUSE_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, LIDO, STAKING_PAUSE_ROLE));

            // DAOKernel permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(KERNEL, APP_MANAGER_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, KERNEL, APP_MANAGER_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, KERNEL, APP_MANAGER_ROLE));

            // Voting permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(VOTING, UNSAFELY_MODIFY_VOTE_TIME_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, VOTING, UNSAFELY_MODIFY_VOTE_TIME_ROLE));

            // TokenManager permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(TOKEN_MANAGER, MINT_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(TOKEN_MANAGER, REVOKE_VESTINGS_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(TOKEN_MANAGER, BURN_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(TOKEN_MANAGER, ISSUE_ROLE) == VOTING);

            vm.assertTrue(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, MINT_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, REVOKE_VESTINGS_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, BURN_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, ISSUE_ROLE));

            // Finance permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(FINANCE, CHANGE_PERIOD_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(FINANCE, CHANGE_BUDGETS_ROLE) == VOTING);

            vm.assertTrue(IACL(ACL).hasPermission(VOTING, FINANCE, CHANGE_PERIOD_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, FINANCE, CHANGE_BUDGETS_ROLE));

            // EVMScriptRegistry permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE));

            // CuratedModule permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, STAKING_ROUTER_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, MANAGE_SIGNING_KEYS) == AGENT);

            vm.assertFalse(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, STAKING_ROUTER_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, MANAGE_SIGNING_KEYS));

            vm.assertFalse(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, STAKING_ROUTER_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, MANAGE_SIGNING_KEYS));

            // Simple DVT Module permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(SDVT_MODULE, STAKING_ROUTER_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE) == AGENT);

            vm.assertFalse(IACL(ACL).hasPermission(VOTING, SDVT_MODULE, STAKING_ROUTER_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));

            vm.assertTrue(IACL(ACL).hasPermission(AGENT, SDVT_MODULE, STAKING_ROUTER_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));

            // ACL permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(ACL, CREATE_PERMISSIONS_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, ACL, CREATE_PERMISSIONS_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(AGENT, ACL, CREATE_PERMISSIONS_ROLE));

            // Agent permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(AGENT, RUN_SCRIPT_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(AGENT, EXECUTE_ROLE) == AGENT);

            vm.assertTrue(IACL(ACL).hasPermission(address(_dgDeployedContracts.adminExecutor), AGENT, RUN_SCRIPT_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(address(_dgDeployedContracts.adminExecutor), AGENT, EXECUTE_ROLE));

            vm.assertTrue(IACL(ACL).hasPermission(AGENT_MANAGER, AGENT, RUN_SCRIPT_ROLE));

            // AllowedTokensRegistry permissions checks
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(DEFAULT_ADMIN_ROLE, AGENT));
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(ADD_TOKEN_TO_ALLOWED_LIST_ROLE, AGENT));
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, AGENT));

            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(DEFAULT_ADMIN_ROLE, VOTING));
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(ADD_TOKEN_TO_ALLOWED_LIST_ROLE, AGENT));
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, AGENT));

            // WithdrawalQueue and VEBO permissions checks
            vm.assertTrue(IOZ(WITHDRAWAL_QUEUE).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertTrue(IOZ(WITHDRAWAL_QUEUE).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertTrue(IOZ(VEBO).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertTrue(IOZ(VEBO).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // Verify new admin of WithdrawalVault
            address currentAdmin = IWithdrawalVaultProxy(WITHDRAWAL_VAULT).proxy_getAdmin();
            vm.assertEq(currentAdmin, AGENT);
        }

        {
            // Pass through the DualGovernance for launch
            uint256 dgProposalId = _dgDeployedContracts.timelock.getProposalsCount();

            vm.assertFalse(_dgDeployedContracts.timelock.canSchedule(dgProposalId));

            _wait(_dgDeployedContracts.timelock.getAfterSubmitDelay());

            vm.assertTrue(_dgDeployedContracts.timelock.canSchedule(dgProposalId));

            _dgDeployedContracts.dualGovernance.scheduleProposal(dgProposalId);
            _wait(_dgDeployedContracts.timelock.getAfterScheduleDelay());

            // Execute the proposal once it's ready
            vm.assertTrue(_dgDeployedContracts.timelock.canExecute(dgProposalId));
            _dgDeployedContracts.timelock.execute(dgProposalId);
        }

        {
            // After launch roles and permissions checks
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, AGENT, RUN_SCRIPT_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, AGENT, EXECUTE_ROLE));

            vm.assertTrue(IACL(ACL).hasPermission(AGENT_MANAGER, AGENT, RUN_SCRIPT_ROLE));
        }
    }
}
