// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IResealManager} from "../interfaces/IResealManager.sol";

library Resealer {
    error InvalidResealManager(address resealManager);
    error InvalidResealCommittee(address resealCommittee);
    error CallerIsNotResealCommittee(address caller);

    event ResealCommitteeSet(address resealCommittee);
    event ResealManagerSet(address resealManager);

    struct Context {
        /// @dev The address of the Reseal Manager.
        IResealManager resealManager;
        /// @dev The address of the Reseal Committee which is allowed to "reseal" sealables paused for a limited
        ///      period of time when the Dual Governance proposal adoption is blocked.
        address resealCommittee;
    }

    function setResealManager(Context storage self, address newResealManager) internal {
        if (newResealManager == address(self.resealManager) || newResealManager == address(0)) {
            revert InvalidResealManager(newResealManager);
        }
        self.resealManager = IResealManager(newResealManager);
        emit ResealManagerSet(newResealManager);
    }

    function setResealCommittee(Context storage self, address newResealCommittee) internal {
        if (newResealCommittee == self.resealCommittee) {
            revert InvalidResealCommittee(newResealCommittee);
        }
        self.resealCommittee = newResealCommittee;
        emit ResealCommitteeSet(newResealCommittee);
    }

    function reseal(Context storage self, address sealable) internal {
        if (msg.sender != self.resealCommittee) {
            revert CallerIsNotResealCommittee(msg.sender);
        }
        self.resealManager.reseal(sealable);
    }

    function resume(Context storage self, address sealable) internal {
        self.resealManager.resume(sealable);
    }
}
