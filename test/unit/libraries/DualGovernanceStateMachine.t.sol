// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IEscrowBase} from "contracts/interfaces/IEscrowBase.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";

import {Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

import {DualGovernanceStateMachine, State} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {
    DualGovernanceConfig,
    ImmutableDualGovernanceConfigProvider
} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract DualGovernanceStateMachineUnitTests is UnitTest {
    using DualGovernanceStateMachine for DualGovernanceStateMachine.Context;

    address private immutable _ESCROW_MASTER_COPY_MOCK = makeAddr("ESCROW_MASTER_COPY_MOCK");

    ImmutableDualGovernanceConfigProvider internal immutable _CONFIG_PROVIDER = new ImmutableDualGovernanceConfigProvider(
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

    DualGovernanceStateMachine.Context private _stateMachine;

    function setUp() external {
        _stateMachine.initialize(_CONFIG_PROVIDER, IEscrowBase(_ESCROW_MASTER_COPY_MOCK));
        _mockRageQuitFinalized(false);
        _mockRageQuitSupport(PercentsD16.from(0));
        _mockEscrowMasterCopy();
    }

    function test_initialize_RevertOn_ReInitialization() external {
        vm.expectRevert(DualGovernanceStateMachine.AlreadyInitialized.selector);
        this.external__initialize();
    }

    // ---
    // activateNextState()
    // ---

    function test_activateNextState_SideEffects_RageQuitRoundResetInVetoCooldownAfterRageQuit() external {
        // Transition state machine into the VetoSignalling state
        _mockRageQuitSupport(_CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1));
        _activateNextState();
        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        // Simulate the Rage Quit process has completed and in the SignallingEscrow the first seal is not reached
        _mockRageQuitFinalized(true);
        _activateNextState();
        _mockRageQuitSupport(PercentsD16.fromBasisPoints(0));

        // Rage Quit Round should reset after system entered the VetoCooldown

        _assertState({persisted: State.RageQuit, effective: State.VetoCooldown});
        assertEq(_stateMachine.rageQuitRound, 1);

        _activateNextState();

        _assertState({persisted: State.VetoCooldown, effective: State.VetoCooldown});
        assertEq(_stateMachine.rageQuitRound, 0);
    }

    function test_activateNextState_SideEffects_RageQuitRoundResetInVetoCooldownAfterVetoSignallingDeactivation()
        external
    {
        // Transition state machine into the RageQuit state
        _mockRageQuitSupport(_CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1));
        _activateNextState();
        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        // Simulate the Rage Quit process has completed and in the SignallingEscrow the first seal is reached
        _mockRageQuitFinalized(true);
        _activateNextState();

        _assertState({persisted: State.RageQuit, effective: State.VetoSignalling});
        assertEq(_stateMachine.rageQuitRound, 1);

        _activateNextState();

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignalling});
        assertEq(_stateMachine.rageQuitRound, 1);

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().dividedBy(2));

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignalling});
        assertEq(_stateMachine.rageQuitRound, 1);

        // Simulate the Rage Quit support decreased
        _mockRageQuitSupport(PercentsD16.from(3_00));

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignallingDeactivation});
        assertEq(_stateMachine.rageQuitRound, 1);

        _activateNextState();

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoSignallingDeactivation});
        assertEq(_stateMachine.rageQuitRound, 1);

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoCooldown});
        assertEq(_stateMachine.rageQuitRound, 1);

        _activateNextState();

        _assertState({persisted: State.VetoCooldown, effective: State.VetoCooldown});
        assertEq(_stateMachine.rageQuitRound, 0);
    }

    function test_activateNextState_HappyPath_MaxRageQuitsRound() external {
        _assertState({persisted: State.Normal, effective: State.Normal});

        // For the simplicity, simulate that Signalling Escrow always has rage quit support greater than the second seal
        _mockRageQuitSupport(_CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1_00));
        // And that the Rage Quit finalized
        _mockRageQuitFinalized(true);

        assertTrue(
            _stateMachine.signallingEscrow.getRageQuitSupport() > _CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT()
        );
        _assertState({persisted: State.Normal, effective: State.VetoSignalling});
        _activateNextState();

        // Simulate sequential Rage Quits
        for (uint256 i = 0; i < 2 * DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND; ++i) {
            _assertState({persisted: State.VetoSignalling, effective: State.VetoSignalling});
            assertEq(_stateMachine.rageQuitRound, Math.min(i, DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND));

            _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
            _activateNextState();

            // Effective state is VetoSignalling, as the rage quit is considered finalized
            _assertState({persisted: State.RageQuit, effective: State.VetoSignalling});
            assertEq(_stateMachine.rageQuitRound, Math.min(i + 1, DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND));

            _activateNextState();
        }

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().dividedBy(2));

        // after the sequential rage quits chain is broken, the rage quit resets to 0
        _mockRageQuitSupport(PercentsD16.from(0));

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignallingDeactivation});
        assertEq(_stateMachine.rageQuitRound, DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND);

        _activateNextState();

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoSignallingDeactivation});
        assertEq(_stateMachine.rageQuitRound, DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND);

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoCooldown});
        assertEq(_stateMachine.rageQuitRound, DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND);

        _activateNextState();

        _assertState({persisted: State.VetoCooldown, effective: State.VetoCooldown});
        assertEq(_stateMachine.rageQuitRound, 0);
    }

    // ---
    // canSubmitProposal()
    // ---

    function test_canSubmitProposal_HappyPath() external {
        _assertState({persisted: State.Normal, effective: State.Normal});
        _assertCanSubmitProposal({persisted: true, effective: true});

        // simulate the first threshold of veto signalling was reached
        _mockRageQuitSupport(_CONFIG_PROVIDER.FIRST_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.from(1));

        _assertState({persisted: State.Normal, effective: State.VetoSignalling});
        _assertCanSubmitProposal({persisted: true, effective: true});

        _activateNextState();

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignalling});
        _assertCanSubmitProposal({persisted: true, effective: true});

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MIN_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignallingDeactivation});
        _assertCanSubmitProposal({persisted: true, effective: false});

        _activateNextState();

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoSignallingDeactivation});
        _assertCanSubmitProposal({persisted: false, effective: false});

        // simulate the second threshold of veto signalling was reached
        _mockRageQuitSupport(_CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.from(1));

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoSignalling});
        _assertCanSubmitProposal({persisted: false, effective: true});

        _activateNextState();

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignalling});
        _assertCanSubmitProposal({persisted: true, effective: true});

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoSignalling, effective: State.RageQuit});
        _assertCanSubmitProposal({persisted: true, effective: true});

        _activateNextState();

        _assertState({persisted: State.RageQuit, effective: State.RageQuit});
        _assertCanSubmitProposal({persisted: true, effective: true});

        _mockRageQuitFinalized(true);
        _mockRageQuitSupport(PercentsD16.from(0));

        _assertState({persisted: State.RageQuit, effective: State.VetoCooldown});
        _assertCanSubmitProposal({persisted: true, effective: false});

        _activateNextState();

        _assertState({persisted: State.VetoCooldown, effective: State.VetoCooldown});
        _assertCanSubmitProposal({persisted: false, effective: false});

        _wait(_CONFIG_PROVIDER.VETO_COOLDOWN_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoCooldown, effective: State.Normal});
        _assertCanSubmitProposal({persisted: false, effective: true});

        _activateNextState();

        _assertState({persisted: State.Normal, effective: State.Normal});
        _assertCanSubmitProposal({persisted: true, effective: true});
    }

    // ---
    // canScheduleProposal()
    // ---

    function test_canScheduleProposal_HappyPath() external {
        Timestamp proposalSubmittedAt = Timestamps.now();

        _assertState({persisted: State.Normal, effective: State.Normal});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: true, effective: true});

        // simulate the first threshold of veto signalling was reached
        _mockRageQuitSupport(_CONFIG_PROVIDER.FIRST_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.from(1));

        _assertState({persisted: State.Normal, effective: State.VetoSignalling});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: true, effective: false});

        _activateNextState();

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignalling});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: false, effective: false});

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MIN_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignallingDeactivation});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: false, effective: false});

        _activateNextState();

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoSignallingDeactivation});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: false, effective: false});

        // simulate the second threshold of veto signalling was reached
        _mockRageQuitSupport(_CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.from(1));

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoSignalling});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: false, effective: false});

        _activateNextState();

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignalling});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: false, effective: false});

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoSignalling, effective: State.RageQuit});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: false, effective: false});

        _activateNextState();

        _assertState({persisted: State.RageQuit, effective: State.RageQuit});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: false, effective: false});

        _mockRageQuitFinalized(true);
        _mockRageQuitSupport(PercentsD16.from(0));

        _assertState({persisted: State.RageQuit, effective: State.VetoCooldown});
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: false, effective: true});

        //  for proposals submitted at the same block the VetoSignalling started scheduling is allowed
        _assertCanScheduleProposal({
            proposalSubmittedAt: _stateMachine.vetoSignallingActivatedAt,
            persisted: false,
            effective: true
        });
        //  for proposals submitted after the VetoSignalling started scheduling is forbidden
        _assertCanScheduleProposal({
            proposalSubmittedAt: Durations.from(1 seconds).addTo(_stateMachine.vetoSignallingActivatedAt),
            persisted: false,
            effective: false
        });
        _assertCanScheduleProposal({proposalSubmittedAt: Timestamps.now(), persisted: false, effective: false});

        _activateNextState();

        _assertState({persisted: State.VetoCooldown, effective: State.VetoCooldown});

        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: true, effective: true});
        _assertCanScheduleProposal({
            proposalSubmittedAt: _stateMachine.vetoSignallingActivatedAt,
            persisted: true,
            effective: true
        });
        //  for proposals submitted after the VetoSignalling started scheduling is forbidden
        _assertCanScheduleProposal({
            proposalSubmittedAt: Durations.from(1 seconds).addTo(_stateMachine.vetoSignallingActivatedAt),
            persisted: false,
            effective: false
        });
        _assertCanScheduleProposal({proposalSubmittedAt: Timestamps.now(), persisted: false, effective: false});

        _wait(_CONFIG_PROVIDER.VETO_COOLDOWN_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoCooldown, effective: State.Normal});

        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: true, effective: true});
        _assertCanScheduleProposal({
            proposalSubmittedAt: _stateMachine.vetoSignallingActivatedAt,
            persisted: true,
            effective: true
        });

        //  for proposals submitted after the VetoSignalling started scheduling is forbidden
        _assertCanScheduleProposal({
            proposalSubmittedAt: Durations.from(1 seconds).addTo(_stateMachine.vetoSignallingActivatedAt),
            persisted: false,
            effective: true
        });
        _assertCanScheduleProposal({proposalSubmittedAt: Timestamps.now(), persisted: false, effective: true});

        _activateNextState();

        _assertState({persisted: State.Normal, effective: State.Normal});

        // persisted
        _assertCanScheduleProposal({proposalSubmittedAt: proposalSubmittedAt, persisted: true, effective: true});
        _assertCanScheduleProposal({proposalSubmittedAt: Timestamps.now(), persisted: true, effective: true});
    }

    // ---
    // canCancelAllPendingProposals()
    // ---

    function test_canCancelAllPendingProposals_HappyPath() external {
        _assertState({persisted: State.Normal, effective: State.Normal});
        _assertCanCancelAllPendingProposals({persisted: false, effective: false});

        // simulate the first threshold of veto signalling was reached
        _mockRageQuitSupport(_CONFIG_PROVIDER.FIRST_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.from(1));

        _assertState({persisted: State.Normal, effective: State.VetoSignalling});
        _assertCanCancelAllPendingProposals({persisted: false, effective: true});

        _activateNextState();

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignalling});
        _assertCanCancelAllPendingProposals({persisted: true, effective: true});

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MIN_DURATION().plusSeconds(1 minutes));

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignallingDeactivation});
        _assertCanCancelAllPendingProposals({persisted: true, effective: true});

        _activateNextState();

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoSignallingDeactivation});
        _assertCanCancelAllPendingProposals({persisted: true, effective: true});

        // simulate the second threshold of veto signalling was reached
        _mockRageQuitSupport(_CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.from(1));

        _assertState({persisted: State.VetoSignallingDeactivation, effective: State.VetoSignalling});
        _assertCanCancelAllPendingProposals({persisted: true, effective: true});

        _activateNextState();

        _assertState({persisted: State.VetoSignalling, effective: State.VetoSignalling});
        _assertCanCancelAllPendingProposals({persisted: true, effective: true});

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoSignalling, effective: State.RageQuit});
        _assertCanCancelAllPendingProposals({persisted: true, effective: false});

        _activateNextState();

        _assertState({persisted: State.RageQuit, effective: State.RageQuit});
        _assertCanCancelAllPendingProposals({persisted: false, effective: false});

        _mockRageQuitFinalized(true);
        _mockRageQuitSupport(PercentsD16.from(0));

        _assertState({persisted: State.RageQuit, effective: State.VetoCooldown});
        _assertCanCancelAllPendingProposals({persisted: false, effective: false});

        _activateNextState();

        _assertState({persisted: State.VetoCooldown, effective: State.VetoCooldown});
        _assertCanCancelAllPendingProposals({persisted: false, effective: false});

        _wait(_CONFIG_PROVIDER.VETO_COOLDOWN_DURATION().plusSeconds(1));

        _assertState({persisted: State.VetoCooldown, effective: State.Normal});
        _assertCanCancelAllPendingProposals({persisted: false, effective: false});

        _activateNextState();

        _assertState({persisted: State.Normal, effective: State.Normal});
        _assertCanCancelAllPendingProposals({persisted: false, effective: false});
    }

    // ---
    // Test helper methods
    // ---

    function _mockEscrowMasterCopy() internal {
        vm.mockCall(
            _ESCROW_MASTER_COPY_MOCK,
            abi.encodeWithSelector(IEscrowBase.ESCROW_MASTER_COPY.selector),
            abi.encode(_ESCROW_MASTER_COPY_MOCK)
        );
    }

    function _mockRageQuitSupport(PercentD16 rageQuitSupport) internal {
        vm.mockCall(
            _ESCROW_MASTER_COPY_MOCK,
            abi.encodeCall(ISignallingEscrow.getRageQuitSupport, ()),
            abi.encode(rageQuitSupport)
        );
    }

    function _mockRageQuitFinalized(bool isRageQuitFinalized) internal {
        vm.mockCall(
            _ESCROW_MASTER_COPY_MOCK,
            abi.encodeCall(IRageQuitEscrow.isRageQuitFinalized, ()),
            abi.encode(isRageQuitFinalized)
        );
    }

    function _activateNextState() internal {
        _stateMachine.activateNextState();
    }

    function _assertState(State persisted, State effective) internal {
        assertEq(_stateMachine.getPersistedState(), persisted, "Unexpected Persisted State");
        assertEq(_stateMachine.getEffectiveState(), effective, "Unexpected Effective State");
    }

    function _assertCanCancelAllPendingProposals(bool persisted, bool effective) internal {
        assertEq(
            _stateMachine.canCancelAllPendingProposals({useEffectiveState: false}),
            persisted,
            "Unexpected persisted canCancelAllPendingProposals() value"
        );
        assertEq(
            _stateMachine.canCancelAllPendingProposals({useEffectiveState: true}),
            effective,
            "Unexpected effective canCancelAllPendingProposals() value"
        );
    }

    function _assertCanScheduleProposal(Timestamp proposalSubmittedAt, bool persisted, bool effective) internal {
        assertEq(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt}),
            persisted,
            "Unexpected persisted canScheduleProposal() value"
        );
        assertEq(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt}),
            effective,
            "Unexpected persisted canScheduleProposal() value"
        );
    }

    function _assertCanSubmitProposal(bool persisted, bool effective) internal {
        assertEq(
            _stateMachine.canSubmitProposal({useEffectiveState: false}),
            persisted,
            "Unexpected persisted canSubmitProposal() value"
        );
        assertEq(
            _stateMachine.canSubmitProposal({useEffectiveState: true}),
            effective,
            "Unexpected effective canSubmitProposal() value"
        );
    }

    function external__initialize() external {
        _stateMachine.initialize(_CONFIG_PROVIDER, IEscrowBase(_ESCROW_MASTER_COPY_MOCK));
    }
}
