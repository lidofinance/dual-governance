// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

import {DualGovernanceStateMachine, State} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {
    DualGovernanceConfig,
    ImmutableDualGovernanceConfigProvider
} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {IEscrow, EscrowMock} from "test/mocks/EscrowMock.sol";

contract DualGovernanceStateMachineUnitTests is UnitTest {
    using DualGovernanceStateMachine for DualGovernanceStateMachine.Context;

    IEscrow private immutable _ESCROW_MASTER_COPY = new EscrowMock();
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
        _stateMachine.initialize(_CONFIG_PROVIDER, _ESCROW_MASTER_COPY);
    }

    function test_initialize_RevertOn_ReInitialization() external {
        vm.expectRevert(DualGovernanceStateMachine.AlreadyInitialized.selector);
        this.external__initialize();
    }

    // ---
    // activateNextState()
    // ---

    function test_activateNextState_HappyPath_MaxRageQuitsRound() external {
        assertEq(_stateMachine.state, State.Normal);

        for (uint256 i = 0; i < 2 * DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND; ++i) {
            address signallingEscrow = address(_stateMachine.signallingEscrow);
            EscrowMock(signallingEscrow).__setRageQuitSupport(
                _CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1_00)
            );
            assertTrue(
                _stateMachine.signallingEscrow.getRageQuitSupport() > _CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT()
            );
            assertEq(_stateMachine.rageQuitRound, Math.min(i, DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND));

            // wait here the full duration of the veto cooldown to make sure it's over from the previous iteration
            _wait(_CONFIG_PROVIDER.VETO_COOLDOWN_DURATION().plusSeconds(1));

            _stateMachine.activateNextState(_ESCROW_MASTER_COPY);
            assertEq(_stateMachine.state, State.VetoSignalling);

            _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
            _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

            assertEq(_stateMachine.state, State.RageQuit);
            assertEq(_stateMachine.rageQuitRound, Math.min(i + 1, DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND));

            EscrowMock(signallingEscrow).__setIsRageQuitFinalized(true);
            _stateMachine.activateNextState(_ESCROW_MASTER_COPY);
            assertEq(_stateMachine.state, State.VetoCooldown);
        }

        // after the sequential rage quits chain is broken, the rage quit resets to 0
        _wait(_CONFIG_PROVIDER.VETO_COOLDOWN_DURATION().plusSeconds(1));
        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.rageQuitRound, 0);
        assertEq(_stateMachine.state, State.Normal);
    }

    // ---
    // canSubmitProposal()
    // ---

    function test_canSubmitProposal_HappyPath() external {
        address signallingEscrow = address(_stateMachine.signallingEscrow);

        assertEq(_stateMachine.getPersistedState(), State.Normal);
        assertEq(_stateMachine.getEffectiveState(), State.Normal);
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: true}));
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));

        // simulate the first threshold of veto signalling was reached
        EscrowMock(signallingEscrow).__setRageQuitSupport(
            _CONFIG_PROVIDER.FIRST_SEAL_RAGE_QUIT_SUPPORT() + PercentD16.wrap(1)
        );

        assertEq(_stateMachine.getPersistedState(), State.Normal);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MIN_DURATION().plusSeconds(1 minutes));

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignallingDeactivation);
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertFalse(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoSignallingDeactivation);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignallingDeactivation);
        assertFalse(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertFalse(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        // simulate the second threshold of veto signalling was reached
        EscrowMock(signallingEscrow).__setRageQuitSupport(
            _CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1_00)
        );

        assertEq(_stateMachine.getPersistedState(), State.VetoSignallingDeactivation);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertFalse(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.RageQuit);
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.RageQuit);
        assertEq(_stateMachine.getEffectiveState(), State.RageQuit);
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        EscrowMock(address(_stateMachine.rageQuitEscrow)).__setIsRageQuitFinalized(true);

        assertEq(_stateMachine.getPersistedState(), State.RageQuit);
        assertEq(_stateMachine.getEffectiveState(), State.VetoCooldown);
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertFalse(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoCooldown);
        assertEq(_stateMachine.getEffectiveState(), State.VetoCooldown);
        assertFalse(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertFalse(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        _wait(_CONFIG_PROVIDER.VETO_COOLDOWN_DURATION().plusSeconds(1));

        assertEq(_stateMachine.getPersistedState(), State.VetoCooldown);
        assertEq(_stateMachine.getEffectiveState(), State.Normal);
        assertFalse(_stateMachine.canSubmitProposal({useEffectiveState: false}));
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.Normal);
        assertEq(_stateMachine.getEffectiveState(), State.Normal);
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: true}));
        assertTrue(_stateMachine.canSubmitProposal({useEffectiveState: false}));
    }

    // ---
    // canScheduleProposal()
    // ---

    function test_canScheduleProposal_HappyPath() external {
        address signallingEscrow = address(_stateMachine.signallingEscrow);
        Timestamp proposalSubmittedAt = Timestamps.now();

        assertEq(_stateMachine.getPersistedState(), State.Normal);
        assertEq(_stateMachine.getEffectiveState(), State.Normal);
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );

        // simulate the first threshold of veto signalling was reached
        EscrowMock(signallingEscrow).__setRageQuitSupport(
            _CONFIG_PROVIDER.FIRST_SEAL_RAGE_QUIT_SUPPORT() + PercentD16.wrap(1)
        );

        assertEq(_stateMachine.getPersistedState(), State.Normal);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MIN_DURATION().plusSeconds(1 minutes));

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignallingDeactivation);
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoSignallingDeactivation);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignallingDeactivation);
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );

        // simulate the second threshold of veto signalling was reached
        EscrowMock(signallingEscrow).__setRageQuitSupport(
            _CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1_00)
        );

        assertEq(_stateMachine.getPersistedState(), State.VetoSignallingDeactivation);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.RageQuit);
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.RageQuit);
        assertEq(_stateMachine.getEffectiveState(), State.RageQuit);
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );

        EscrowMock(address(_stateMachine.rageQuitEscrow)).__setIsRageQuitFinalized(true);

        assertEq(_stateMachine.getPersistedState(), State.RageQuit);
        assertEq(_stateMachine.getEffectiveState(), State.VetoCooldown);
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );
        //  for proposals submitted at the same block the VetoSignalling started scheduling is allowed
        assertTrue(
            _stateMachine.canScheduleProposal({
                useEffectiveState: true,
                proposalSubmittedAt: _stateMachine.vetoSignallingActivatedAt
            })
        );
        //  for proposals submitted after the VetoSignalling started scheduling is forbidden
        assertFalse(
            _stateMachine.canScheduleProposal({
                useEffectiveState: true,
                proposalSubmittedAt: Durations.from(1 seconds).addTo(_stateMachine.vetoSignallingActivatedAt)
            })
        );
        assertFalse(_stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: Timestamps.now()}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoCooldown);
        assertEq(_stateMachine.getEffectiveState(), State.VetoCooldown);

        // persisted
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertTrue(
            _stateMachine.canScheduleProposal({
                useEffectiveState: false,
                proposalSubmittedAt: _stateMachine.vetoSignallingActivatedAt
            })
        );
        //  for proposals submitted after the VetoSignalling started scheduling is forbidden
        assertFalse(
            _stateMachine.canScheduleProposal({
                useEffectiveState: false,
                proposalSubmittedAt: Durations.from(1 seconds).addTo(_stateMachine.vetoSignallingActivatedAt)
            })
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: Timestamps.now()})
        );

        // effective
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );
        //  for proposals submitted at the same block the VetoSignalling started scheduling is allowed
        assertTrue(
            _stateMachine.canScheduleProposal({
                useEffectiveState: true,
                proposalSubmittedAt: _stateMachine.vetoSignallingActivatedAt
            })
        );
        //  for proposals submitted after the VetoSignalling started scheduling is forbidden
        assertFalse(
            _stateMachine.canScheduleProposal({
                useEffectiveState: true,
                proposalSubmittedAt: Durations.from(1 seconds).addTo(_stateMachine.vetoSignallingActivatedAt)
            })
        );
        assertFalse(_stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: Timestamps.now()}));

        _wait(_CONFIG_PROVIDER.VETO_COOLDOWN_DURATION().plusSeconds(1));

        assertEq(_stateMachine.getPersistedState(), State.VetoCooldown);
        assertEq(_stateMachine.getEffectiveState(), State.Normal);

        // persisted
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertTrue(
            _stateMachine.canScheduleProposal({
                useEffectiveState: false,
                proposalSubmittedAt: _stateMachine.vetoSignallingActivatedAt
            })
        );
        //  for proposals submitted after the VetoSignalling started scheduling is forbidden
        assertFalse(
            _stateMachine.canScheduleProposal({
                useEffectiveState: false,
                proposalSubmittedAt: Durations.from(1 seconds).addTo(_stateMachine.vetoSignallingActivatedAt)
            })
        );
        assertFalse(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: Timestamps.now()})
        );

        // effective
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertTrue(_stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: Timestamps.now()}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.Normal);
        assertEq(_stateMachine.getEffectiveState(), State.Normal);

        // persisted
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertTrue(_stateMachine.canScheduleProposal({useEffectiveState: false, proposalSubmittedAt: Timestamps.now()}));

        // effective
        assertTrue(
            _stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: proposalSubmittedAt})
        );
        assertTrue(_stateMachine.canScheduleProposal({useEffectiveState: true, proposalSubmittedAt: Timestamps.now()}));
    }

    // ---
    // canCancelAllPendingProposals()
    // ---

    function test_canCancelAllPendingProposals_HappyPath() external {
        address signallingEscrow = address(_stateMachine.signallingEscrow);
        Timestamp proposalSubmittedAt = Timestamps.now();

        assertEq(_stateMachine.getPersistedState(), State.Normal);
        assertEq(_stateMachine.getEffectiveState(), State.Normal);
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));

        // simulate the first threshold of veto signalling was reached
        EscrowMock(signallingEscrow).__setRageQuitSupport(
            _CONFIG_PROVIDER.FIRST_SEAL_RAGE_QUIT_SUPPORT() + PercentD16.wrap(1)
        );

        assertEq(_stateMachine.getPersistedState(), State.Normal);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MIN_DURATION().plusSeconds(1 minutes));

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignallingDeactivation);
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoSignallingDeactivation);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignallingDeactivation);
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        // simulate the second threshold of veto signalling was reached
        EscrowMock(signallingEscrow).__setRageQuitSupport(
            _CONFIG_PROVIDER.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1_00)
        );

        assertEq(_stateMachine.getPersistedState(), State.VetoSignallingDeactivation);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.VetoSignalling);
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        assertEq(_stateMachine.getPersistedState(), State.VetoSignalling);
        assertEq(_stateMachine.getEffectiveState(), State.RageQuit);
        assertTrue(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.RageQuit);
        assertEq(_stateMachine.getEffectiveState(), State.RageQuit);
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        EscrowMock(address(_stateMachine.rageQuitEscrow)).__setIsRageQuitFinalized(true);

        assertEq(_stateMachine.getPersistedState(), State.RageQuit);
        assertEq(_stateMachine.getEffectiveState(), State.VetoCooldown);
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.VetoCooldown);
        assertEq(_stateMachine.getEffectiveState(), State.VetoCooldown);
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        _wait(_CONFIG_PROVIDER.VETO_COOLDOWN_DURATION().plusSeconds(1));

        assertEq(_stateMachine.getPersistedState(), State.VetoCooldown);
        assertEq(_stateMachine.getEffectiveState(), State.Normal);
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));

        _stateMachine.activateNextState(_ESCROW_MASTER_COPY);

        assertEq(_stateMachine.getPersistedState(), State.Normal);
        assertEq(_stateMachine.getEffectiveState(), State.Normal);
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: false}));
        assertFalse(_stateMachine.canCancelAllPendingProposals({useEffectiveState: true}));
    }

    // ---
    // Test helper methods
    // ---

    function external__initialize() external {
        _stateMachine.initialize(_CONFIG_PROVIDER, _ESCROW_MASTER_COPY);
    }
}
