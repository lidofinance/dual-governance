// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {EvmScriptUtils} from "scripts/utils/evm-script-utils.sol";
import {IGovernance} from "contracts/interfaces/IGovernance.sol";

import {LidoMainnetAddresses} from "../LidoMainnetAddresses.sol";
import {IAgent} from "./interfaces/IAgent.sol";
import {IVoting} from "./interfaces/IVoting.sol";
import {IACL} from "./interfaces/IACL.sol";
import {IOZ} from "./interfaces/IOZ.sol";

abstract contract Omnibus {
    struct VoteItem {
        string description;
        EvmScriptUtils.EvmScriptCall call;
    }

    struct Call {
        address target;
        bytes data;
    }

    function getVoteItemsCount() public view virtual returns (uint256);
    function getVoteItems() external view virtual returns (VoteItem[] memory voteItems);

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
        ) = IVoting(LidoMainnetAddresses.VOTING).getVote(voteId);
        return keccak256(script) == keccak256(this.getEVMCallScript());
    }

    function getEVMCallScript() external view returns (bytes memory) {
        EvmScriptUtils.EvmScriptCall[] memory allCalls = new EvmScriptUtils.EvmScriptCall[](this.getVoteItemsCount());
        VoteItem[] memory voteItems = this.getVoteItems();

        for (uint256 i = 0; i < voteItems.length; i++) {
            allCalls[i] = voteItems[i].call;
        }

        return EvmScriptUtils.encodeEvmCallScript(allCalls);
    }

    function _aclGrantPermission(address who, address where, bytes32 what) internal pure returns (Call memory) {
        return Call({target: LidoMainnetAddresses.ACL, data: abi.encodeCall(IACL.grantPermission, (who, where, what))});
    }

    function _aclRevokePermission(address who, address where, bytes32 what) internal pure returns (Call memory) {
        return Call({target: LidoMainnetAddresses.ACL, data: abi.encodeCall(IACL.revokePermission, (who, where, what))});
    }

    function _aclSetPermissionManager(address who, address where, bytes32 what) internal pure returns (Call memory) {
        return Call({
            target: LidoMainnetAddresses.ACL,
            data: abi.encodeCall(IACL.setPermissionManager, (who, where, what))
        });
    }

    function _aclCreatePermission(
        address who,
        address where,
        bytes32 what,
        address grantTo
    ) internal pure returns (Call memory) {
        return Call({
            target: LidoMainnetAddresses.ACL,
            data: abi.encodeCall(IACL.createPermission, (who, where, what, grantTo))
        });
    }

    function _ozGrantRole(address who, address where, bytes32 what) internal pure returns (Call memory) {
        return Call({target: where, data: abi.encodeCall(IOZ.grantRole, (what, who))});
    }

    function _ozRevokeRole(address who, address where, bytes32 what) internal pure returns (Call memory) {
        return Call({target: where, data: abi.encodeCall(IOZ.revokeRole, (what, who))});
    }

    function _votingCall(Call memory call) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return EvmScriptUtils.EvmScriptCall(call.target, call.data);
    }

    function _agentForward(Call memory call) internal pure returns (Call memory) {
        return Call({
            target: LidoMainnetAddresses.AGENT,
            data: abi.encodeCall(IAgent.forward, (EvmScriptUtils.encodeEvmCallScript(call.target, call.data)))
        });
    }

    function _agentForwardFromVoting(Call memory call) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return _votingCall(_agentForward(call));
    }

    function _agentForwardFromExecutor(Call memory call) internal pure returns (ExternalCall memory) {
        return _executorCall(_agentForward(call));
    }

    function _executorCall(Call memory call) internal pure returns (ExternalCall memory) {
        return ExternalCall(call.target, 0, call.data);
    }

    function _submitDualGovernanceProposal(
        address dualGovernance,
        ExternalCall[] memory externalCalls,
        string memory description
    ) internal pure returns (Call memory) {
        return Call({
            target: dualGovernance,
            data: abi.encodeCall(IGovernance.submitProposal, (externalCalls, description))
        });
    }
}
