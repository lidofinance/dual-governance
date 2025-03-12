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

contract Omnibus {
    IACL public constant ACL = IACL(0x9895F0F17cc1d1891b6f18ee0b483B6f221b37Bb);
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
    address public constant VEBO = 0x0De4Ea0184c2ad0BacA7183356Aea5B8d5Bf5c6e;

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
        ExternalCall[] memory executorCalls = new ExternalCall[](2);
        voteItems = new VoteItem[](48);

        // Lido
        voteItems[0] = VoteItem({
            description: "Revoke STAKING_CONTROL_ROLE permission from Voting on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, keccak256("STAKING_CONTROL_ROLE")))
            )
        });
        voteItems[1] = VoteItem({
            description: "Set STAKING_CONTROL_ROLE manager to Agent on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, keccak256("STAKING_CONTROL_ROLE")))
            )
        });
        voteItems[2] = VoteItem({
            description: "Revoke RESUME_ROLE permission from Voting on Lido",
            call: _votingCall(address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, keccak256("RESUME_ROLE"))))
        });
        voteItems[3] = VoteItem({
            description: "Set RESUME_ROLE manager to Agent on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, keccak256("RESUME_ROLE")))
            )
        });
        voteItems[4] = VoteItem({
            description: "Revoke PAUSE_ROLE permission from Voting on Lido",
            call: _votingCall(address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, keccak256("PAUSE_ROLE"))))
        });
        voteItems[5] = VoteItem({
            description: "Set PAUSE_ROLE manager to Agent on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, keccak256("PAUSE_ROLE")))
            )
        });
        voteItems[6] = VoteItem({
            description: "Revoke STAKING_PAUSE_ROLE permission from Voting on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, keccak256("STAKING_PAUSE_ROLE")))
            )
        });
        voteItems[7] = VoteItem({
            description: "Set STAKING_PAUSE_ROLE manager to Agent on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, keccak256("STAKING_PAUSE_ROLE")))
            )
        });

        // Kernel
        voteItems[8] = VoteItem({
            description: "Revoke APP_MANAGER_ROLE permission from Voting on Kernel",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, KERNEL, keccak256("APP_MANAGER_ROLE")))
            )
        });
        voteItems[9] = VoteItem({
            description: "Set APP_MANAGER_ROLE manager to Agent on Kernel",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, KERNEL, keccak256("APP_MANAGER_ROLE")))
            )
        });

        // TokenManager
        voteItems[10] = VoteItem({
            description: "Set MINT_ROLE manager and grant role to Voting on TokenManager",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.createPermission, (VOTING, TOKEN_MANAGER, keccak256("MINT_ROLE"), VOTING))
            )
        });
        voteItems[11] = VoteItem({
            description: "Set REVOKE_VESTINGS_ROLE manager and grant role to Voting on TokenManager",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.createPermission, (VOTING, TOKEN_MANAGER, keccak256("REVOKE_VESTINGS_ROLE"), VOTING))
            )
        });

        // Finance
        voteItems[12] = VoteItem({
            description: "Set CHANGE_PERIOD_ROLE manager to Voting on Finance",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.createPermission, (VOTING, FINANCE, keccak256("CHANGE_PERIOD_ROLE"), VOTING))
            )
        });
        voteItems[13] = VoteItem({
            description: "Set CHANGE_BUDGETS_ROLE manager to Voting on Finance",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.createPermission, (VOTING, FINANCE, keccak256("CHANGE_BUDGETS_ROLE"), VOTING))
            )
        });

        // EVMScriptRegistry
        voteItems[14] = VoteItem({
            description: "Revoke REGISTRY_MANAGER_ROLE permission from Voting on EVMScriptRegistry",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, EVM_SCRIPT_REGISTRY, keccak256("REGISTRY_MANAGER_ROLE")))
            )
        });
        voteItems[15] = VoteItem({
            description: "Set REGISTRY_MANAGER_ROLE manager to Agent on EVMScriptRegistry",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, EVM_SCRIPT_REGISTRY, keccak256("REGISTRY_MANAGER_ROLE")))
            )
        });
        voteItems[16] = VoteItem({
            description: "Revoke REGISTRY_ADD_EXECUTOR_ROLE permission from Voting on EVMScriptRegistry",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, EVM_SCRIPT_REGISTRY, keccak256("REGISTRY_ADD_EXECUTOR_ROLE")))
            )
        });
        voteItems[17] = VoteItem({
            description: "Set REGISTRY_ADD_EXECUTOR_ROLE manager to Agent on EVMScriptRegistry",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(
                    ACL.setPermissionManager, (AGENT, EVM_SCRIPT_REGISTRY, keccak256("REGISTRY_ADD_EXECUTOR_ROLE"))
                )
            )
        });

        // CuratedModule
        voteItems[18] = VoteItem({
            description: "Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, CURATED_MODULE, keccak256("STAKING_ROUTER_ROLE")))
            )
        });
        voteItems[19] = VoteItem({
            description: "Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, CURATED_MODULE, keccak256("MANAGE_NODE_OPERATOR_ROLE")))
            )
        });
        voteItems[20] = VoteItem({
            description: "Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, CURATED_MODULE, keccak256("SET_NODE_OPERATOR_LIMIT_ROLE")))
            )
        });
        voteItems[21] = VoteItem({
            description: "Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, CURATED_MODULE, keccak256("SET_NODE_OPERATOR_LIMIT_ROLE")))
            )
        });
        voteItems[22] = VoteItem({
            description: "Revoke MANAGE_SIGNING_KEYS permission from Voting on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, CURATED_MODULE, keccak256("MANAGE_SIGNING_KEYS")))
            )
        });
        voteItems[23] = VoteItem({
            description: "Set MANAGE_SIGNING_KEYS manager to Agent on CuratedModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, CURATED_MODULE, keccak256("MANAGE_SIGNING_KEYS")))
            )
        });

        // SDVTModule
        voteItems[24] = VoteItem({
            description: "Set STAKING_ROUTER_ROLE manager to Agent on SDVTModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, SDVT_MODULE, keccak256("STAKING_ROUTER_ROLE")))
            )
        });
        voteItems[25] = VoteItem({
            description: "Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on SDVTModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, SDVT_MODULE, keccak256("MANAGE_NODE_OPERATOR_ROLE")))
            )
        });
        voteItems[26] = VoteItem({
            description: "Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on SDVTModule",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, SDVT_MODULE, keccak256("SET_NODE_OPERATOR_LIMIT_ROLE")))
            )
        });

        // ACL
        voteItems[27] = VoteItem({
            description: "Grant CREATE_PERMISSIONS_ROLE permission to Agent on ACL",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.grantPermission, (AGENT, address(ACL), keccak256("CREATE_PERMISSIONS_ROLE")))
            )
        });
        voteItems[28] = VoteItem({
            description: "Revoke CREATE_PERMISSIONS_ROLE permission from Voting on ACL",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.revokePermission, (VOTING, address(ACL), keccak256("CREATE_PERMISSIONS_ROLE")))
            )
        });
        voteItems[29] = VoteItem({
            description: "Set CREATE_PERMISSIONS_ROLE manager to Agent on ACL",
            call: _votingCall(
                address(ACL),
                abi.encodeCall(ACL.setPermissionManager, (AGENT, address(ACL), keccak256("CREATE_PERMISSIONS_ROLE")))
            )
        });

        // WithdrawalQueue
        voteItems[30] = VoteItem({
            description: "Grant PAUSE_ROLE on WithdrawalQueue to ResealManager",
            call: _agentForward(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (keccak256("PAUSE_ROLE"), RESEAL_MANAGER)))
        });
        voteItems[31] = VoteItem({
            description: "Grant RESUME_ROLE on WithdrawalQueue to ResealManager",
            call: _agentForward(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (keccak256("RESUME_ROLE"), RESEAL_MANAGER)))
        });

        // VEBO
        voteItems[32] = VoteItem({
            description: "Grant PAUSE_ROLE on VEBO to ResealManager",
            call: _agentForward(VEBO, abi.encodeCall(IOZ.grantRole, (keccak256("PAUSE_ROLE"), RESEAL_MANAGER)))
        });
        voteItems[33] = VoteItem({
            description: "Grant RESUME_ROLE on VEBO to ResealManager",
            call: _agentForward(VEBO, abi.encodeCall(IOZ.grantRole, (keccak256("RESUME_ROLE"), RESEAL_MANAGER)))
        });

        // AllowedTokensRegistry
        bytes32 DEFAULT_ADMIN_ROLE = bytes32(0);
        voteItems[33] = VoteItem({
            description: "Grant DEFAULT_ADMIN_ROLE on AllowedTokensRegistry to Voting",
            call: _agentForward(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (DEFAULT_ADMIN_ROLE, VOTING)))
        });
        voteItems[34] = VoteItem({
            description: "Revoke DEFAULT_ADMIN_ROLE on AllowedTokensRegistry from AGENT",
            call: _votingCall(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (DEFAULT_ADMIN_ROLE, AGENT)))
        });
        voteItems[35] = VoteItem({
            description: "Grant ADD_TOKEN_TO_ALLOWED_LIST_ROLE on AllowedTokensRegistry to Voting",
            call: _votingCall(
                ALLOWED_TOKENS_REGISTRY,
                abi.encodeCall(IOZ.grantRole, (keccak256("ADD_TOKEN_TO_ALLOWED_LIST_ROLE"), VOTING))
            )
        });
        voteItems[36] = VoteItem({
            description: "Revoke ADD_TOKEN_TO_ALLOWED_LIST_ROLE on AllowedTokensRegistry from AGENT",
            call: _votingCall(
                ALLOWED_TOKENS_REGISTRY,
                abi.encodeCall(IOZ.revokeRole, (keccak256("ADD_TOKEN_TO_ALLOWED_LIST_ROLE"), AGENT))
            )
        });
        voteItems[37] = VoteItem({
            description: "Grant REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE on AllowedTokensRegistry to Voting",
            call: _votingCall(
                ALLOWED_TOKENS_REGISTRY,
                abi.encodeCall(IOZ.grantRole, (keccak256("REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE"), VOTING))
            )
        });
        voteItems[38] = VoteItem({
            description: "Revoke REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE on AllowedTokensRegistry from AGENT",
            call: _votingCall(
                ALLOWED_TOKENS_REGISTRY,
                abi.encodeCall(IOZ.revokeRole, (keccak256("REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE"), AGENT))
            )
        });

        // WithdrawalVault
        voteItems[39] = VoteItem({
            description: "Set admin to Agent on WithdrawalVault",
            call: _votingCall(WITHDRAWAL_VAULT, abi.encodeCall(IWithdrawalVaultProxy.proxy_changeAdmin, (AGENT)))
        });

        // Insurance Fund
        voteItems[40] = VoteItem({
            description: "Set owner to Voting on InsuranceFund",
            call: _agentForward(INSURANCE_FUND, abi.encodeCall(IOwnable.transferOwnership, (VOTING)))
        });

        // Agent
        voteItems[41] = VoteItem({
            description: "Grant RUN_SCRIPT_ROLE to DualGovernance Executor on Agent",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.grantPermission, (ADMIN_EXECUTOR, AGENT, keccak256("RUN_SCRIPT_ROLE")))
            )
        });
        voteItems[42] = VoteItem({
            description: "Set RUN_SCRIPT_ROLE manager to Agent on Agent",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, AGENT, keccak256("RUN_SCRIPT_ROLE")))
            )
        });
        voteItems[43] = VoteItem({
            description: "Grant EXECUTE_ROLE to DualGovernance Executor on Agent",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.grantPermission, (ADMIN_EXECUTOR, AGENT, keccak256("EXECUTE_ROLE")))
            )
        });
        voteItems[44] = VoteItem({
            description: "Set EXECUTE_ROLE manager to Agent on Agent",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, AGENT, keccak256("EXECUTE_ROLE")))
            )
        });

        // Validate transferred roles
        voteItems[45] = VoteItem({
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
        voteItems[46] = VoteItem({
            description: "Submit first proposal",
            call: _votingCall(
                address(DUAL_GOVERNANCE),
                abi.encodeCall(IGovernance.submitProposal, (executorCalls, string("First dual governance proposal")))
            )
        });

        // Verify state of the DG after launch
        voteItems[47] = VoteItem({
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
