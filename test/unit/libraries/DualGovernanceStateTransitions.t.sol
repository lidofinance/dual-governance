// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

import {IEscrowBase} from "contracts/interfaces/IEscrowBase.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";

import {
    State,
    DualGovernanceStateMachine,
    DualGovernanceStateTransitions
} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {
    DualGovernanceConfig,
    ImmutableDualGovernanceConfigProvider
} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {stdError} from "forge-std/StdError.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract DualGovernanceStateTransitionsUnitTestSuite is UnitTest {
    using DualGovernanceConfig for DualGovernanceConfig.Context;
    using DualGovernanceStateTransitions for DualGovernanceStateMachine.Context;

    DualGovernanceStateMachine.Context internal _stateMachine;
    ImmutableDualGovernanceConfigProvider internal _configProvider;
    address internal _escrowMasterCopyMock = makeAddr("ESCROW_MOCK");

    function setUp() external {
        _configProvider = new ImmutableDualGovernanceConfigProvider(
            DualGovernanceConfig.Context({
                firstSealRageQuitSupport: PercentsD16.fromBasisPoints(3_00), // 3%
                secondSealRageQuitSupport: PercentsD16.fromBasisPoints(15_00), // 15%
                //
                minAssetsLockDuration: Durations.from(5 hours),
                //
                vetoSignallingMinDuration: Durations.from(3 days),
                vetoSignallingMaxDuration: Durations.from(30 days),
                vetoSignallingMinActiveDuration: Durations.from(5 hours),
                vetoSignallingDeactivationMaxDuration: Durations.from(5 days),
                //
                vetoCooldownDuration: Durations.from(4 days),
                //
                rageQuitExtensionPeriodDuration: Durations.from(7 days),
                rageQuitEthWithdrawalsMinDelay: Durations.from(30 days),
                rageQuitEthWithdrawalsMaxDelay: Durations.from(180 days),
                rageQuitEthWithdrawalsDelayGrowth: Durations.from(15 days)
            })
        );
        DualGovernanceStateMachine.initialize(_stateMachine, _configProvider, IEscrowBase(_escrowMasterCopyMock));
        _setMockRageQuitSupportInBP(0);
    }

    // ---
    // getStateTransition()
    // ---

    // ---
    // Normal -> Normal
    // ---

    function test_getStateTransition_FromNormalToNormal() external {
        assertEq(_stateMachine.state, State.Normal);

        _setMockRageQuitSupportInBP(2_99);

        (State current, State next) = _stateMachine.getStateTransition(_configProvider.getDualGovernanceConfig());

        assertEq(current, State.Normal);
        assertEq(next, State.Normal);
    }

    // ---
    // Normal -> VetoSignalling
    // ---

    function test_getStateTransition_FromNormalToVetoSignalling() external {
        assertEq(_stateMachine.state, State.Normal);

        _setMockRageQuitSupportInBP(3_00);

        (State current, State next) = _stateMachine.getStateTransition(_configProvider.getDualGovernanceConfig());

        assertEq(current, State.Normal);
        assertEq(next, State.VetoSignalling);
    }

    // ---
    // VetoSignalling -> VetoSignalling (veto signalling still in progress)
    // ---

    function test_getStateTransition_FromVetoSignallingToVetoSignalling_VetoSignallingDurationNotPassed() external {
        _setupVetoSignallingState();
        _setMockRageQuitSupportInBP(3_00);

        (State current, State next) = _stateMachine.getStateTransition(_configProvider.getDualGovernanceConfig());

        assertEq(current, State.VetoSignalling);
        assertEq(next, State.VetoSignalling);
    }

    // ---
    // VetoSignalling -> VetoSignalling (min veto signalling duration not passed)
    // ---

    function test_getStateTransition_FromVetoSignallingToVetoSignalling_VetoSignallingReactivationNotPassed()
        external
    {
        _setMockRageQuitSupportInBP(3_00);

        // the veto signalling state was entered
        _setupVetoSignallingState();

        // wait until the duration of the veto signalling is over
        _wait(_calcVetoSignallingDuration().plusSeconds(1));

        // when the duration is over the VetoSignallingDeactivation state must be entered
        _assertStateMachineTransition({from: State.VetoSignalling, to: State.VetoSignallingDeactivation});

        // simulate the reactivation of the VetoSignallingState
        _stateMachine.vetoSignallingReactivationTime = Timestamps.now();

        // while the min veto signalling active duration hasn't passed the VetoSignalling can't be exited
        _wait(_configProvider.VETO_SIGNALLING_MIN_ACTIVE_DURATION().dividedBy(2));

        _assertStateMachineTransition({from: State.VetoSignalling, to: State.VetoSignalling});

        // but when the duration has passed, the next state should be VetoSignallingDeactivation
        _wait(_configProvider.VETO_SIGNALLING_MIN_ACTIVE_DURATION().dividedBy(2).plusSeconds(1));

        _assertStateMachineTransition({from: State.VetoSignalling, to: State.VetoSignallingDeactivation});
    }

    // ---
    // VetoSignalling -> RageQuit
    // ---

    function test_getStateTransition_FromVetoSignallingToRageQuit() external {
        _setMockRageQuitSupportInBP(15_00);

        // the veto signalling state was entered
        _setupVetoSignallingState();

        // while the full duration of the veto signalling hasn't passed the state machine stays in the VetoSignalling state
        _wait(_calcVetoSignallingDuration().dividedBy(2));

        _assertStateMachineTransition({from: State.VetoSignalling, to: State.VetoSignalling});

        // when the full duration has passed the state machine should transition to the Rage Quit
        _wait(_calcVetoSignallingDuration().dividedBy(2).plusSeconds(1));

        _assertStateMachineTransition({from: State.VetoSignalling, to: State.RageQuit});
    }

    // ---
    // VetoSignallingDeactivation -> VetoSignalling
    // ---

    function test_getStateTransition_FromVetoSignallingDeactivationToVetoSignalling() external {
        _setMockRageQuitSupportInBP(3_00);
        _setupVetoSignallingDeactivationState();

        _assertStateMachineTransition({from: State.VetoSignallingDeactivation, to: State.VetoSignallingDeactivation});

        _setMockRageQuitSupportInBP(15_00);

        _assertStateMachineTransition({from: State.VetoSignallingDeactivation, to: State.VetoSignalling});
    }

    // ---
    // VetoSignallingDeactivation -> RageQuit
    // ---

    function test_getStateTransition_FromVetoSignallingDeactivationToRageQuit() external {
        _setMockRageQuitSupportInBP(3_00);
        _setupVetoSignallingDeactivationState();

        _assertStateMachineTransition({from: State.VetoSignallingDeactivation, to: State.VetoSignallingDeactivation});

        _setMockRageQuitSupportInBP(15_00);

        _wait(_calcVetoSignallingDuration().plusSeconds(1 seconds));

        _assertStateMachineTransition({from: State.VetoSignallingDeactivation, to: State.RageQuit});
    }

    // ---
    // VetoSignallingDeactivation -> VetoCooldown
    // ---

    function test_getStateTransition_FromVetoSignallingDeactivationToVetoCooldown() external {
        _setMockRageQuitSupportInBP(3_00);
        _setupVetoSignallingDeactivationState();

        _assertStateMachineTransition({from: State.VetoSignallingDeactivation, to: State.VetoSignallingDeactivation});

        _wait(_configProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));

        _assertStateMachineTransition({from: State.VetoSignallingDeactivation, to: State.VetoCooldown});
    }

    // ---
    // VetoSignallingDeactivation -> VetoSignallingDeactivation
    // ---

    function test_getStateTransition_FromVetoSignallingDeactivationToVetoSignallingDeactivation() external {
        _setMockRageQuitSupportInBP(3_00);
        _setupVetoSignallingDeactivationState();

        _assertStateMachineTransition({from: State.VetoSignallingDeactivation, to: State.VetoSignallingDeactivation});

        _wait(_configProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION());

        _assertStateMachineTransition({from: State.VetoSignallingDeactivation, to: State.VetoSignallingDeactivation});

        _wait(Durations.from(1 seconds));

        _assertStateMachineTransition({from: State.VetoSignallingDeactivation, to: State.VetoCooldown});
    }

    // ---
    // VetoCooldown -> VetoCooldown
    // ---

    function test_getStateTransition_FromVetoCooldownToVetoCooldown() external {
        _setupVetoCooldownState();

        _assertStateMachineTransition({from: State.VetoCooldown, to: State.VetoCooldown});

        _wait(_configProvider.VETO_COOLDOWN_DURATION().dividedBy(2));

        _assertStateMachineTransition({from: State.VetoCooldown, to: State.VetoCooldown});

        _wait(_configProvider.VETO_COOLDOWN_DURATION().dividedBy(2).plusSeconds(1));

        _assertStateMachineTransition({from: State.VetoCooldown, to: State.Normal});
    }

    // ---
    // VetoCooldown -> VetoSignalling
    // ---

    function test_getStateTransition_FromVetoCooldownToVetoSignalling() external {
        _setupVetoCooldownState();

        _assertStateMachineTransition({from: State.VetoCooldown, to: State.VetoCooldown});

        _setMockRageQuitSupportInBP(3_00);

        _wait(_configProvider.VETO_COOLDOWN_DURATION().plusSeconds(1));

        _assertStateMachineTransition({from: State.VetoCooldown, to: State.VetoSignalling});
    }

    // ---
    // VetoCooldown -> Normal
    // ---

    function test_getStateTransition_FromVetoCooldownToNormal() external {
        _setupVetoCooldownState();

        _assertStateMachineTransition({from: State.VetoCooldown, to: State.VetoCooldown});

        _wait(_configProvider.VETO_COOLDOWN_DURATION().plusSeconds(1));

        _assertStateMachineTransition({from: State.VetoCooldown, to: State.Normal});
    }

    // ---
    // RageQuit -> RageQuit
    // ---

    function test_getStateTransition_FromRageQuitToRageQuit() external {
        _setupRageQuitState();
        _setMockIsRageQuitFinalized(false);

        _assertStateMachineTransition({from: State.RageQuit, to: State.RageQuit});
    }

    // ---
    // RageQuit -> VetoSignalling
    // ---

    function test_getStateTransition_FromRageQuitToVetoSignalling() external {
        _setupRageQuitState();
        _setMockIsRageQuitFinalized(false);

        _assertStateMachineTransition({from: State.RageQuit, to: State.RageQuit});

        _setMockIsRageQuitFinalized(true);
        _setMockRageQuitSupportInBP(3_00);

        _assertStateMachineTransition({from: State.RageQuit, to: State.VetoSignalling});
    }

    // ---
    // RageQuit -> VetoCooldown
    // ---

    function test_getStateTransition_FromRageQuitToVetoCooldown() external {
        _setupRageQuitState();
        _setMockIsRageQuitFinalized(false);

        _assertStateMachineTransition({from: State.RageQuit, to: State.RageQuit});

        _setMockIsRageQuitFinalized(true);
        _setMockRageQuitSupportInBP(1_01);

        _assertStateMachineTransition({from: State.RageQuit, to: State.VetoCooldown});
    }

    // ---
    // NotInitialized -> assert(false)
    // ---

    function test_getStateTransition_RevertOn_NotInitializedState() external {
        _stateMachine.state = State.NotInitialized;

        vm.expectRevert(stdError.assertionError);
        this.external__getStateTransition();
    }

    // ---
    // Helper test methods
    // ---

    function _setupVetoSignallingState() internal {
        _stateMachine.state = State.VetoSignalling;
        _stateMachine.enteredAt = Timestamps.now();
        _stateMachine.vetoSignallingActivatedAt = Timestamps.now();
    }

    function _setupVetoSignallingDeactivationState() internal {
        _setupVetoSignallingState();

        _wait(_configProvider.VETO_SIGNALLING_MIN_DURATION().plusSeconds(1 hours));

        _stateMachine.state = State.VetoSignallingDeactivation;
        _stateMachine.enteredAt = Timestamps.now();
    }

    function _setupVetoCooldownState() internal {
        _setupVetoSignallingDeactivationState();
        _wait(_configProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));

        _stateMachine.state = State.VetoCooldown;
        _stateMachine.enteredAt = Timestamps.now();
    }

    function _setupRageQuitState() internal {
        _stateMachine.state = State.RageQuit;
        _stateMachine.enteredAt = Timestamps.now();
        _stateMachine.rageQuitEscrow = IRageQuitEscrow(_escrowMasterCopyMock);
    }

    function _setMockRageQuitSupportInBP(uint256 bpValue) internal {
        vm.mockCall(
            address(_stateMachine.signallingEscrow),
            abi.encodeWithSelector(ISignallingEscrow.getRageQuitSupport.selector),
            abi.encode(PercentsD16.fromBasisPoints(bpValue))
        );
    }

    function _setMockIsRageQuitFinalized(bool isRageQuitFinalized) internal {
        vm.mockCall(
            address(_stateMachine.rageQuitEscrow),
            abi.encodeWithSelector(IRageQuitEscrow.isRageQuitFinalized.selector),
            abi.encode(isRageQuitFinalized)
        );
    }

    function _calcVetoSignallingDuration() internal returns (Duration) {
        return _configProvider.getDualGovernanceConfig().calcVetoSignallingDuration(
            _stateMachine.signallingEscrow.getRageQuitSupport()
        );
    }

    function _assertStateMachineTransition(State from, State to) internal {
        (State current, State next) = _stateMachine.getStateTransition(_configProvider.getDualGovernanceConfig());

        assertEq(current, from);
        assertEq(next, to);
    }

    function external__getStateTransition() external returns (State current, State next) {
        (current, next) = _stateMachine.getStateTransition(_configProvider.getDualGovernanceConfig());
    }
}
