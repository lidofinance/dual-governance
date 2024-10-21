pragma solidity 0.8.26;

import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract RageQuitTest is DualGovernanceSetUp {
    function testRageQuitDuration() external {
        vm.assume(dualGovernance.getPersistedState() == State.RageQuit);

        dualGovernance.activateNextState();

        uint40 rageQuitTimelockStartedAt = _getRageQuitExtensionPeriodStartedAt(rageQuitEscrow);
        uint32 rageQuitExtensionDelay = _getRageQuitEthWithdrawalsDelay(rageQuitEscrow);

        if (block.timestamp <= rageQuitTimelockStartedAt + rageQuitExtensionDelay) {
            assert(dualGovernance.getPersistedState() == State.RageQuit);
        }
    }
}
