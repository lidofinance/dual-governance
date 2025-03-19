// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {EvmScriptUtils} from "test/utils/evm-script-utils.sol";

import {IVoting} from "./interfaces/IVoting.sol";
import {IForwarder} from "./interfaces/IForwarder.sol";

abstract contract OmnibusBase {
    struct VoteItem {
        string description;
        EvmScriptUtils.EvmScriptCall call;
    }

    function getVoteItems() public view virtual returns (VoteItem[] memory);
    function getVoteItemsCount() internal pure virtual returns (uint256);

    function getEVMCallScript() external view returns (bytes memory) {
        uint256 voteItemsCount = getVoteItemsCount();

        EvmScriptUtils.EvmScriptCall[] memory allCalls = new EvmScriptUtils.EvmScriptCall[](voteItemsCount);
        VoteItem[] memory voteItems = this.getVoteItems();

        for (uint256 i = 0; i < voteItems.length; i++) {
            allCalls[i] = voteItems[i].call;
        }

        return EvmScriptUtils.encodeEvmCallScript(allCalls);
    }

    function validateVote(address voting, uint256 voteId) internal view returns (bool) {
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
        ) = IVoting(voting).getVote(voteId);
        return keccak256(script) == keccak256(this.getEVMCallScript());
    }

    function _votingCall(
        address target,
        bytes memory data
    ) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return EvmScriptUtils.EvmScriptCall(target, data);
    }

    function _forwardCall(
        address forwarder,
        address target,
        bytes memory data
    ) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return _votingCall(
            forwarder, abi.encodeCall(IForwarder.forward, (EvmScriptUtils.encodeEvmCallScript(target, data)))
        );
    }

    function _executorCall(
        address target,
        uint96 value,
        bytes memory payload
    ) internal pure returns (ExternalCall memory) {
        return ExternalCall(target, value, payload);
    }

    function _forwardCallFromExecutor(
        address forwarder,
        address target,
        bytes memory data
    ) internal pure returns (ExternalCall memory) {
        return _executorCall(
            forwarder, 0, abi.encodeCall(IForwarder.forward, (EvmScriptUtils.encodeEvmCallScript(target, data)))
        );
    }
}
