pragma solidity 0.8.23;

import {State} from "contracts/libraries/DualGovernanceState.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract ActivateNextStateTest is DualGovernanceSetUp {
    function testEscrowStateTransition() public {
        State initialState = dualGovernance.getCurrentState();
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();

        dualGovernance.activateNextState();

        if (
            (initialState == State.VetoSignalling || initialState == State.VetoSignallingDeactivation)
                && rageQuitSupport > config.SECOND_SEAL_RAGE_QUIT_SUPPORT()
        ) {
            assert(_getCurrentState(signallingEscrow) == EscrowState.RageQuitEscrow);
        } else {
            assert(_getCurrentState(signallingEscrow) == EscrowState.SignallingEscrow);
        }
    }
}
