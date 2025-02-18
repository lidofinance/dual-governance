// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "../../contracts/types/Duration.sol";

import {ExternalCall} from "../../contracts/libraries/ExternalCalls.sol";
import {EvmScriptUtils} from "../../test/utils/evm-script-utils.sol";

import {IOZ} from "./interfaces/IOZ.sol";
import {IACL} from "./interfaces/IACL.sol";
import {IAgent} from "./interfaces/IAgent.sol";
import {IGovernance} from "../../contracts/interfaces/IGovernance.sol";
import {
    IHoleskyMocksLidoRolesValidator, IDGLaunchVerifier, ITimeConstraints, IFoo, IVoting
} from "./interfaces/utils.sol";

contract Voting {
    IACL public constant ACL = IACL(0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC);
    address public constant LIDO = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address public constant AGENT = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d;
    address public constant VOTING = 0xdA7d2573Df555002503F29aA4003e398d28cc00f;
    address public constant WITHDRAWAL_QUEUE = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
    address public constant ALLOWED_TOKENS_REGISTRY = 0x091C0eC8B4D54a9fcB36269B5D5E5AF43309e666;
    address public constant TOKEN_MANAGER = 0xFaa1692c6eea8eeF534e7819749aD93a1420379A;

    address public constant FOO = 0xC3fc22C7e0d20247B797fb6dc743BD3879217c81;
    address public constant ROLES_VALIDATOR = 0x0F8826a574BCFDC4997939076f6D82877971feB3;
    address public constant LAUNCH_VERIFIER = 0xfEcF4634f6571da23C8F21bEEeA8D12788df529e;
    address public constant TIME_CONSTRAINTS = 0x3db5ABA48123bb8789f6f09ec714e7082Bc26747;

    address public immutable DUAL_GOVERNANCE;
    address public immutable ADMIN_EXECUTOR;
    address public immutable RESEAL_MANAGER;

    constructor(address dualGovernance, address adminExecutor, address resealManager) {
        DUAL_GOVERNANCE = dualGovernance;
        ADMIN_EXECUTOR = adminExecutor;
        RESEAL_MANAGER = resealManager;
    }

    function getVoteCalldata() external view returns (bytes memory) {
        EvmScriptUtils.EvmScriptCall[] memory allCalls = new EvmScriptUtils.EvmScriptCall[](12);
        uint256 callIndex = 0;

        // Lido
        bytes32 stakingControlRole = keccak256("STAKING_CONTROL_ROLE");
        allCalls[callIndex++] =
            votingCall(address(ACL), abi.encodeCall(ACL.grantPermission, (AGENT, LIDO, stakingControlRole)));
        allCalls[callIndex++] =
            votingCall(address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, stakingControlRole)));
        allCalls[callIndex++] =
            votingCall(address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, stakingControlRole)));

        // Withdrawal Queue
        bytes32 pauseRole = keccak256("PAUSE_ROLE");
        bytes32 resumeRole = keccak256("RESUME_ROLE");
        allCalls[callIndex++] =
            agentForward(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (pauseRole, RESEAL_MANAGER)));
        allCalls[callIndex++] =
            agentForward(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (resumeRole, RESEAL_MANAGER)));
        // Allowed tokens registry
        bytes32 defaultAdminRole = bytes32(0);
        allCalls[callIndex++] =
            agentForward(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (defaultAdminRole, VOTING)));
        allCalls[callIndex++] =
            votingCall(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (defaultAdminRole, AGENT)));

        // Agent
        bytes32 runScriptRole = keccak256("RUN_SCRIPT_ROLE");
        allCalls[callIndex++] =
            votingCall(address(ACL), abi.encodeCall(ACL.grantPermission, (ADMIN_EXECUTOR, AGENT, runScriptRole)));

        // Validate transferred roles
        allCalls[callIndex++] = votingCall(
            address(ROLES_VALIDATOR),
            abi.encodeCall(IHoleskyMocksLidoRolesValidator.validate, (ADMIN_EXECUTOR, RESEAL_MANAGER))
        );

        // Submit first proposal
        ExternalCall[] memory proposalCalls = new ExternalCall[](2);
        proposalCalls[0] = ExternalCall(
            address(AGENT),
            0,
            abi.encodeCall(IAgent.forward, EvmScriptUtils.encodeEvmCallScript(FOO, abi.encodeCall(IFoo.bar, ())))
        );
        proposalCalls[1] = ExternalCall(
            address(TIME_CONSTRAINTS),
            0,
            abi.encodeCall(ITimeConstraints.checkExecuteWithinDayTime, (Durations.from(28800), Durations.from(72000)))
        );

        allCalls[callIndex++] = votingCall(
            address(DUAL_GOVERNANCE), abi.encodeCall(IGovernance.submitProposal, (proposalCalls, string("")))
        );

        // Verify dual governance launch
        allCalls[callIndex++] = votingCall(address(LAUNCH_VERIFIER), abi.encodeCall(IDGLaunchVerifier.verify, ()));

        return EvmScriptUtils.encodeEvmCallScript(allCalls);
    }

    function getVoteCalldataForVoting() external view returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(
            VOTING, abi.encodeCall(IVoting.newVote, (this.getVoteCalldata(), "", false, false))
        );
    }

    function votingCall(
        address target,
        bytes memory data
    ) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return EvmScriptUtils.EvmScriptCall(target, data);
    }

    function agentForward(
        address target,
        bytes memory data
    ) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return votingCall(
            address(AGENT), abi.encodeCall(IAgent.forward, (EvmScriptUtils.encodeEvmCallScript(target, data)))
        );
    }

    // TODO: add agent fowrard wrapper
    // TODO: add dual governance submit proposal wrapper

    function aclPermissionGrant(
        address target,
        address grantTo,
        bytes32 permission
    ) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(
            address(ACL), abi.encodeCall(ACL.grantPermission, (grantTo, target, permission))
        );
    }

    function aclPermissionRevoke(
        address target,
        address revokeFrom,
        bytes32 permission
    ) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(
            address(ACL), abi.encodeCall(ACL.revokePermission, (revokeFrom, target, permission))
        );
    }

    function aclPermissionSetManager(
        address app,
        address newManager,
        bytes32 role
    ) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(
            address(ACL), abi.encodeCall(ACL.setPermissionManager, (newManager, app, role))
        );
    }

    function ozRoleGrant(address target, address grantTo, bytes32 role) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(target, abi.encodeCall(IOZ.grantRole, (role, grantTo)));
    }

    function ozRoleRevoke(address target, address revokeFrom, bytes32 role) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(target, abi.encodeCall(IOZ.revokeRole, (role, revokeFrom)));
    }
}
