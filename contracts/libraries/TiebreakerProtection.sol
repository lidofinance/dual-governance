// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IResealManger {
    function resume(address sealable) external;
}

library TiebreakerProtection {
    struct Tiebreaker {
        address tiebreaker;
        IResealManger resealManager;
    }

    event TiebreakerSet(address tiebreakCommittee, address resealManager);
    event SealableResumed(address sealable);

    error ProposalNotExecutable(uint256 proposalId);
    error NotTiebreaker(address account, address tiebreakCommittee);
    error TieBreakerAddressIsSame();

    function resumeSealable(Tiebreaker storage self, address sealable) internal {
        self.resealManager.resume(sealable);
        emit SealableResumed(sealable);
    }

    function setTiebreaker(Tiebreaker storage self, address tiebreaker, address resealManager) internal {
        if (self.tiebreaker == tiebreaker) {
            revert TieBreakerAddressIsSame();
        }

        self.tiebreaker = tiebreaker;
        self.resealManager = IResealManger(resealManager);
        emit TiebreakerSet(tiebreaker, resealManager);
    }

    function checkTiebreakerCommittee(Tiebreaker storage self, address account) internal view {
        if (account != self.tiebreaker) {
            revert NotTiebreaker(account, self.tiebreaker);
        }
    }
}
