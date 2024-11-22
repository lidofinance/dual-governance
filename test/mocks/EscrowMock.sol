// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";

import {IEscrow} from "contracts/interfaces/IEscrow.sol";

contract EscrowMock is IEscrow {
    event __RageQuitStarted(Duration rageQuitExtraTimelock, Duration rageQuitWithdrawalsTimelock);

    Duration public __minAssetsLockDuration;
    PercentD16 public __rageQuitSupport;
    bool public __isRageQuitFinalized;

    function __setRageQuitSupport(PercentD16 newRageQuitSupport) external {
        __rageQuitSupport = newRageQuitSupport;
    }

    function __setIsRageQuitFinalized(bool newIsRageQuitFinalized) external {
        __isRageQuitFinalized = newIsRageQuitFinalized;
    }

    function initialize(Duration minAssetsLockDuration) external {
        __minAssetsLockDuration = minAssetsLockDuration;
    }

    function startRageQuit(Duration rageQuitExtraTimelock, Duration rageQuitWithdrawalsTimelock) external {
        emit __RageQuitStarted(rageQuitExtraTimelock, rageQuitWithdrawalsTimelock);
    }

    function isRageQuitFinalized() external view returns (bool) {
        return __isRageQuitFinalized;
    }

    function getRageQuitSupport() external view returns (PercentD16 rageQuitSupport) {
        return __rageQuitSupport;
    }

    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external {
        __minAssetsLockDuration = newMinAssetsLockDuration;
    }

    function getMinAssetsLockDuration() external view returns (Duration minAssetsLockDuration) {
        return __minAssetsLockDuration;
    }
}
