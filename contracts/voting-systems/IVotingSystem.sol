// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * Voting system adapter.
 *
 * The adapter should not be assigned any permissions over the protocol. If a privileged execution
 * is needed, the adapter should use DualGovernance.forwardCall to request the call from the Agent.
 *
 * The only exception is the permission to submit a proposal to the upstream voting system. If this
 * permission is assigned to an adapter, the adapter should check that the original submitter is
 * allowed to submit the proposal.
 */
interface IVotingSystem {
    function submitProposal(bytes calldata data, address submitter) external returns (uint256 id, uint256 decidedAt);
    function executeProposal(uint256 id, bytes calldata data) external;
    function isValidExecutionForwarder(address addr) external view returns (bool);
}
