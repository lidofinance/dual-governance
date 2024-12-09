// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";
import {ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";

contract GovernanceStateTransitions is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});
        _setupStETHBalance(
            _VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1_00)
        );
    }

    function test_signalling_state_min_duration() public {
        _assertNormalState();

        _lockStETH(_VETOER, _dualGovernanceConfigProvider.FIRST_SEAL_RAGE_QUIT_SUPPORT() - PercentsD16.from(1));
        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MIN_DURATION().dividedBy(2));

        _activateNextState();
        _assertVetoSignalingState();

        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MIN_DURATION().dividedBy(2).plusSeconds(1));

        _activateNextState();
        _assertVetoSignalingDeactivationState();
    }

    function test_signalling_state_max_duration() public {
        _assertNormalState();

        _lockStETH(_VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT());

        _assertVetoSignalingState();

        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().dividedBy(2));
        _activateNextState();

        _assertVetoSignalingState();

        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().dividedBy(2));
        _activateNextState();

        _assertVetoSignalingState();

        _lockStETH(_VETOER, 1 gwei);

        _wait(Durations.from(1 seconds));
        _activateNextState();

        _assertRageQuitState();
    }

    function test_signalling_to_normal() public {
        _assertNormalState();

        _lockStETH(_VETOER, _dualGovernanceConfigProvider.FIRST_SEAL_RAGE_QUIT_SUPPORT() - PercentsD16.from(1));

        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoSignalingDeactivationState();

        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoCooldownState();

        vm.startPrank(_VETOER);
        _getVetoSignallingEscrow().unlockStETH();
        vm.stopPrank();

        _wait(_dualGovernanceConfigProvider.VETO_COOLDOWN_DURATION().plusSeconds(1));
        _activateNextState();

        _assertNormalState();
    }

    function test_signalling_non_stop() public {
        _assertNormalState();

        _lockStETH(_VETOER, _dualGovernanceConfigProvider.FIRST_SEAL_RAGE_QUIT_SUPPORT() - PercentsD16.from(1));
        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoSignalingDeactivationState();

        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoCooldownState();

        _wait(_dualGovernanceConfigProvider.VETO_COOLDOWN_DURATION().plusSeconds(1));
        _activateNextState();

        _assertVetoSignalingState();
    }

    function test_signalling_to_rage_quit() public {
        _assertNormalState();

        _lockStETH(_VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT());
        _assertVetoSignalingState();

        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION());
        _activateNextState();

        _assertVetoSignalingState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(Durations.from(1 seconds));
        _activateNextState();
        _assertRageQuitState();
    }
}
