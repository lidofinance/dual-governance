// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";

interface ITiebreaker {
    struct TiebreakerDetails {
        bool isTie;
        address tiebreakerCommittee;
        Duration tiebreakerActivationTimeout;
        address[] sealableWithdrawalBlockers;
    }

    function addTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker) external;
    function removeTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker) external;
    function setTiebreakerCommittee(address tiebreakerCommittee) external;
    function setTiebreakerActivationTimeout(Duration tiebreakerActivationTimeout) external;
    function tiebreakerScheduleProposal(uint256 proposalId) external;
    function tiebreakerResumeSealable(address sealable) external;
}
