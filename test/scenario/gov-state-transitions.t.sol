// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ScenarioTestBlueprint, percents, Durations} from "../utils/scenario-test-blueprint.sol";

contract GovernanceStateTransitions is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _selectFork();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);
        _depositStETH(_VETOER, 1 ether);
    }

    function test_signalling_state_min_duration() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents(_config.FIRST_SEAL_RAGE_QUIT_SUPPORT()));
        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_config.DYNAMIC_TIMELOCK_MIN_DURATION().dividedBy(2));

        _activateNextState();
        _assertVetoSignalingState();

        _wait(_config.DYNAMIC_TIMELOCK_MIN_DURATION().dividedBy(2).plusSeconds(1));

        _activateNextState();
        _assertVetoSignalingDeactivationState();
    }

    function test_signalling_state_max_duration() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents(_config.SECOND_SEAL_RAGE_QUIT_SUPPORT()));

        _assertVetoSignalingState();

        _wait(_config.DYNAMIC_TIMELOCK_MAX_DURATION().dividedBy(2));
        _activateNextState();

        _assertVetoSignalingState();

        _wait(_config.DYNAMIC_TIMELOCK_MAX_DURATION().dividedBy(2));
        _activateNextState();

        _assertVetoSignalingState();

        _lockStETH(_VETOER, 1 gwei);

        _wait(Durations.from(1 seconds));
        _activateNextState();

        _assertRageQuitState();
    }

    function test_signalling_to_normal() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents(_config.FIRST_SEAL_RAGE_QUIT_SUPPORT()));

        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_config.DYNAMIC_TIMELOCK_MIN_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoSignalingDeactivationState();

        _wait(_config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoCooldownState();

        vm.startPrank(_VETOER);
        _getVetoSignallingEscrow().unlockStETH();
        vm.stopPrank();

        _wait(_config.VETO_COOLDOWN_DURATION().plusSeconds(1));
        _activateNextState();

        _assertNormalState();
    }

    function test_signalling_non_stop() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents(_config.FIRST_SEAL_RAGE_QUIT_SUPPORT()));
        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_config.DYNAMIC_TIMELOCK_MIN_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoSignalingDeactivationState();

        _wait(_config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoCooldownState();

        _wait(_config.VETO_COOLDOWN_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoSignalingState();
    }

    function test_signalling_to_rage_quit() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents(_config.SECOND_SEAL_RAGE_QUIT_SUPPORT()));
        _assertVetoSignalingState();

        _wait(_config.DYNAMIC_TIMELOCK_MAX_DURATION());
        _activateNextState();

        _assertVetoSignalingState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(Durations.from(1 seconds));
        _activateNextState();
        _assertRageQuitState();
    }
}
