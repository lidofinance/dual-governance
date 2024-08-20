// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {IEscrow} from "contracts/interfaces/IEscrow.sol";
import {Duration} from "contracts/types/Duration.sol";

/* solhint-disable no-unused-vars,custom-errors */
contract DualGovernanceMock is IDualGovernance {
    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId) {
        revert("Not Implemented");
    }

    function scheduleProposal(uint256 proposalId) external {
        revert("Not Implemented");
    }

    function cancelAllPendingProposals() external {
        revert("Not Implemented");
    }

    function canScheduleProposal(uint256 proposalId) external view returns (bool) {
        revert("Not Implemented");
    }

    function activateNextState() external {
        revert("Not Implemented");
    }

    function resealSealable(address sealables) external {
        revert("Not Implemented");
    }

    function tiebreakerScheduleProposal(uint256 proposalId) external {
        revert("Not Implemented");
    }

    function tiebreakerResumeSealable(address sealable) external {
        revert("Not Implemented");
    }

    function initializeEscrow(IEscrow instance, Duration minAssetsLockDuration) external {
        instance.initialize(minAssetsLockDuration);
    }

    function startRageQuitForEscrow(
        IEscrow instance,
        Duration rageQuitExtensionDelay,
        Duration rageQuitWithdrawalsTimelock
    ) external {
        instance.startRageQuit(rageQuitExtensionDelay, rageQuitWithdrawalsTimelock);
    }

    function setMinAssetsLockDurationForEscrow(IEscrow instance, Duration newMinAssetsLockDuration) external {
        instance.setMinAssetsLockDuration(newMinAssetsLockDuration);
    }
}
