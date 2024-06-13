// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library TiebreakerProtection {
    struct Tiebreaker {
        address tiebreaker;
        uint256 tiebreakerProposalApprovalTimelock;
        mapping(uint256 proposalId => uint256) tiebreakerProposalApprovalTimestamp;
    }

    event TiebreakerSet(address tiebreakCommittee);
    event ProposalApprovedForExecution(uint256 proposalId);
    event SealableResumeApproved(address sealable);

    error ProposalNotExecutable(uint256 proposalId);
    error NotTiebreaker(address account, address tiebreakCommittee);
    error ProposalAlreadyApproved(uint256 proposalId);
    error ProposalIsNotApprovedForExecution(uint256 proposalId);
    error TiebreakerTimelockIsNotPassed(uint256 proposalId);
    error SealableResumeAlreadyApproved(address sealable);
    error TieBreakerAddressIsSame();

    function approveProposal(Tiebreaker storage self, uint256 proposalId) internal {
        if (self.tiebreakerProposalApprovalTimestamp[proposalId] > 0) {
            revert ProposalAlreadyApproved(proposalId);
        }

        _approveProposal(self, proposalId);
    }

    function approveSealableResume(Tiebreaker storage self, uint256 proposalId, address sealable) internal {
        _approveProposal(self, proposalId);
        emit SealableResumeApproved(sealable);
    }

    function canSchedule(Tiebreaker storage self, uint256 proposalId) internal view {
        if (self.tiebreakerProposalApprovalTimestamp[proposalId] == 0) {
            revert ProposalIsNotApprovedForExecution(proposalId);
        }
        if (
            self.tiebreakerProposalApprovalTimestamp[proposalId] + self.tiebreakerProposalApprovalTimelock
                > block.timestamp
        ) {
            revert TiebreakerTimelockIsNotPassed(proposalId);
        }
    }

    function setTiebreaker(Tiebreaker storage self, address tiebreaker) internal {
        if (self.tiebreaker == tiebreaker) {
            revert TieBreakerAddressIsSame();
        }

        self.tiebreaker = tiebreaker;
        emit TiebreakerSet(tiebreaker);
    }

    function checkTiebreakerCommittee(Tiebreaker storage self, address account) internal view {
        if (account != self.tiebreaker) {
            revert NotTiebreaker(account, self.tiebreaker);
        }
    }

    function _approveProposal(Tiebreaker storage self, uint256 proposalId) internal {
        self.tiebreakerProposalApprovalTimestamp[proposalId] = block.timestamp;
        emit ProposalApprovedForExecution(proposalId);
    }
}
