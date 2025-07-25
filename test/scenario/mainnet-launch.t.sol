// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    Durations,
    Duration,
    Timestamps,
    Timestamp,
    ContractsDeployment,
    DGScenarioTestSetup,
    MAINNET_CHAIN_ID
} from "test/utils/integration-tests.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";

import {OmnibusBase} from "scripts/utils/OmnibusBase.sol";
import {TimeConstraints} from "scripts/launch/TimeConstraints.sol";
import {DGLaunchStateVerifier} from "scripts/launch/DGLaunchStateVerifier.sol";
import {DGLaunchOmnibusMainnet} from "scripts/launch/mainnet/DGLaunchOmnibusMainnet.sol";
import {LidoAddressesMainnet} from "scripts/launch/mainnet/LidoAddressesMainnet.sol";
import {DGRolesValidatorMainnet} from "scripts/launch/mainnet/DGRolesValidatorMainnet.sol";

import {IWithdrawalVaultProxy} from "scripts/launch/interfaces/IWithdrawalVaultProxy.sol";
import {IOZ} from "scripts/launch/interfaces/IOZ.sol";
import {IACL} from "scripts/launch/interfaces/IACL.sol";
import {IInsuranceFund} from "scripts/launch/interfaces/IInsuranceFund.sol";
import {TimeConstraints} from "scripts/launch/TimeConstraints.sol";

contract MainnetLaunch is DGScenarioTestSetup, LidoAddressesMainnet {
    using LidoUtils for LidoUtils.Context;

    DGLaunchOmnibusMainnet internal launchOmnibus;

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
    bytes32 internal CHANGE_PERIOD_ROLE = keccak256("CHANGE_PERIOD_ROLE");
    bytes32 internal CHANGE_BUDGETS_ROLE = keccak256("CHANGE_BUDGETS_ROLE");
    uint256 internal constant VOTE_EXECUTION_BLOCK = 22817714;

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: true, chainId: MAINNET_CHAIN_ID});
        if (block.number >= VOTE_EXECUTION_BLOCK) {
            vm.skip(true, "Skipping launch test. Vote already executed.");
        }

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
                emergencyModeDuration: _dgDeployedContracts.timelock.getEmergencyProtectionDetails().emergencyModeDuration,
                proposalsCount: 1
            })
        );

        DGRolesValidatorMainnet rolesValidator = new DGRolesValidatorMainnet(
            address(_dgDeployedContracts.adminExecutor), address(_dgDeployedContracts.resealManager)
        );
        launchOmnibus = new DGLaunchOmnibusMainnet(
            address(_dgDeployedContracts.dualGovernance),
            address(_dgDeployedContracts.adminExecutor),
            address(_dgDeployedContracts.resealManager),
            address(rolesValidator),
            address(launchVerifier),
            address(timeConstraints)
        );
    }

    function testFork_MainnetLaunch_HappyPath() external {
        {
            // Pre-launch roles and permissions checks
            // Lido permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, STAKING_CONTROL_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, LIDO, STAKING_CONTROL_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, RESUME_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, LIDO, RESUME_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, PAUSE_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, LIDO, PAUSE_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, STAKING_PAUSE_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, LIDO, STAKING_PAUSE_ROLE));

            // DAOKernel permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(KERNEL, APP_MANAGER_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, KERNEL, APP_MANAGER_ROLE));

            // TokenManager permissions checks
            vm.assertFalse(IACL(ACL).getPermissionManager(TOKEN_MANAGER, MINT_ROLE) == VOTING);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, MINT_ROLE));

            vm.assertFalse(IACL(ACL).getPermissionManager(TOKEN_MANAGER, REVOKE_VESTINGS_ROLE) == VOTING);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, REVOKE_VESTINGS_ROLE));

            // Finance permissions checks
            vm.assertFalse(IACL(ACL).getPermissionManager(FINANCE, CHANGE_PERIOD_ROLE) == VOTING);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, FINANCE, CHANGE_PERIOD_ROLE));

            vm.assertFalse(IACL(ACL).getPermissionManager(FINANCE, CHANGE_BUDGETS_ROLE) == VOTING);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, FINANCE, CHANGE_BUDGETS_ROLE));

            // EVMScriptRegistry permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE));

            // CuratedModule permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, STAKING_ROUTER_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(STAKING_ROUTER, CURATED_MODULE, STAKING_ROUTER_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(EVM_SCRIPT_EXECUTOR, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, MANAGE_SIGNING_KEYS) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, MANAGE_SIGNING_KEYS));

            // SimpleDVT Module permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(SDVT_MODULE, STAKING_ROUTER_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(STAKING_ROUTER, SDVT_MODULE, STAKING_ROUTER_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(EVM_SCRIPT_EXECUTOR, SDVT_MODULE, STAKING_ROUTER_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(EVM_SCRIPT_EXECUTOR, SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(EVM_SCRIPT_EXECUTOR, SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));

            // ACL permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(ACL, CREATE_PERMISSIONS_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, ACL, CREATE_PERMISSIONS_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(AGENT, ACL, CREATE_PERMISSIONS_ROLE));

            // Agent permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(AGENT, RUN_SCRIPT_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, AGENT, RUN_SCRIPT_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(address(_dgDeployedContracts.adminExecutor), AGENT, RUN_SCRIPT_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(AGENT, EXECUTE_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, AGENT, EXECUTE_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(address(_dgDeployedContracts.adminExecutor), AGENT, EXECUTE_ROLE));

            // WithdrawalQueue and VEBO permissions checks
            vm.assertFalse(IOZ(WITHDRAWAL_QUEUE).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertTrue(IOZ(WITHDRAWAL_QUEUE).hasRole(PAUSE_ROLE, ORACLES_GATE_SEAL));

            vm.assertFalse(IOZ(WITHDRAWAL_QUEUE).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            vm.assertFalse(IOZ(VEBO).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertTrue(IOZ(VEBO).hasRole(PAUSE_ROLE, ORACLES_GATE_SEAL));

            vm.assertFalse(IOZ(VEBO).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // CSModule permissions checks
            vm.assertTrue(IOZ(CS_MODULE).hasRole(PAUSE_ROLE, CS_GATE_SEAL));
            vm.assertFalse(IOZ(CS_MODULE).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));

            vm.assertFalse(IOZ(CS_MODULE).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // CSAccounting permissions checks
            vm.assertTrue(IOZ(CS_ACCOUNTING).hasRole(PAUSE_ROLE, CS_GATE_SEAL));
            vm.assertFalse(IOZ(CS_ACCOUNTING).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));

            vm.assertFalse(IOZ(CS_ACCOUNTING).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // CSFeeOracle permissions checks
            vm.assertTrue(IOZ(CS_FEE_ORACLE).hasRole(PAUSE_ROLE, CS_GATE_SEAL));
            vm.assertFalse(IOZ(CS_FEE_ORACLE).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));

            vm.assertFalse(IOZ(CS_FEE_ORACLE).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // AllowedTokensRegistry permissions checks
            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(DEFAULT_ADMIN_ROLE, AGENT));
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(DEFAULT_ADMIN_ROLE, VOTING));
            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(DEFAULT_ADMIN_ROLE, AGENT));

            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(ADD_TOKEN_TO_ALLOWED_LIST_ROLE, AGENT));
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(ADD_TOKEN_TO_ALLOWED_LIST_ROLE, VOTING));
            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(ADD_TOKEN_TO_ALLOWED_LIST_ROLE, AGENT));

            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, AGENT));
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, VOTING));
            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, AGENT));

            // Verify current admin of WithdrawalVault
            address currentAdmin = IWithdrawalVaultProxy(WITHDRAWAL_VAULT).proxy_getAdmin();
            vm.assertEq(currentAdmin, VOTING);

            // Verify current owner of InsuranceFund
            address insuranceFundOwner = IInsuranceFund(INSURANCE_FUND).owner();
            vm.assertEq(insuranceFundOwner, AGENT);
        }

        {
            // Create and pass the aragon vote to launch DualGovernance
            uint256 testDay = block.timestamp - (block.timestamp % 1 days) + 13 hours;
            vm.warp(testDay);

            uint256 voteId = _lido.adoptVote("Activate Dual Governance", launchOmnibus.getEVMScript());
            _lido.executeVote(voteId);
            (, bool executed,,,,,,,,,) = _lido.voting.getVote(voteId);
            assertTrue(executed);
        }

        {
            // After aragon voting checks
            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, STAKING_CONTROL_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, LIDO, STAKING_CONTROL_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, RESUME_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, LIDO, RESUME_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, PAUSE_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, LIDO, PAUSE_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(LIDO, STAKING_PAUSE_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, LIDO, STAKING_PAUSE_ROLE));

            // DAOKernel permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(KERNEL, APP_MANAGER_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, KERNEL, APP_MANAGER_ROLE));

            // TokenManager permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(TOKEN_MANAGER, MINT_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(TOKEN_MANAGER, REVOKE_VESTINGS_ROLE) == VOTING);

            vm.assertTrue(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, MINT_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, TOKEN_MANAGER, REVOKE_VESTINGS_ROLE));

            // Finance permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(FINANCE, CHANGE_PERIOD_ROLE) == VOTING);
            vm.assertTrue(IACL(ACL).getPermissionManager(FINANCE, CHANGE_BUDGETS_ROLE) == VOTING);

            vm.assertTrue(IACL(ACL).hasPermission(VOTING, FINANCE, CHANGE_PERIOD_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(VOTING, FINANCE, CHANGE_BUDGETS_ROLE));

            // EVMScriptRegistry permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE));

            // CuratedModule permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, STAKING_ROUTER_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).hasPermission(STAKING_ROUTER, CURATED_MODULE, STAKING_ROUTER_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).hasPermission(AGENT, CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).hasPermission(EVM_SCRIPT_EXECUTOR, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(CURATED_MODULE, MANAGE_SIGNING_KEYS) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, CURATED_MODULE, MANAGE_SIGNING_KEYS));

            // Simple DVT Module permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(SDVT_MODULE, STAKING_ROUTER_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).hasPermission(STAKING_ROUTER, SDVT_MODULE, STAKING_ROUTER_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(EVM_SCRIPT_EXECUTOR, SDVT_MODULE, STAKING_ROUTER_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).hasPermission(EVM_SCRIPT_EXECUTOR, SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE));

            vm.assertTrue(IACL(ACL).getPermissionManager(SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).hasPermission(EVM_SCRIPT_EXECUTOR, SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE));

            // ACL permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(ACL, CREATE_PERMISSIONS_ROLE) == AGENT);
            vm.assertFalse(IACL(ACL).hasPermission(VOTING, ACL, CREATE_PERMISSIONS_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(AGENT, ACL, CREATE_PERMISSIONS_ROLE));

            // Agent permissions checks
            vm.assertTrue(IACL(ACL).getPermissionManager(AGENT, RUN_SCRIPT_ROLE) == AGENT);
            vm.assertTrue(IACL(ACL).getPermissionManager(AGENT, EXECUTE_ROLE) == AGENT);

            vm.assertTrue(IACL(ACL).hasPermission(address(_dgDeployedContracts.adminExecutor), AGENT, RUN_SCRIPT_ROLE));
            vm.assertTrue(IACL(ACL).hasPermission(address(_dgDeployedContracts.adminExecutor), AGENT, EXECUTE_ROLE));

            // WithdrawalQueue and VEBO permissions checks
            vm.assertTrue(IOZ(WITHDRAWAL_QUEUE).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertTrue(IOZ(WITHDRAWAL_QUEUE).hasRole(PAUSE_ROLE, ORACLES_GATE_SEAL));

            vm.assertTrue(IOZ(WITHDRAWAL_QUEUE).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            vm.assertTrue(IOZ(VEBO).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));
            vm.assertTrue(IOZ(VEBO).hasRole(PAUSE_ROLE, ORACLES_GATE_SEAL));

            vm.assertTrue(IOZ(VEBO).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // CSModule permissions checks
            vm.assertTrue(IOZ(CS_MODULE).hasRole(PAUSE_ROLE, CS_GATE_SEAL));
            vm.assertTrue(IOZ(CS_MODULE).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));

            vm.assertTrue(IOZ(CS_MODULE).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // CSAccounting permissions checks
            vm.assertTrue(IOZ(CS_ACCOUNTING).hasRole(PAUSE_ROLE, CS_GATE_SEAL));
            vm.assertTrue(IOZ(CS_ACCOUNTING).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));

            vm.assertTrue(IOZ(CS_ACCOUNTING).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // CSFee Oracle permissions checks
            vm.assertTrue(IOZ(CS_FEE_ORACLE).hasRole(PAUSE_ROLE, CS_GATE_SEAL));
            vm.assertTrue(IOZ(CS_FEE_ORACLE).hasRole(PAUSE_ROLE, address(_dgDeployedContracts.resealManager)));

            vm.assertTrue(IOZ(CS_FEE_ORACLE).hasRole(RESUME_ROLE, address(_dgDeployedContracts.resealManager)));

            // AllowedTokensRegistry permissions checks
            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(DEFAULT_ADMIN_ROLE, AGENT));
            vm.assertTrue(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(DEFAULT_ADMIN_ROLE, VOTING));

            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(ADD_TOKEN_TO_ALLOWED_LIST_ROLE, AGENT));

            vm.assertFalse(IOZ(ALLOWED_TOKENS_REGISTRY).hasRole(REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE, AGENT));

            // Verify new admin of WithdrawalVault
            address currentAdmin = IWithdrawalVaultProxy(WITHDRAWAL_VAULT).proxy_getAdmin();
            vm.assertEq(currentAdmin, AGENT);

            // Verify InsuranceFund owner has been changed to VOTING
            address insuranceFundOwner = IInsuranceFund(INSURANCE_FUND).owner();
            vm.assertEq(insuranceFundOwner, VOTING);
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
        }
    }

    function test_MainnetLaunch_RevertOn_ExpiredOmnibus() external {
        Timestamp expirationTimestamp = launchOmnibus.OMNIBUS_EXPIRATION_TIMESTAMP();

        uint256 voteId = _lido.adoptVote("Activate Dual Governance", launchOmnibus.getEVMScript());

        vm.warp(expirationTimestamp.toSeconds() + 1);

        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.TimestampPassed.selector, expirationTimestamp));
        _lido.executeVote(voteId);
    }

    function test_MainnetLaunch_RevertOn_ExpiredDGProposal() external {
        Timestamp expirationTimestamp = launchOmnibus.DG_PROPOSAL_EXPIRATION_TIMESTAMP();

        uint256 voteId = _lido.adoptVote("Activate Dual Governance", launchOmnibus.getEVMScript());
        _lido.executeVote(voteId);

        uint256 dgProposalId = _dgDeployedContracts.timelock.getProposalsCount();

        _wait(_dgDeployedContracts.timelock.getAfterSubmitDelay());

        _dgDeployedContracts.dualGovernance.scheduleProposal(dgProposalId);

        _wait(_dgDeployedContracts.timelock.getAfterScheduleDelay());

        vm.warp(expirationTimestamp.toSeconds() + 1);

        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.TimestampPassed.selector, expirationTimestamp));
        _dgDeployedContracts.timelock.execute(dgProposalId);
    }

    function test_MainnetLaunch_RevertOn_OutsideExecutionHours() external {
        Duration fromDayTime = launchOmnibus.DG_PROPOSAL_EXECUTABLE_FROM_DAY_TIME();
        Duration tillDayTime = launchOmnibus.DG_PROPOSAL_EXECUTABLE_TILL_DAY_TIME();

        uint256 voteId = _lido.adoptVote("Activate Dual Governance", launchOmnibus.getEVMScript());
        _lido.executeVote(voteId);

        uint256 dgProposalId = _dgDeployedContracts.timelock.getProposalsCount();
        _wait(_dgDeployedContracts.timelock.getAfterSubmitDelay());
        _dgDeployedContracts.dualGovernance.scheduleProposal(dgProposalId);
        _wait(_dgDeployedContracts.timelock.getAfterScheduleDelay());

        uint256 testDay = block.timestamp + 1 days - (block.timestamp % 1 days);
        vm.warp(testDay + fromDayTime.toSeconds() - 1);

        Duration currentDayTime = Durations.from(block.timestamp % 1 days);

        vm.expectRevert(
            abi.encodeWithSelector(TimeConstraints.DayTimeOutOfRange.selector, currentDayTime, fromDayTime, tillDayTime)
        );
        _dgDeployedContracts.timelock.execute(dgProposalId);

        vm.warp(testDay + tillDayTime.toSeconds() + 1);

        currentDayTime = Durations.from(block.timestamp % 1 days);

        vm.expectRevert(
            abi.encodeWithSelector(TimeConstraints.DayTimeOutOfRange.selector, currentDayTime, fromDayTime, tillDayTime)
        );
        _dgDeployedContracts.timelock.execute(dgProposalId);
    }

    function test_getEVMScript_NoEmptyItems() external view {
        OmnibusBase.VoteItem[] memory voteItems = launchOmnibus.getVoteItems();

        for (uint256 i = 0; i < voteItems.length; i++) {
            vm.assertTrue(bytes(voteItems[i].description).length != 0);
            vm.assertTrue(voteItems[i].call.to != address(0));
            vm.assertTrue(voteItems[i].call.data.length > 0);
        }
    }
}
