// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {EvmScriptUtils} from "test/utils/evm-script-utils.sol";

import {IForwarder} from "./interfaces/IForwarder.sol";
import {IVoting} from "./interfaces/IVoting.sol";

// @title OmnibusBase
// @notice Abstract base contract for creating votes for the Aragon Voting.
//
// Inheriting contracts must implement:
// - getVoteItems() - to define the specific actions in the proposal
// - _voteItemsCount() - to specify the number of vote items
// - _voting() - to specify the Aragon Voting contract address
// - _forwarder() - to specify the Forwarder (Aragon Agent) contract address
abstract contract OmnibusBase {
    // @notice A structure that represents a single voting item in a governance proposal.
    // @dev This struct is designed to match the format required by the Lido scripts repository
    //      for compatibility with the voting tooling.
    // @param description Human-readable description of the voting item.
    // @param call The EVM script call containing the target contract address and calldata.
    struct VoteItem {
        string description;
        EvmScriptUtils.EvmScriptCall call;
    }

    // @return VoteItem[] The list of voting items to be executed by Aragon Voting.
    function getVoteItems() public view virtual returns (VoteItem[] memory);

    // @return The address of the voting contract.
    function _voting() internal pure virtual returns (address);

    // @return Returns the address of the forwarder contract.
    function _forwarder() internal pure virtual returns (address);

    // @return The number of vote items in the proposal.
    function _voteItemsCount() internal pure virtual returns (uint256);

    // @notice Converts all vote items to the Aragon-compatible EVMCallScript to validate against.
    // @return _evmCallScript A bytes containing encoded EVMCallScript.
    function getEVMCallScript() external view returns (bytes memory) {
        uint256 voteItemsCount = _voteItemsCount();

        EvmScriptUtils.EvmScriptCall[] memory allCalls = new EvmScriptUtils.EvmScriptCall[](voteItemsCount);
        VoteItem[] memory voteItems = this.getVoteItems();

        for (uint256 i = 0; i < voteItems.length; i++) {
            allCalls[i] = voteItems[i].call;
        }

        return EvmScriptUtils.encodeEvmCallScript(allCalls);
    }

    // @notice Validates the specific vote on Aragon Voting contract.
    // @return A boolean value indicating whether the vote is valid.
    function validateVote(uint256 voteId) internal view returns (bool) {
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
        ) = IVoting(_voting()).getVote(voteId);
        return keccak256(script) == keccak256(this.getEVMCallScript());
    }

    function _votingCall(
        address target,
        bytes memory data
    ) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return EvmScriptUtils.EvmScriptCall(target, data);
    }

    function _forwardCall(
        address target,
        bytes memory data
    ) internal pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return _votingCall(
            _forwarder(), abi.encodeCall(IForwarder.forward, (EvmScriptUtils.encodeEvmCallScript(target, data)))
        );
    }

    function _executorCall(address target, bytes memory payload) internal pure returns (ExternalCall memory) {
        return ExternalCall(target, 0, payload);
    }

    function _forwardCallFromExecutor(address target, bytes memory data) internal pure returns (ExternalCall memory) {
        return _executorCall(
            _forwarder(), abi.encodeCall(IForwarder.forward, (EvmScriptUtils.encodeEvmCallScript(target, data)))
        );
    }
}
