// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {TimelockExecutor} from "./TimelockExecutor.sol";

enum ProposalStatus {
    NotProposed,
    Proposed,
    Enqueued,
    Executed,
    Canceled,
    Dequeued
}

struct Proposal {
    uint256 id;
    ProposalStatus status;
    uint256 statusChangedAt;
    address executor;
    address[] targets;
    uint256[] values;
    // TODO: Decide should the payloads include 4bytes method ids or pass signatures in a
    // standalone array and calculate the method id onchain.
    // The second option more gas expensive but provides more transparency, because signature
    // is human readable
    bytes[] payloads;
}

library Proposals {
    using SafeCast for uint256;

    struct ProposalState {
        ProposalStatus status;
        uint40 enteredAt;
    }

    struct ProposalPacked {
        uint24 id;
        ProposalState state;
        address executor;
        address[] targets;
        uint256[] values;
        // TODO: Decide should the payloads include 4bytes method ids or pass signatures in a
        // standalone array and calculate the method id onchain.
        // The second option more gas expensive but provides more transparency, because signature
        // is human readable
        bytes[] payloads;
    }

    // TODO: Decide start counting ids from 0 or 1
    struct State {
        uint24 proposalsCount;
        // all proposals with ids less or equal than given one cannot be queued
        uint24 lastCanceledProposalId;
        // all queued proposals with ids less or equal than given cannot be executed
        uint24 lastDequeuedProposalId;
        mapping(uint256 id => ProposalPacked proposal) proposals;
    }

    event Proposed(
        uint256 indexed id,
        address indexed executor,
        address[] targets,
        uint256[] valued,
        bytes[] payloads
    );

    event Queued(uint256 indexed id);
    event Executed(uint256 indexed id);
    event ProposalsCanceledTill(uint256 lastCanceledProposalId);
    event ProposalsDequeuedTill(uint256 lasDequeuedProposalId);

    error EmptyProposal();
    error InvalidExecutorAddress(address executor);
    error ProposalItemsLengthMismatch(
        uint256 targetsLength,
        uint256 valuesLength,
        uint256 payloadsLength
    );
    error InvalidProposalStatus(ProposalStatus actual, ProposalStatus expected);
    error ExecutionTimeLocked(uint256 currentTime, uint256 executableAt);
    error ProposalIsNotReady();

    function cancelAllProposals(State storage self) internal {
        self.lastCanceledProposalId = self.proposalsCount;
        emit ProposalsCanceledTill(self.lastCanceledProposalId);
    }

    function dequeueAllProposals(State storage self) internal {
        self.lastDequeuedProposalId = self.proposalsCount;
        emit ProposalsDequeuedTill(self.lastDequeuedProposalId);
    }

    function propose(
        State storage self,
        address executor,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads
    ) internal returns (uint256) {
        if (executor == address(0)) {
            revert InvalidExecutorAddress(executor);
        }

        if (targets.length != values.length || targets.length != payloads.length) {
            revert ProposalItemsLengthMismatch(targets.length, values.length, payloads.length);
        }

        if (targets.length == 0) {
            revert EmptyProposal();
        }

        uint24 newProposalId = ++self.proposalsCount;
        ProposalPacked storage newProposal = self.proposals[newProposalId];
        newProposal.id = newProposalId;
        newProposal.executor = executor;
        newProposal.state = ProposalState({
            status: ProposalStatus.Proposed,
            enteredAt: block.timestamp.toUint40()
        });
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.payloads = payloads;
        emit Proposed(newProposalId, executor, targets, values, payloads);
        return newProposalId;
    }

    // waitBeforeEnqueue - time required proposal was in state Proposed before being transitioned
    // into Queued state
    function enqueue(State storage self, uint256 proposalId, uint256 waitBeforeEnqueue) internal {
        ProposalPacked storage proposal = self.proposals[proposalId];
        ProposalState memory state = proposal.state;

        if (state.status != ProposalStatus.Proposed) {
            revert InvalidProposalStatus(state.status, ProposalStatus.Proposed);
        }
        if (_isCanceled(self, proposalId)) {
            revert InvalidProposalStatus(ProposalStatus.Canceled, ProposalStatus.Proposed);
        }

        if (block.timestamp < state.enteredAt + waitBeforeEnqueue) {
            revert ProposalIsNotReady();
        }
        proposal.state = ProposalState({
            status: ProposalStatus.Enqueued,
            enteredAt: block.timestamp.toUint40()
        });
        emit Queued(proposalId);
    }

    function execute(State storage self, uint256 proposalId, uint256 delay) internal {
        ProposalPacked storage proposal = self.proposals[proposalId];
        ProposalState memory state = proposal.state;

        if (state.status != ProposalStatus.Enqueued) {
            revert InvalidProposalStatus(state.status, ProposalStatus.Proposed);
        }
        if (_isDequeued(self, proposalId)) {
            revert InvalidProposalStatus(ProposalStatus.Dequeued, ProposalStatus.Proposed);
        }
        if (block.timestamp < state.enteredAt + delay) {
            revert ExecutionTimeLocked(block.timestamp, state.enteredAt + delay);
        }
        proposal.state = ProposalState({
            status: ProposalStatus.Executed,
            enteredAt: block.timestamp.toUint40()
        });
        _makeCalls(proposal.executor, proposal.targets, proposal.values, proposal.payloads);
        emit Executed(proposalId);
    }

    function get(
        State storage self,
        uint256 proposalId
    ) internal view returns (Proposal memory proposal) {
        ProposalPacked storage storedProposal = self.proposals[proposalId];
        proposal.id = storedProposal.id;
        proposal.executor = storedProposal.executor;
        proposal.status = _getProposalStatus(self, proposalId);
        proposal.statusChangedAt = storedProposal.state.enteredAt;
        proposal.targets = storedProposal.targets;
        proposal.values = storedProposal.values;
        proposal.payloads = storedProposal.payloads;
    }

    function isProposed(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Proposed;
    }

    function isEnqueued(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Enqueued;
    }

    function isExecutable(
        State storage self,
        uint256 proposalId,
        uint256 delay
    ) internal view returns (bool) {
        if (_getProposalStatus(self, proposalId) != ProposalStatus.Enqueued) return false;
        ProposalState memory state = self.proposals[proposalId].state;
        return block.timestamp >= state.enteredAt + delay;
    }

    function isExecuted(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Executed;
    }

    function isDequeued(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Dequeued;
    }

    function isCanceled(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Canceled;
    }

    function _makeCalls(
        address executor,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads
    ) private {
        assert(targets.length > 0);
        assert(targets.length == values.length && values.length == payloads.length);

        for (uint256 i = 0; i < targets.length; ) {
            Address.functionCallWithValue(
                executor,
                abi.encodeCall(
                    TimelockExecutor(executor).call,
                    (targets[i], values[i], payloads[i])
                ),
                values[i]
            );
            unchecked {
                ++i;
            }
        }
    }

    function _getProposalStatus(
        State storage self,
        uint256 proposalId
    ) private view returns (ProposalStatus status) {
        ProposalState memory state = self.proposals[proposalId].state;
        if (state.status == ProposalStatus.Proposed && _isCanceled(self, proposalId)) {
            status = ProposalStatus.Canceled;
        } else if (state.status == ProposalStatus.Enqueued && _isDequeued(self, proposalId)) {
            status = ProposalStatus.Dequeued;
        } else {
            status = state.status;
        }
    }

    function _isCanceled(State storage self, uint256 proposalId) private view returns (bool) {
        return self.lastCanceledProposalId >= proposalId;
    }

    function _isDequeued(State storage self, uint256 proposalId) private view returns (bool) {
        return self.lastDequeuedProposalId >= proposalId;
    }
}
