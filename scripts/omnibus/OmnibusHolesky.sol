// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "../../contracts/types/Duration.sol";

import {ExternalCall} from "../../contracts/libraries/ExternalCalls.sol";
import {EvmScriptUtils} from "../../test/utils/evm-script-utils.sol";

import {IOZ} from "./interfaces/IOZ.sol";
import {IACL} from "./interfaces/IACL.sol";
import {IAgent} from "./interfaces/IAgent.sol";
import {IVoting} from "./interfaces/IVoting.sol";
import {IOwnable} from "./interfaces/IOwnable.sol";
import {IGovernance} from "../../contracts/interfaces/IGovernance.sol";
import {IWithdrawalVaultProxy} from "./interfaces/IWithdrawalVaultProxy.sol";
import {IRolesValidator, IDGLaunchVerifier, ITimeConstraints, IFoo} from "./interfaces/utils.sol";

contract OmnibusHolesky {
    IACL public constant ACL = IACL(0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC);
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
    address public constant VEBO = 0xffDDF7025410412deaa05E3E1cE68FE53208afcb;

    address public immutable DUAL_GOVERNANCE;
    address public immutable ADMIN_EXECUTOR;
    address public immutable RESEAL_MANAGER;
    address public immutable ROLES_VALIDATOR;
    address public immutable LAUNCH_VERIFIER;

    struct VoteItem {
        string description;
        EvmScriptUtils.EvmScriptCall call;
    }

    constructor(
        address dualGovernance,
        address adminExecutor,
        address resealManager,
        address rolesValidator,
        address launchVerifier
    ) {
        DUAL_GOVERNANCE = dualGovernance;
        ADMIN_EXECUTOR = adminExecutor;
        RESEAL_MANAGER = resealManager;
        ROLES_VALIDATOR = rolesValidator;
        LAUNCH_VERIFIER = launchVerifier;
    }

    function getVoteItems() external view returns (VoteItem[] memory voteItems) {
        ExternalCall[] memory executorCalls = new ExternalCall[](3);
        voteItems = new VoteItem[](51);

        uint256 index = 0;

        // Lido
        voteItems[index++] = VoteItem({
            description: "Revoke STAKING_CONTROL_ROLE permission from Voting on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, keccak256("STAKING_CONTROL_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set STAKING_CONTROL_ROLE manager to Agent on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, keccak256("STAKING_CONTROL_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke RESUME_ROLE permission from Voting on Lido",
            call: _votingCall(address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, keccak256("RESUME_ROLE"))))
        });
        voteItems[index++] = VoteItem({
            description: "Set RESUME_ROLE manager to Agent on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, keccak256("RESUME_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke PAUSE_ROLE permission from Voting on Lido",
            call: _votingCall(address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, keccak256("PAUSE_ROLE"))))
        });
        voteItems[index++] = VoteItem({
            description: "Set PAUSE_ROLE manager to Agent on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, keccak256("PAUSE_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke STAKING_PAUSE_ROLE permission from Voting on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, keccak256("STAKING_PAUSE_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set STAKING_PAUSE_ROLE manager to Agent on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, keccak256("STAKING_PAUSE_ROLE")))
            )
        });

        // Kernel
        voteItems[index++] = VoteItem({
            description: "Revoke APP_MANAGER_ROLE permission from Voting on Kernel",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, KERNEL, keccak256("APP_MANAGER_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set APP_MANAGER_ROLE manager to Agent on Kernel",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, KERNEL, keccak256("APP_MANAGER_ROLE")))
            )
        });

        // TokenManager
        voteItems[index++] = VoteItem({
            description: "Set MINT_ROLE manager and grant role to Voting on TokenManager",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.createPermission, (VOTING, TOKEN_MANAGER, keccak256("MINT_ROLE"), VOTING))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set REVOKE_VESTINGS_ROLE manager and grant role to Voting on TokenManager",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.createPermission, (VOTING, TOKEN_MANAGER, keccak256("REVOKE_VESTINGS_ROLE"), VOTING))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set BURN_ROLE manager and grant role to Voting on TokenManager",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.createPermission, (VOTING, TOKEN_MANAGER, keccak256("BURN_ROLE"), VOTING))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set ISSUE_ROLE manager and grant role to Voting on TokenManager",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.createPermission, (VOTING, TOKEN_MANAGER, keccak256("ISSUE_ROLE"), VOTING))
            )
        });

        // Finance
        voteItems[index++] = VoteItem({
            description: "Set CHANGE_PERIOD_ROLE manager to Voting on Finance",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.createPermission, (VOTING, FINANCE, keccak256("CHANGE_PERIOD_ROLE"), VOTING))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set CHANGE_BUDGETS_ROLE manager to Voting on Finance",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.createPermission, (VOTING, FINANCE, keccak256("CHANGE_BUDGETS_ROLE"), VOTING))
            )
        });

        // EVMScriptRegistry
        voteItems[index++] = VoteItem({
            description: "Revoke REGISTRY_MANAGER_ROLE permission from Voting on EVMScriptRegistry",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, EVM_SCRIPT_REGISTRY, keccak256("REGISTRY_MANAGER_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set REGISTRY_MANAGER_ROLE manager to Agent on EVMScriptRegistry",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, EVM_SCRIPT_REGISTRY, keccak256("REGISTRY_MANAGER_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke REGISTRY_ADD_EXECUTOR_ROLE permission from Voting on EVMScriptRegistry",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, EVM_SCRIPT_REGISTRY, keccak256("REGISTRY_ADD_EXECUTOR_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set REGISTRY_ADD_EXECUTOR_ROLE manager to Agent on EVMScriptRegistry",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(
                    ACL.setPermissionManager, (AGENT, EVM_SCRIPT_REGISTRY, keccak256("REGISTRY_ADD_EXECUTOR_ROLE"))
                )
            )
        });

        // CuratedModule
        voteItems[index++] = VoteItem({
            description: "Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, CURATED_MODULE, keccak256("STAKING_ROUTER_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke MANAGE_NODE_OPERATOR_ROLE permission from Voting on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, CURATED_MODULE, keccak256("MANAGE_NODE_OPERATOR_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, CURATED_MODULE, keccak256("MANAGE_NODE_OPERATOR_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, CURATED_MODULE, keccak256("SET_NODE_OPERATOR_LIMIT_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, CURATED_MODULE, keccak256("SET_NODE_OPERATOR_LIMIT_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke MANAGE_SIGNING_KEYS permission from Voting on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, CURATED_MODULE, keccak256("MANAGE_SIGNING_KEYS")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set MANAGE_SIGNING_KEYS manager to Agent on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, CURATED_MODULE, keccak256("MANAGE_SIGNING_KEYS")))
            )
        });

        // SDVTModule
        voteItems[index++] = VoteItem({
            description: "Set STAKING_ROUTER_ROLE manager to Agent on SDVTModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, SDVT_MODULE, keccak256("STAKING_ROUTER_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on SDVTModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, SDVT_MODULE, keccak256("MANAGE_NODE_OPERATOR_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on SDVTModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, SDVT_MODULE, keccak256("SET_NODE_OPERATOR_LIMIT_ROLE")))
            )
        });

        // ACL
        voteItems[index++] = VoteItem({
            description: "Grant CREATE_PERMISSIONS_ROLE permission to Agent on ACL",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.grantPermission, (AGENT, address(ACL), keccak256("CREATE_PERMISSIONS_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke CREATE_PERMISSIONS_ROLE permission from Voting on ACL",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, address(ACL), keccak256("CREATE_PERMISSIONS_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set CREATE_PERMISSIONS_ROLE manager to Agent on ACL",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, address(ACL), keccak256("CREATE_PERMISSIONS_ROLE")))
            )
        });

        // WithdrawalQueue
        voteItems[index++] = VoteItem({
            description: "Grant PAUSE_ROLE on WithdrawalQueue to ResealManager",
            call: _agentForward(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (keccak256("PAUSE_ROLE"), RESEAL_MANAGER)))
        });
        voteItems[index++] = VoteItem({
            description: "Grant RESUME_ROLE on WithdrawalQueue to ResealManager",
            call: _agentForward(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (keccak256("RESUME_ROLE"), RESEAL_MANAGER)))
        });

        // VEBO
        voteItems[index++] = VoteItem({
            description: "Grant PAUSE_ROLE on VEBO to ResealManager",
            call: _agentForward(VEBO, abi.encodeCall(IOZ.grantRole, (keccak256("PAUSE_ROLE"), RESEAL_MANAGER)))
        });
        voteItems[index++] = VoteItem({
            description: "Grant RESUME_ROLE on VEBO to ResealManager",
            call: _agentForward(VEBO, abi.encodeCall(IOZ.grantRole, (keccak256("RESUME_ROLE"), RESEAL_MANAGER)))
        });

        // AllowedTokensRegistry
        bytes32 DEFAULT_ADMIN_ROLE = bytes32(0);
        voteItems[index++] = VoteItem({
            description: "Grant DEFAULT_ADMIN_ROLE on AllowedTokensRegistry to Voting",
            call: _agentForward(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (DEFAULT_ADMIN_ROLE, VOTING)))
        });
        voteItems[index++] = VoteItem({
            description: "Revoke DEFAULT_ADMIN_ROLE on AllowedTokensRegistry from AGENT",
            call: _votingCall(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (DEFAULT_ADMIN_ROLE, AGENT)))
        });
        voteItems[index++] = VoteItem({
            description: "Grant ADD_TOKEN_TO_ALLOWED_LIST_ROLE on AllowedTokensRegistry to Voting",
            call: _votingCall(
                ALLOWED_TOKENS_REGISTRY,
                abi.encodeCall(IOZ.grantRole, (keccak256("ADD_TOKEN_TO_ALLOWED_LIST_ROLE"), VOTING))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke ADD_TOKEN_TO_ALLOWED_LIST_ROLE on AllowedTokensRegistry from AGENT",
            call: _votingCall(
                ALLOWED_TOKENS_REGISTRY,
                abi.encodeCall(IOZ.revokeRole, (keccak256("ADD_TOKEN_TO_ALLOWED_LIST_ROLE"), AGENT))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Grant REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE on AllowedTokensRegistry to Voting",
            call: _votingCall(
                ALLOWED_TOKENS_REGISTRY,
                abi.encodeCall(IOZ.grantRole, (keccak256("REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE"), VOTING))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Revoke REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE on AllowedTokensRegistry from AGENT",
            call: _votingCall(
                ALLOWED_TOKENS_REGISTRY,
                abi.encodeCall(IOZ.revokeRole, (keccak256("REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE"), AGENT))
            )
        });

        // WithdrawalVault
        voteItems[index++] = VoteItem({
            description: "Set admin to Agent on WithdrawalVault",
            call: _votingCall(WITHDRAWAL_VAULT, abi.encodeCall(IWithdrawalVaultProxy.proxy_changeAdmin, (AGENT)))
        });

        // Agent
        voteItems[index++] = VoteItem({
            description: "Grant RUN_SCRIPT_ROLE to DualGovernance Executor on Agent",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.grantPermission, (ADMIN_EXECUTOR, AGENT, keccak256("RUN_SCRIPT_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set RUN_SCRIPT_ROLE manager to Agent on Agent",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, AGENT, keccak256("RUN_SCRIPT_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Grant EXECUTE_ROLE to DualGovernance Executor on Agent",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.grantPermission, (ADMIN_EXECUTOR, AGENT, keccak256("EXECUTE_ROLE")))
            )
        });
        voteItems[index++] = VoteItem({
            description: "Set EXECUTE_ROLE manager to Agent on Agent",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, AGENT, keccak256("EXECUTE_ROLE")))
            )
        });

        // Validate transferred roles
        voteItems[index++] = VoteItem({
            description: "Validate transferred roles",
            call: _votingCall(
                address(ROLES_VALIDATOR), abi.encodeCall(IRolesValidator.validate, (ADMIN_EXECUTOR, RESEAL_MANAGER))
            )
        });

        // Submit first dual governance proposal
        executorCalls[0] = _agentForwardFromExecutor(
            address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, AGENT, keccak256("RUN_SCRIPT_ROLE")))
        );
        executorCalls[1] = _agentForwardFromExecutor(
            address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, AGENT, keccak256("EXECUTE_ROLE")))
        );
        executorCalls[2] =
            _agentForwardFromExecutor(address(ROLES_VALIDATOR), abi.encodeCall(IRolesValidator.validateAfterDG, ()));
        voteItems[index++] = VoteItem({
            description: "Submit first proposal",
            call: _votingCall(
                address(DUAL_GOVERNANCE),
                abi.encodeCall(IGovernance.submitProposal, (executorCalls, string("First dual governance proposal")))
            )
        });

        // Verify state of the DG after launch
        voteItems[index++] = VoteItem({
            description: "Verify dual governance launch",
            call: _votingCall(address(LAUNCH_VERIFIER), abi.encodeCall(IDGLaunchVerifier.verify, ()))
        });
    }

    function validateVote(uint256 voteId) external view returns (bool) {
        ( /*open*/
            , /*executed*/
            , /*startDate*/
            , /*snapshotBlock*/
            , /*supportRequired*/
            , /*minAcceptQuorum*/
            , /*yea*/
            , /*nay*/
            , /*votingPower*/
            ,
            bytes memory script,
            /*phase*/
        ) = IVoting(VOTING).getVote(voteId);
        return keccak256(script) == keccak256(this.getEVMCallScript());
    }

    function getEVMCallScript() external view returns (bytes memory) {
        EvmScriptUtils.EvmScriptCall[] memory allCalls = new EvmScriptUtils.EvmScriptCall[](11);
        VoteItem[] memory voteItems = this.getVoteItems();

        for (uint256 i = 0; i < voteItems.length; i++) {
            allCalls[i] = voteItems[i].call;
        }

        return EvmScriptUtils.encodeEvmCallScript(allCalls);
    }

    function _votingCall(
        address target,
        bytes memory data
    ) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return EvmScriptUtils.EvmScriptCall(target, data);
    }

    function _agentForward(
        address target,
        bytes memory data
    ) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return _votingCall(
            address(AGENT), abi.encodeCall(IAgent.forward, (EvmScriptUtils.encodeEvmCallScript(target, data)))
        );
    }

    function _executorCall(
        address target,
        uint96 value,
        bytes memory payload
    ) internal pure returns (ExternalCall memory) {
        return ExternalCall(target, value, payload);
    }

    function _agentForwardFromExecutor(address target, bytes memory data) internal pure returns (ExternalCall memory) {
        return _executorCall(
            address(AGENT), 0, abi.encodeCall(IAgent.forward, (EvmScriptUtils.encodeEvmCallScript(target, data)))
        );
    }
}
