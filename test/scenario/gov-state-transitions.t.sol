// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ScenarioTestBlueprint, percents} from "../utils/scenario-test-blueprint.sol";

contract GovernanceStateTransitions is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _selectFork();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);
    }

    function test_signalling_state_min_duration() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents("3.00"));
        _assertVetoSignalingState();

        _wait(_config.SIGNALLING_MIN_DURATION() / 2);

        _activateNextState();
        _assertVetoSignalingState();

        _wait(_config.SIGNALLING_MIN_DURATION() / 2 + 1);

        _activateNextState();
        _assertVetoSignalingDeactivationState();
    }

    function test_signalling_state_max_duration() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents("15.0"));

        _assertVetoSignalingState();

        _wait(_config.SIGNALLING_MAX_DURATION() / 2);
        _activateNextState();

        _assertVetoSignalingState();

        _wait(_config.SIGNALLING_MAX_DURATION() / 2 + 1);
        _activateNextState();

        _assertRageQuitState();
    }

    function test_signalling_to_normal() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents("3.00"));

        _assertVetoSignalingState();

        _wait(_config.SIGNALLING_MIN_DURATION());
        _activateNextState();

        _assertVetoSignalingDeactivationState();

        _wait(_config.SIGNALLING_DEACTIVATION_DURATION());
        _activateNextState();

        _assertVetoCooldownState();

        vm.startPrank(_VETOER);
        _getSignallingEscrow().unlockStETH();
        vm.stopPrank();

        _wait(_config.SIGNALLING_COOLDOWN_DURATION());
        _activateNextState();

        _assertNormalState();
    }

    function test_signalling_non_stop() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents("3.00"));

        _assertVetoSignalingState();

        _wait(_config.SIGNALLING_MIN_DURATION());
        _activateNextState();

        _assertVetoSignalingDeactivationState();

        _wait(_config.SIGNALLING_DEACTIVATION_DURATION());
        _activateNextState();

        _assertVetoCooldownState();

        _wait(_config.SIGNALLING_COOLDOWN_DURATION());
        _activateNextState();

        _assertVetoSignalingState();
    }

    function test_signalling_to_rage_quit() public {
        _assertNormalState();

        _lockStETH(_VETOER, percents("15.00"));
        _assertVetoSignalingState();

        _wait(_config.SIGNALLING_MAX_DURATION());
        _activateNextState();

        _assertRageQuitState();
    }
}
