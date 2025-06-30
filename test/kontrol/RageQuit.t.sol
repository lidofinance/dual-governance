pragma solidity 0.8.26;

import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract RageQuitTest is DualGovernanceSetUp {
    function testRageQuitDuration() external {
        vm.assume(dualGovernance.getPersistedState() == State.RageQuit);

        dualGovernance.activateNextState();

        uint40 rageQuitExtensionPeriodStartedAt = _getRageQuitExtensionPeriodStartedAt(rageQuitEscrow);
        uint32 rageQuitExtensionPeriodDuration = _getRageQuitExtensionPeriodDuration(rageQuitEscrow);

        if (block.timestamp <= rageQuitExtensionPeriodStartedAt + rageQuitExtensionPeriodDuration) {
            assert(dualGovernance.getPersistedState() == State.RageQuit);
        }
    }
}
