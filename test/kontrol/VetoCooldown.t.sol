pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract VetoCooldownTest is DualGovernanceSetUp {
    function testVetoCooldownDuration() external {
        vm.assume(dualGovernance.getCurrentState() == State.VetoCooldown);

        dualGovernance.activateNextState();

        bool stillInVetoCooldown = (dualGovernance.getCurrentState() == State.VetoCooldown);
        Timestamp timeEnteredAt = Timestamp.wrap(_getEnteredAt(dualGovernance));
        Duration timeInVetoCooldown = Durations.between(Timestamps.now(), timeEnteredAt);
        bool durationHasElapsed = (timeInVetoCooldown > config.VETO_COOLDOWN_DURATION());
        assert(stillInVetoCooldown == durationHasElapsed);
    }
}
