pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract RageQuitTest is DualGovernanceSetUp {
    function testRageQuitDuration() external {
        vm.assume(dualGovernance.getCurrentState() == State.RageQuit);

        dualGovernance.activateNextState();

        uint40 rageQuitTimelockStartedAt = _getRageQuitTimelockStartedAt(rageQuitEscrow);
        uint32 rageQuitExtensionDelay = _getRageQuitExtensionDelay(rageQuitEscrow);

        if (block.timestamp <= rageQuitTimelockStartedAt + rageQuitExtensionDelay) {
            assert(dualGovernance.getCurrentState() == State.RageQuit);
        }
    }
}
