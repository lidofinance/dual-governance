pragma solidity 0.8.26;

import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract VetoCooldownTest is DualGovernanceSetUp {
    function testVetoCooldownDuration() external {
        vm.assume(dualGovernance.getPersistedState() == State.VetoCooldown);
        Timestamp timeEnteredAt = Timestamp.wrap(_getEnteredAt(dualGovernance));
        Timestamp maxCooldownDuration = addTo(config.VETO_COOLDOWN_DURATION(), timeEnteredAt);

        dualGovernance.activateNextState();

        bool stillInVetoCooldown = (dualGovernance.getPersistedState() == State.VetoCooldown);
        bool durationHasElapsed = (Timestamps.now() > maxCooldownDuration);
        assert(stillInVetoCooldown != durationHasElapsed);
    }
}
