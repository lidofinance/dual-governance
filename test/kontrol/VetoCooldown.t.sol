pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract VetoCooldownTest is DualGovernanceSetUp {
    function testVetoCooldownDuration() external {
        vm.assume(dualGovernance.currentState() == State.VetoCooldown);

        bool stillInVetoCooldown = (dualGovernance.currentState() == State.VetoCooldown);
        bool durationHasElapsed = (block.timestamp - _getEnteredAt(dualGovernance) > config.VETO_COOLDOWN_DURATION());
        assert(stillInVetoCooldown == durationHasElapsed);
    }
}
