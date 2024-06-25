// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IResealManger {
    function resume(address sealable) external;
}

library TiebreakerProtection {
    struct Tiebreaker {
        address tiebreaker;
        IResealManger resealManager;
        uint256 tiebreakerProposalApprovalTimelock;
        mapping(uint256 proposalId => uint256) tiebreakerProposalApprovalTimestamp;
    }

    event TiebreakerSet(address tiebreakCommittee);
    event ProposalApprovedForExecution(uint256 proposalId);
    event SealableResumed(address sealable);
    event ResealManagerSet(address resealManager);

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

    function resumeSealable(Tiebreaker storage self, address sealable) internal {
        self.resealManager.resume(sealable);
        emit SealableResumed(sealable);
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

    function setTiebreaker(Tiebreaker storage self, address tiebreaker, address resealManager) internal {
        if (self.tiebreaker == tiebreaker) {
            revert TieBreakerAddressIsSame();
        }

        self.tiebreaker = tiebreaker;
        emit TiebreakerSet(tiebreaker);

        self.resealManager = IResealManger(resealManager);
        emit ResealManagerSet(resealManager);
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
