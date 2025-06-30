// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {DGScenarioTestSetup, ExternalCall} from "../utils/integration-tests.sol";

contract DualGovernanceStateTransitions is DGScenarioTestSetup {
    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});
        _setupStETHBalance(_VETOER, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
    }

    function testFork_VetoSignalling_HappyPath_MinDuration() external {
        _assertNormalState();

        _lockStETH(_VETOER, _getFirstSealRageQuitSupport() - PercentsD16.from(1));
        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMinDuration().dividedBy(2));

        _activateNextState();
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMinDuration().dividedBy(2).plusSeconds(1));

        _activateNextState();
        _assertVetoSignallingDeactivationState();
    }

    function testFork_VetoSignalling_HappyPath_MaxDuration() public {
        _assertNormalState();

        _lockStETH(_VETOER, _getSecondSealRageQuitSupport());

        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration().dividedBy(2));
        _activateNextState();

        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration().dividedBy(2));
        _activateNextState();

        _assertVetoSignalingState();

        _lockStETH(_VETOER, 1 gwei);

        _wait(Durations.from(1 seconds));
        _activateNextState();

        _assertRageQuitState();
    }

    function testFork_VetoSignalling_HappyPath_TransitionToNormal() public {
        _assertNormalState();

        _lockStETH(_VETOER, _getFirstSealRageQuitSupport() - PercentsD16.from(1));

        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoSignallingDeactivationState();

        _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoCooldownState();

        vm.startPrank(_VETOER);
        _getVetoSignallingEscrow().unlockStETH();
        vm.stopPrank();

        _wait(_getVetoCooldownDuration().plusSeconds(1));
        _activateNextState();

        _assertNormalState();
    }

    function testFork_VetoSignalling_HappyPath_VetoCooldownLoop() public {
        _assertNormalState();

        _lockStETH(_VETOER, _getFirstSealRageQuitSupport() - PercentsD16.from(1));
        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoSignallingDeactivationState();

        _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoCooldownState();

        _wait(_getVetoCooldownDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoSignalingState();
    }

    function testFork_VetoSignalling_HappyPath_ToRageQuit() public {
        _assertNormalState();

        _lockStETH(_VETOER, _getSecondSealRageQuitSupport());
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration());
        _activateNextState();

        _assertVetoSignalingState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(Durations.from(1 seconds));
        _activateNextState();
        _assertRageQuitState();
    }
}
