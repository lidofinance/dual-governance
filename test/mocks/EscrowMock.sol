// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";

import {IEscrow} from "contracts/interfaces/IEscrow.sol";

/* solhint-disable custom-errors */
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

    function lockStETH(uint256 /* amount */ ) external returns (uint256 /* lockedStETHShares */ ) {
        revert("Not implemented");
    }

    function unlockStETH() external returns (uint256 /* unlockedStETHShares */ ) {
        revert("Not implemented");
    }

    function lockWstETH(uint256 /* amount */ ) external returns (uint256 /* lockedStETHShares */ ) {
        revert("Not implemented");
    }

    function unlockWstETH() external returns (uint256 /* unlockedStETHShares */ ) {
        revert("Not implemented");
    }

    function lockUnstETH(uint256[] memory /* unstETHIds */ ) external {
        revert("Not implemented");
    }

    function unlockUnstETH(uint256[] memory /* unstETHIds */ ) external {
        revert("Not implemented");
    }

    function markUnstETHFinalized(uint256[] memory, /* unstETHIds */ uint256[] calldata /* hints */ ) external {
        revert("Not implemented");
    }

    function startRageQuit(Duration rageQuitExtensionPeriodDuration, Duration rageQuitEthWithdrawalsDelay) external {
        emit __RageQuitStarted(rageQuitExtensionPeriodDuration, rageQuitEthWithdrawalsDelay);
    }

    function requestNextWithdrawalsBatch(uint256 /* batchSize */ ) external {
        revert("Not implemented");
    }

    function claimNextWithdrawalsBatch(uint256, /* fromUnstETHId */ uint256[] calldata /* hints */ ) external {
        revert("Not implemented");
    }

    function claimNextWithdrawalsBatch(uint256 /* maxUnstETHIdsCount */ ) external {
        revert("Not implemented");
    }

    function startRageQuitExtensionPeriod() external {
        revert("Not implemented");
    }

    function claimUnstETH(uint256[] calldata, /* unstETHIds */ uint256[] calldata /* hints */ ) external {
        revert("Not implemented");
    }

    function withdrawETH() external {
        revert("Not implemented");
    }

    function withdrawETH(uint256[] calldata /* unstETHIds */ ) external {
        revert("Not implemented");
    }

    function getLockedAssetsTotals() external view returns (LockedAssetsTotals memory /* totals */ ) {
        revert("Not implemented");
    }

    function getVetoerState(address /* vetoer */ ) external view returns (VetoerState memory /* state */ ) {
        revert("Not implemented");
    }

    function getUnclaimedUnstETHIdsCount() external view returns (uint256) {
        revert("Not implemented");
    }

    function getNextWithdrawalBatch(uint256 /* limit */ ) external view returns (uint256[] memory /* unstETHIds */ ) {
        revert("Not implemented");
    }

    function isWithdrawalsBatchesClosed() external view returns (bool) {
        revert("Not implemented");
    }

    function isRageQuitExtensionPeriodStarted() external view returns (bool) {
        revert("Not implemented");
    }

    function getRageQuitExtensionPeriodStartedAt() external view returns (Timestamp) {
        revert("Not implemented");
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
}
