// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/Strings.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {IGovernance} from "contracts/interfaces/IGovernance.sol";
import {EvmScriptUtils} from "scripts/utils/evm-script-utils.sol";

import {Omnibus} from "./Omnibus.sol";
import {VoteBuilder} from "./VoteBuilder.sol";
import {IOwnable} from "./interfaces/IOwnable.sol";
import {IWithdrawalVaultProxy} from "./interfaces/IWithdrawalVaultProxy.sol";
import {IRolesValidator, IDGLaunchVerifier, ITimeConstraints} from "./interfaces/utils.sol";
import {LidoMainnetAddresses} from "../LidoMainnetAddresses.sol";

contract DGUpgradeMainnet is Omnibus {
    using VoteBuilder for VoteBuilder.State;

    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant STAKING_CONTROL_ROLE = keccak256("STAKING_CONTROL_ROLE");
    bytes32 public constant STAKING_PAUSE_ROLE = keccak256("STAKING_PAUSE_ROLE");
    bytes32 public constant APP_MANAGER_ROLE = keccak256("APP_MANAGER_ROLE");
    bytes32 public constant REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");
    bytes32 public constant REGISTRY_ADD_EXECUTOR_ROLE = keccak256("REGISTRY_ADD_EXECUTOR_ROLE");
    bytes32 public constant SET_NODE_OPERATOR_LIMIT_ROLE = keccak256("SET_NODE_OPERATOR_LIMIT_ROLE");
    bytes32 public constant MANAGE_SIGNING_KEYS = keccak256("MANAGE_SIGNING_KEYS");
    bytes32 public constant CREATE_PERMISSIONS_ROLE = keccak256("CREATE_PERMISSIONS_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant ADD_TOKEN_TO_ALLOWED_LIST_ROLE = keccak256("ADD_TOKEN_TO_ALLOWED_LIST_ROLE");
    bytes32 public constant REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE = keccak256("REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE");
    bytes32 public constant RUN_SCRIPT_ROLE = keccak256("RUN_SCRIPT_ROLE");
    bytes32 public constant EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    bytes32 public constant STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE");
    bytes32 public constant MANAGE_NODE_OPERATOR_ROLE = keccak256("MANAGE_NODE_OPERATOR_ROLE");
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant REVOKE_VESTINGS_ROLE = keccak256("REVOKE_VESTINGS_ROLE");
    bytes32 public constant CHANGE_PERIOD_ROLE = keccak256("CHANGE_PERIOD_ROLE");
    bytes32 public constant CHANGE_BUDGETS_ROLE = keccak256("CHANGE_BUDGETS_ROLE");

    address public immutable DUAL_GOVERNANCE;
    address public immutable DUAL_GOVERNANCE_EXECUTOR;
    address public immutable RESEAL_MANAGER;
    address public immutable ROLES_VALIDATOR;
    address public immutable LAUNCH_VERIFIER;

    constructor(
        address dualGovernance,
        address dualGovernanceExecutor,
        address resealManager,
        address rolesValidator,
        address launchVerifier
    ) {
        DUAL_GOVERNANCE = dualGovernance;
        DUAL_GOVERNANCE_EXECUTOR = dualGovernanceExecutor;
        RESEAL_MANAGER = resealManager;
        ROLES_VALIDATOR = rolesValidator;
        LAUNCH_VERIFIER = launchVerifier;
    }

    function getVoteItems() external view override returns (VoteItem[] memory) {
        VoteBuilder.State memory builder = VoteBuilder.create(getVoteItemsCount());

        // Lido
        builder.add(
            "Revoke STAKING_CONTROL_ROLE permission from Voting on Lido",
            _votingCall(
                _aclRevokePermission(LidoMainnetAddresses.VOTING, LidoMainnetAddresses.LIDO, STAKING_CONTROL_ROLE)
            )
        );

        builder.add(
            "Set STAKING_CONTROL_ROLE manager to Agent on Lido",
            _votingCall(
                _aclSetPermissionManager(LidoMainnetAddresses.AGENT, LidoMainnetAddresses.LIDO, STAKING_CONTROL_ROLE)
            )
        );

        builder.add(
            "Revoke RESUME_ROLE permission from Voting on Lido",
            _votingCall(_aclRevokePermission(LidoMainnetAddresses.VOTING, LidoMainnetAddresses.LIDO, RESUME_ROLE))
        );

        builder.add(
            "Set RESUME_ROLE manager to Agent on Lido",
            _votingCall(_aclSetPermissionManager(LidoMainnetAddresses.AGENT, LidoMainnetAddresses.LIDO, RESUME_ROLE))
        );

        builder.add(
            "Revoke PAUSE_ROLE permission from Voting on Lido",
            _votingCall(_aclRevokePermission(LidoMainnetAddresses.VOTING, LidoMainnetAddresses.LIDO, PAUSE_ROLE))
        );

        builder.add(
            "Set PAUSE_ROLE manager to Agent on Lido",
            _votingCall(_aclSetPermissionManager(LidoMainnetAddresses.AGENT, LidoMainnetAddresses.LIDO, PAUSE_ROLE))
        );

        builder.add(
            "Revoke STAKING_PAUSE_ROLE permission from Voting on Lido",
            _votingCall(
                _aclRevokePermission(LidoMainnetAddresses.VOTING, LidoMainnetAddresses.LIDO, STAKING_PAUSE_ROLE)
            )
        );

        builder.add(
            "Set STAKING_PAUSE_ROLE manager to Agent on Lido",
            _votingCall(
                _aclSetPermissionManager(LidoMainnetAddresses.AGENT, LidoMainnetAddresses.LIDO, STAKING_PAUSE_ROLE)
            )
        );

        // Kernel
        builder.add(
            "Revoke APP_MANAGER_ROLE permission from Voting on Kernel",
            _votingCall(
                _aclRevokePermission(LidoMainnetAddresses.VOTING, LidoMainnetAddresses.KERNEL, APP_MANAGER_ROLE)
            )
        );

        builder.add(
            "Set APP_MANAGER_ROLE manager to Agent on Kernel",
            _votingCall(
                _aclSetPermissionManager(LidoMainnetAddresses.AGENT, LidoMainnetAddresses.KERNEL, APP_MANAGER_ROLE)
            )
        );

        // TokenManager
        builder.add(
            "Set MINT_ROLE manager and grant role to Voting on TokenManager",
            _votingCall(
                _aclCreatePermission(
                    LidoMainnetAddresses.VOTING,
                    LidoMainnetAddresses.TOKEN_MANAGER,
                    MINT_ROLE,
                    LidoMainnetAddresses.VOTING
                )
            )
        );

        builder.add(
            "Set REVOKE_VESTINGS_ROLE manager and grant role to Voting on TokenManager",
            _votingCall(
                _aclCreatePermission(
                    LidoMainnetAddresses.VOTING,
                    LidoMainnetAddresses.TOKEN_MANAGER,
                    REVOKE_VESTINGS_ROLE,
                    LidoMainnetAddresses.VOTING
                )
            )
        );

        // Finance
        builder.add(
            "Set CHANGE_PERIOD_ROLE manager and grant role to Voting on Finance",
            _votingCall(
                _aclCreatePermission(
                    LidoMainnetAddresses.VOTING,
                    LidoMainnetAddresses.FINANCE,
                    CHANGE_PERIOD_ROLE,
                    LidoMainnetAddresses.VOTING
                )
            )
        );

        builder.add(
            "Set CHANGE_BUDGETS_ROLE manager and grant role to Voting on Finance",
            _votingCall(
                _aclCreatePermission(
                    LidoMainnetAddresses.VOTING,
                    LidoMainnetAddresses.FINANCE,
                    CHANGE_BUDGETS_ROLE,
                    LidoMainnetAddresses.VOTING
                )
            )
        );

        // EVMScriptRegistry

        builder.add(
            "Revoke REGISTRY_MANAGER_ROLE permission from Voting on EVMScriptRegistry",
            _votingCall(
                _aclRevokePermission(
                    LidoMainnetAddresses.VOTING, LidoMainnetAddresses.EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE
                )
            )
        );

        builder.add(
            "Set REGISTRY_MANAGER_ROLE manager to Agent on EVMScriptRegistry",
            _votingCall(
                _aclSetPermissionManager(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.EVM_SCRIPT_REGISTRY, REGISTRY_MANAGER_ROLE
                )
            )
        );

        builder.add(
            "Revoke REGISTRY_ADD_EXECUTOR_ROLE permission from Voting on EVMScriptRegistry",
            _votingCall(
                _aclRevokePermission(
                    LidoMainnetAddresses.VOTING, LidoMainnetAddresses.EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE
                )
            )
        );

        builder.add(
            "Set REGISTRY_ADD_EXECUTOR_ROLE manager to Agent on EVMScriptRegistry",
            _votingCall(
                _aclSetPermissionManager(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.EVM_SCRIPT_REGISTRY, REGISTRY_ADD_EXECUTOR_ROLE
                )
            )
        );

        // CuratedModule

        builder.add(
            "Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule",
            _votingCall(
                _aclSetPermissionManager(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.CURATED_MODULE, STAKING_ROUTER_ROLE
                )
            )
        );

        builder.add(
            "Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on CuratedModule",
            _votingCall(
                _aclSetPermissionManager(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.CURATED_MODULE, MANAGE_NODE_OPERATOR_ROLE
                )
            )
        );

        builder.add(
            "Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on CuratedModule",
            _votingCall(
                _aclRevokePermission(
                    LidoMainnetAddresses.VOTING, LidoMainnetAddresses.CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE
                )
            )
        );

        builder.add(
            "Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on CuratedModule",
            _votingCall(
                _aclSetPermissionManager(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.CURATED_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE
                )
            )
        );

        builder.add(
            "Revoke MANAGE_SIGNING_KEYS permission from Voting on CuratedModule",
            _votingCall(
                _aclRevokePermission(
                    LidoMainnetAddresses.VOTING, LidoMainnetAddresses.CURATED_MODULE, MANAGE_SIGNING_KEYS
                )
            )
        );

        builder.add(
            "Set MANAGE_SIGNING_KEYS manager to Agent on CuratedModule",
            _votingCall(
                _aclSetPermissionManager(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.CURATED_MODULE, MANAGE_SIGNING_KEYS
                )
            )
        );

        // SDVTModule
        builder.add(
            "Set STAKING_ROUTER_ROLE manager to Agent on SDVTModule",
            _votingCall(
                _aclSetPermissionManager(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.SDVT_MODULE, STAKING_ROUTER_ROLE
                )
            )
        );

        builder.add(
            "Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on SDVTModule",
            _votingCall(
                _aclSetPermissionManager(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.SDVT_MODULE, MANAGE_NODE_OPERATOR_ROLE
                )
            )
        );

        builder.add(
            "Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on SDVTModule",
            _votingCall(
                _aclSetPermissionManager(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.SDVT_MODULE, SET_NODE_OPERATOR_LIMIT_ROLE
                )
            )
        );

        // ACL

        builder.add(
            "Grant CREATE_PERMISSIONS_ROLE permission to Agent on ACL",
            _votingCall(
                _aclGrantPermission(LidoMainnetAddresses.AGENT, LidoMainnetAddresses.ACL, CREATE_PERMISSIONS_ROLE)
            )
        );

        builder.add(
            "Revoke CREATE_PERMISSIONS_ROLE permission from Voting on ACL",
            _votingCall(
                _aclRevokePermission(LidoMainnetAddresses.VOTING, LidoMainnetAddresses.ACL, CREATE_PERMISSIONS_ROLE)
            )
        );

        builder.add(
            "Set CREATE_PERMISSIONS_ROLE manager to Agent on ACL",
            _votingCall(
                _aclSetPermissionManager(LidoMainnetAddresses.AGENT, LidoMainnetAddresses.ACL, CREATE_PERMISSIONS_ROLE)
            )
        );

        // WithdrawalQueue
        builder.add(
            "Grant PAUSE_ROLE on WithdrawalQueue to ResealManager",
            _agentForwardFromVoting(_ozGrantRole(RESEAL_MANAGER, LidoMainnetAddresses.WITHDRAWAL_QUEUE, PAUSE_ROLE))
        );

        builder.add(
            "Grant RESUME_ROLE on WithdrawalQueue to ResealManager",
            _agentForwardFromVoting(_ozGrantRole(RESEAL_MANAGER, LidoMainnetAddresses.WITHDRAWAL_QUEUE, RESUME_ROLE))
        );

        // LidoMainnetAddresses.VEBO
        builder.add(
            "Grant PAUSE_ROLE on LidoMainnetAddresses.VEBO to ResealManager",
            _agentForwardFromVoting(_ozGrantRole(RESEAL_MANAGER, LidoMainnetAddresses.VEBO, PAUSE_ROLE))
        );

        builder.add(
            "Grant RESUME_ROLE on LidoMainnetAddresses.VEBO to ResealManager",
            _agentForwardFromVoting(_ozGrantRole(RESEAL_MANAGER, LidoMainnetAddresses.VEBO, RESUME_ROLE))
        );

        // AllowedTokensRegistry

        builder.add(
            "Grant DEFAULT_ADMIN_ROLE on AllowedTokensRegistry to Voting",
            _agentForwardFromVoting(
                _ozGrantRole(
                    LidoMainnetAddresses.VOTING, LidoMainnetAddresses.ALLOWED_TOKENS_REGISTRY, DEFAULT_ADMIN_ROLE
                )
            )
        );

        builder.add(
            "Revoke DEFAULT_ADMIN_ROLE on AllowedTokensRegistry from Agent",
            _votingCall(
                _ozRevokeRole(
                    LidoMainnetAddresses.AGENT, LidoMainnetAddresses.ALLOWED_TOKENS_REGISTRY, DEFAULT_ADMIN_ROLE
                )
            )
        );

        builder.add(
            "Grant ADD_TOKEN_TO_ALLOWED_LIST_ROLE on AllowedTokensRegistry to Voting",
            _votingCall(
                _ozGrantRole(
                    LidoMainnetAddresses.VOTING,
                    LidoMainnetAddresses.ALLOWED_TOKENS_REGISTRY,
                    ADD_TOKEN_TO_ALLOWED_LIST_ROLE
                )
            )
        );

        builder.add(
            "Revoke ADD_TOKEN_TO_ALLOWED_LIST_ROLE on AllowedTokensRegistry from Agent",
            _votingCall(
                _ozRevokeRole(
                    LidoMainnetAddresses.AGENT,
                    LidoMainnetAddresses.ALLOWED_TOKENS_REGISTRY,
                    ADD_TOKEN_TO_ALLOWED_LIST_ROLE
                )
            )
        );

        builder.add(
            "Grant REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE on AllowedTokensRegistry to Voting",
            _votingCall(
                _ozGrantRole(
                    LidoMainnetAddresses.VOTING,
                    LidoMainnetAddresses.ALLOWED_TOKENS_REGISTRY,
                    REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE
                )
            )
        );

        builder.add(
            "Revoke REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE on AllowedTokensRegistry from Agent",
            _votingCall(
                _ozRevokeRole(
                    LidoMainnetAddresses.AGENT,
                    LidoMainnetAddresses.ALLOWED_TOKENS_REGISTRY,
                    REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE
                )
            )
        );

        // WithdrawalVault
        builder.add(
            "Set admin to Agent on WithdrawalVault",
            _votingCall(
                Omnibus.Call({
                    target: LidoMainnetAddresses.WITHDRAWAL_VAULT,
                    data: abi.encodeCall(IWithdrawalVaultProxy.proxy_changeAdmin, (LidoMainnetAddresses.AGENT))
                })
            )
        );

        // Insurance Fund
        builder.add(
            "Set owner to Voting on InsuranceFund",
            _agentForwardFromVoting(
                Omnibus.Call({
                    target: LidoMainnetAddresses.INSURANCE_FUND,
                    data: abi.encodeCall(IOwnable.transferOwnership, (LidoMainnetAddresses.VOTING))
                })
            )
        );

        // Agent

        builder.add(
            "Grant RUN_SCRIPT_ROLE to DualGovernance Executor on Agent",
            _votingCall(_aclGrantPermission(DUAL_GOVERNANCE_EXECUTOR, LidoMainnetAddresses.AGENT, RUN_SCRIPT_ROLE))
        );

        builder.add(
            "Set RUN_SCRIPT_ROLE manager to Agent on Agent",
            _votingCall(
                _aclSetPermissionManager(LidoMainnetAddresses.AGENT, LidoMainnetAddresses.AGENT, RUN_SCRIPT_ROLE)
            )
        );

        builder.add(
            "Grant EXECUTE_ROLE to DualGovernance Executor on Agent",
            _votingCall(_aclGrantPermission(DUAL_GOVERNANCE_EXECUTOR, LidoMainnetAddresses.AGENT, EXECUTE_ROLE))
        );

        builder.add(
            "Set EXECUTE_ROLE manager to Agent on Agent",
            _votingCall(_aclSetPermissionManager(LidoMainnetAddresses.AGENT, LidoMainnetAddresses.AGENT, EXECUTE_ROLE))
        );

        // Validate transferred roles
        builder.add(
            "Validate transferred roles",
            _votingCall(
                Omnibus.Call({
                    target: ROLES_VALIDATOR,
                    data: abi.encodeCall(IRolesValidator.validate, (DUAL_GOVERNANCE_EXECUTOR, RESEAL_MANAGER))
                })
            )
        );

        // Submit first dual governance proposal
        ExternalCall[] memory executorCalls = new ExternalCall[](2);
        executorCalls[0] = _agentForwardFromExecutor(
            _aclRevokePermission(LidoMainnetAddresses.VOTING, LidoMainnetAddresses.AGENT, RUN_SCRIPT_ROLE)
        );
        executorCalls[1] = _agentForwardFromExecutor(
            _aclRevokePermission(LidoMainnetAddresses.VOTING, LidoMainnetAddresses.AGENT, EXECUTE_ROLE)
        );
        // TODO: add actual proposal description
        builder.add(
            "Submit first proposal",
            _votingCall(_submitDualGovernanceProposal(DUAL_GOVERNANCE, executorCalls, "First dual governance proposal"))
        );

        // Verify state of the DG after launch
        // builder.add(
        //     "Verify state of the DG after launch",
        //     _votingCall(Omnibus.Call({target: LAUNCH_VERIFIER, data: abi.encodeCall(IDGLaunchVerifier.verify, ())}))
        // );

        return builder.items;
    }

    function getVoteItemsCount() public pure override returns (uint256) {
        return 48;
    }
}
