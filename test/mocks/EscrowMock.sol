// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";

import {IEscrowBase} from "contracts/interfaces/IEscrowBase.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";

import {State as EscrowState} from "contracts/libraries/EscrowState.sol";

contract EscrowMock is ISignallingEscrow, IRageQuitEscrow {
    IEscrowBase public immutable ESCROW_MASTER_COPY = this;

    event __RageQuitStarted(Duration rageQuitExtraTimelock, Duration rageQuitWithdrawalsTimelock);

    Duration public __minAssetsLockDuration;
    PercentD16 public __rageQuitSupport;
    bool public __isRageQuitFinalized;

    function initialize(Duration minAssetsLockDuration) external {
        __minAssetsLockDuration = minAssetsLockDuration;
    }

    function getEscrowState() external view returns (EscrowState) {
        revert("Not implemented");
    }

    function getVetoerDetails(address vetoer) external view returns (VetoerDetails memory) {
        revert("Not implemented");
    }

    function getVetoerUnstETHIds(address vetoer) external view returns (uint256[] memory) {
        revert("Not implemented");
    }

    // ---
    // Signalling Escrow Methods
    // ---

    function lockStETH(uint256 amount) external returns (uint256 lockedStETHShares) {
        revert("Not implemented");
    }

    function unlockStETH() external returns (uint256 unlockedStETHShares) {
        revert("Not implemented");
    }

    function lockWstETH(uint256 amount) external returns (uint256 lockedStETHShares) {
        revert("Not implemented");
    }

    function unlockWstETH() external returns (uint256 wstETHUnlocked) {
        revert("Not implemented");
    }

    function lockUnstETH(uint256[] memory unstETHIds) external {
        revert("Not implemented");
    }

    function unlockUnstETH(uint256[] memory unstETHIds) external {
        revert("Not implemented");
    }

    function markUnstETHFinalized(uint256[] memory unstETHIds, uint256[] calldata hints) external {
        revert("Not implemented");
    }

    function startRageQuit(
        Duration rageQuitExtraTimelock,
        Duration rageQuitWithdrawalsTimelock
    ) external returns (IRageQuitEscrow) {
        emit __RageQuitStarted(rageQuitExtraTimelock, rageQuitWithdrawalsTimelock);
        return this;
    }

    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external {
        __minAssetsLockDuration = newMinAssetsLockDuration;
    }

    function getRageQuitSupport() external view returns (PercentD16 rageQuitSupport) {
        return __rageQuitSupport;
    }

    function getMinAssetsLockDuration() external view returns (Duration) {
        revert("Not implemented");
    }

    function getLockedUnstETHDetails(uint256[] calldata unstETHIds)
        external
        view
        returns (LockedUnstETHDetails[] memory)
    {
        revert("Not implemented");
    }

    function getSignallingEscrowDetails() external view returns (SignallingEscrowDetails memory) {
        revert("Not implemented");
    }

    // ---
    // Rage Quit Escrow
    // ---

    function requestNextWithdrawalsBatch(uint256 batchSize) external {
        revert("Not implemented");
    }

    function claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] calldata hints) external {
        revert("Not implemented");
    }

    function claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount) external {
        revert("Not implemented");
    }

    function claimUnstETH(uint256[] calldata unstETHIds, uint256[] calldata hints) external {
        revert("Not implemented");
    }

    function startRageQuitExtensionPeriod() external {
        revert("Not implemented");
    }

    function withdrawETH() external {
        revert("Not implemented");
    }

    function withdrawETH(uint256[] calldata unstETHIds) external {
        revert("Not implemented");
    }

    function isRageQuitFinalized() external view returns (bool) {
        return __isRageQuitFinalized;
    }

    function getRageQuitEscrowDetails() external view returns (RageQuitEscrowDetails memory) {
        revert("Not implemented");
    }

    function getNextWithdrawalBatch(uint256 limit) external view returns (uint256[] memory unstETHIds) {
        revert("Not implemented");
    }

    // ---
    // Mock methods
    // ---

    function __setRageQuitSupport(PercentD16 newRageQuitSupport) external {
        __rageQuitSupport = newRageQuitSupport;
    }

    function __setIsRageQuitFinalized(bool newIsRageQuitFinalized) external {
        __isRageQuitFinalized = newIsRageQuitFinalized;
    }
}
