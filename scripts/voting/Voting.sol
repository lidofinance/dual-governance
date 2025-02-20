// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "../../contracts/types/Duration.sol";

import {ExternalCall} from "../../contracts/libraries/ExternalCalls.sol";
import {EvmScriptUtils} from "../../test/utils/evm-script-utils.sol";

import {IOZ} from "./interfaces/IOZ.sol";
import {IACL} from "./interfaces/IACL.sol";
import {IAgent} from "./interfaces/IAgent.sol";
import {IVoting} from "./interfaces/IVoting.sol";
import {IGovernance} from "../../contracts/interfaces/IGovernance.sol";
import {IHoleskyMocksLidoRolesValidator, IDGLaunchVerifier, ITimeConstraints, IFoo} from "./interfaces/utils.sol";

contract Voting {
    IACL private constant ACL = IACL(0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC);
    address private constant LIDO = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address private constant AGENT = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d;
    address private constant VOTING = 0xdA7d2573Df555002503F29aA4003e398d28cc00f;
    address private constant WITHDRAWAL_QUEUE = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
    address private constant ALLOWED_TOKENS_REGISTRY = 0x091C0eC8B4D54a9fcB36269B5D5E5AF43309e666;
    address private constant TOKEN_MANAGER = 0xFaa1692c6eea8eeF534e7819749aD93a1420379A;

    address private constant FOO = 0xC3fc22C7e0d20247B797fb6dc743BD3879217c81;
    address private constant ROLES_VALIDATOR = 0x0F8826a574BCFDC4997939076f6D82877971feB3;
    address private constant LAUNCH_VERIFIER = 0xfEcF4634f6571da23C8F21bEEeA8D12788df529e;
    address private constant TIME_CONSTRAINTS = 0x3db5ABA48123bb8789f6f09ec714e7082Bc26747;

    address private immutable DUAL_GOVERNANCE;
    address private immutable ADMIN_EXECUTOR;
    address private immutable RESEAL_MANAGER;

    struct VoteItem {
        string description;
        EvmScriptUtils.EvmScriptCall call;
    }

    constructor(address dualGovernance, address adminExecutor, address resealManager) {
        DUAL_GOVERNANCE = dualGovernance;
        ADMIN_EXECUTOR = adminExecutor;
        RESEAL_MANAGER = resealManager;
    }

    function getVoteItems() external view returns (VoteItem[] memory) {
        VoteItem[] memory voteItems = new VoteItem[](11);
        ExternalCall[] memory executorCalls = new ExternalCall[](2);

        // Lido
        voteItems[0] = VoteItem({
            description: "Grant permission for STAKING_CONTROL_ROLE on Lido to Agent",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.grantPermission, (AGENT, LIDO, keccak256("STAKING_CONTROL_ROLE")))
            )
        });
        voteItems[1] = VoteItem({
            description: "Revoke permission from Voting for STAKING_CONTROL_ROLE on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.revokePermission, (VOTING, LIDO, keccak256("STAKING_CONTROL_ROLE")))
            )
        });
        voteItems[2] = VoteItem({
            description: "Set Agent as a manager for STAKING_CONTROL_ROLE on Lido",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.setPermissionManager, (AGENT, LIDO, keccak256("STAKING_CONTROL_ROLE")))
            )
        });

        // Withdrawal Queue
        voteItems[3] = VoteItem({
            description: "Grant PAUSE_ROLE on Withdrawal Queue to RESEAL_MANAGER",
            call: _agentForward(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (keccak256("PAUSE_ROLE"), RESEAL_MANAGER)))
        });
        voteItems[4] = VoteItem({
            description: "Grant RESUME_ROLE on Withdrawal Queue to RESEAL_MANAGER",
            call: _agentForward(WITHDRAWAL_QUEUE, abi.encodeCall(IOZ.grantRole, (keccak256("RESUME_ROLE"), RESEAL_MANAGER)))
        });

        // Allowed tokens registry
        bytes32 DEFAULT_ADMIN_ROLE = bytes32(0);
        voteItems[5] = VoteItem({
            description: "Grant DEFAULT_ADMIN_ROLE on AllowedTokensRegistry to Voting",
            call: _agentForward(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.grantRole, (DEFAULT_ADMIN_ROLE, VOTING)))
        });
        voteItems[6] = VoteItem({
            description: "Revoke DEFAULT_ADMIN_ROLE on AllowedTokensRegistry from AGENT",
            call: _votingCall(ALLOWED_TOKENS_REGISTRY, abi.encodeCall(IOZ.revokeRole, (DEFAULT_ADMIN_ROLE, AGENT)))
        });

        // Agent
        voteItems[7] = VoteItem({
            description: "Grant RUN_SCRIPT_ROLE on ACL to ADMIN_EXECUTOR",
            call: _votingCall(
                address(ACL), abi.encodeCall(ACL.grantPermission, (ADMIN_EXECUTOR, AGENT, keccak256("RUN_SCRIPT_ROLE")))
            )
        });

        // Validate transferred roles
        voteItems[8] = VoteItem({
            description: "Validate transferred roles",
            call: _votingCall(
                address(ROLES_VALIDATOR),
                abi.encodeCall(IHoleskyMocksLidoRolesValidator.validate, (ADMIN_EXECUTOR, RESEAL_MANAGER))
            )
        });

        // Submit first proposal
        executorCalls[0] = _agentForwardFromExecutor(FOO, abi.encodeCall(IFoo.bar, ()));
        executorCalls[1] = _agentForwardFromExecutor(
            address(TIME_CONSTRAINTS),
            abi.encodeCall(ITimeConstraints.checkExecuteWithinDayTime, (Durations.from(28800), Durations.from(72000)))
        );
        voteItems[9] = VoteItem({
            description: "Submit first proposal",
            call: _votingCall(
                address(DUAL_GOVERNANCE),
                abi.encodeCall(IGovernance.submitProposal, (executorCalls, string("First dual governance proposal")))
            )
        });

        // Verify dual governance launch
        voteItems[10] = VoteItem({
            description: "Verify dual governance launch",
            call: _votingCall(address(LAUNCH_VERIFIER), abi.encodeCall(IDGLaunchVerifier.verify, ()))
        });

        return voteItems;
    }

    function validateVote(uint256 voteId) external view returns (bool) {
        (,,,,,,,,, bytes memory script,) = IVoting(VOTING).getVote(voteId);
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

    function _aclPermissionGrant(
        address target,
        address grantTo,
        bytes32 permission
    ) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(
            address(ACL), abi.encodeCall(ACL.grantPermission, (grantTo, target, permission))
        );
    }

    function _aclPermissionRevoke(
        address target,
        address revokeFrom,
        bytes32 permission
    ) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(
            address(ACL), abi.encodeCall(ACL.revokePermission, (revokeFrom, target, permission))
        );
    }

    function _aclPermissionSetManager(
        address app,
        address newManager,
        bytes32 role
    ) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(
            address(ACL), abi.encodeCall(ACL.setPermissionManager, (newManager, app, role))
        );
    }

    function _ozRoleGrant(address target, address grantTo, bytes32 role) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(target, abi.encodeCall(IOZ.grantRole, (role, grantTo)));
    }

    function _ozRoleRevoke(address target, address revokeFrom, bytes32 role) internal pure returns (bytes memory) {
        return EvmScriptUtils.encodeEvmCallScript(target, abi.encodeCall(IOZ.revokeRole, (role, revokeFrom)));
    }
}
