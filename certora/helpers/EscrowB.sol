// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../contracts/Escrow.sol";
import {State as EscrowStateInner} from "../../contracts/libraries/EscrowState.sol";

contract EscrowB is Escrow {
    constructor(
        IStETH stETH,
        IWstETH wstETH,
        IWithdrawalQueue withdrawalQueue,
        IDualGovernance dualGovernance,
        uint256 minWithdrawalsBatchSize,
        Duration maxMinAssetsLockDuration
    ) Escrow(stETH, wstETH, withdrawalQueue, dualGovernance, minWithdrawalsBatchSize, maxMinAssetsLockDuration) {}

    function isRageQuitState() external returns (bool) {
        return _escrowState.state == EscrowStateInner.RageQuitEscrow;
    }
}
