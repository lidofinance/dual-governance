// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IConfiguration} from "../interfaces/IConfiguration.sol";
import {IExecutor, ExecutorCall} from "../interfaces/IExecutor.sol";

import {timestamp} from "../utils/time.sol";

struct Proposal {
    uint256 id;
    address proposer;
    address executor;
    uint256 submittedAt;
    uint256 executedAt;
    bool isCanceled;
    ExecutorCall[] calls;
}

enum ProposalStatus {
    NotExist,
    Submitted,
    Executed,
    Canceled
}

library Proposals {
    struct ProposalPacked {
        address proposer;
        address executor;
        uint40 submittedAt;
        uint40 executedAt;
        ExecutorCall[] calls;
    }

    struct State {
        // any proposals with ids less or equal to the given one cannot be executed
        uint256 lastCanceledProposalId;
        ProposalPacked[] proposals;
    }

    error EmptyCalls();
    error ProposalCanceled(uint256 proposalId);
    error ProposalNotFound(uint256 proposalId);
    error ProposalNotSubmitted(uint256 proposalId);
    error ProposalNotExecutable(uint256 proposalId);

    event ProposalSubmitted(uint256 indexed id, address indexed executor, ExecutorCall[] calls);
    event ProposalExecuted(uint256 indexed id, bytes[] callResults);
    event ProposalsCanceledTill(uint256 proposalId);

    // The id of the first proposal
    uint256 private constant PROPOSAL_ID_OFFSET = 1;

    function submit(
        State storage self,
        address executor,
        ExecutorCall[] calldata calls
    ) internal returns (uint256 newProposalId) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        uint256 newProposalIndex = self.proposals.length;

        self.proposals.push();
        ProposalPacked storage newProposal = self.proposals[newProposalIndex];
        newProposal.executor = executor;

        newProposal.executedAt = 0;
        newProposal.submittedAt = timestamp();

        // copying of arrays of custom types from calldata to storage has not been supported by the
        // Solidity compiler yet, so insert item by item
        for (uint256 i = 0; i < calls.length; ++i) {
            newProposal.calls.push(calls[i]);
        }

        newProposalId = newProposalIndex + PROPOSAL_ID_OFFSET;
        emit ProposalSubmitted(newProposalId, executor, calls);
    }

    function execute(State storage self, IConfiguration config, uint256 proposalId) internal {
        checkProposalSubmitted(self, proposalId);
        _checkAfterSubmitDelayPassed(self, proposalId, config.AFTER_SUBMIT_DELAY());
        _executeProposal(self, proposalId);
    }

    function cancelAll(State storage self) internal {
        uint256 lastProposalId = self.proposals.length;
        self.lastCanceledProposalId = lastProposalId;
        emit ProposalsCanceledTill(lastProposalId);
    }

    function get(State storage self, uint256 proposalId) internal view returns (Proposal memory proposal) {
        _checkProposalExists(self, proposalId);
        ProposalPacked storage packed = _packed(self, proposalId);

        proposal.id = proposalId;
        proposal.proposer = packed.proposer;
        proposal.executor = packed.executor;
        proposal.submittedAt = packed.submittedAt;
        proposal.executedAt = packed.executedAt;
        proposal.isCanceled = _getProposalStatus(self, proposalId) == ProposalStatus.Canceled;
        proposal.calls = packed.calls;
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.proposals.length;
    }

    function canExecute(State storage self, IConfiguration config, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Submitted
            && block.timestamp >= _packed(self, proposalId).submittedAt + config.AFTER_SUBMIT_DELAY();
    }

    function isProposalSubmitted(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Submitted;
    }

    function isProposalCanceled(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Canceled;
    }

    function isProposalExecuted(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Executed;
    }

    function _executeProposal(State storage self, uint256 proposalId) private returns (bytes[] memory results) {
        ProposalPacked storage packed = _packed(self, proposalId);
        packed.executedAt = timestamp();

        ExecutorCall[] memory calls = packed.calls;
        uint256 callsCount = calls.length;

        assert(callsCount > 0);

        address executor = packed.executor;
        results = new bytes[](callsCount);
        for (uint256 i = 0; i < callsCount; ++i) {
            results[i] = IExecutor(payable(executor)).execute(calls[i].target, calls[i].value, calls[i].payload);
        }
        emit ProposalExecuted(proposalId, results);
    }

    function _packed(State storage self, uint256 proposalId) private view returns (ProposalPacked storage packed) {
        packed = self.proposals[proposalId - PROPOSAL_ID_OFFSET];
    }

    function _checkProposalExists(State storage self, uint256 proposalId) private view {
        if (proposalId < PROPOSAL_ID_OFFSET || proposalId > self.proposals.length) {
            revert ProposalNotFound(proposalId);
        }
    }

    function checkProposalSubmitted(State storage self, uint256 proposalId) private view {
        ProposalStatus status = _getProposalStatus(self, proposalId);
        if (status != ProposalStatus.Submitted) {
            revert ProposalNotSubmitted(proposalId);
        }
    }

    function _checkAfterSubmitDelayPassed(
        State storage self,
        uint256 proposalId,
        uint256 afterSubmitDelay
    ) private view {
        if (block.timestamp < _packed(self, proposalId).submittedAt + afterSubmitDelay) {
            revert ProposalNotExecutable(proposalId);
        }
    }

    function _getProposalStatus(State storage self, uint256 proposalId) private view returns (ProposalStatus) {
        if (proposalId < PROPOSAL_ID_OFFSET || proposalId > self.proposals.length) return ProposalStatus.NotExist;

        ProposalPacked storage packed = _packed(self, proposalId);

        if (packed.executedAt != 0) return ProposalStatus.Executed;
        if (proposalId <= self.lastCanceledProposalId) return ProposalStatus.Canceled;
        if (packed.submittedAt != 0) return ProposalStatus.Submitted;
        assert(false);
    }
}
