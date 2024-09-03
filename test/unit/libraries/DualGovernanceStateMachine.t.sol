// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {DualGovernanceStateMachine, State} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {DualGovernanceConfig, ImmutableDualGovernanceConfigProvider} from "contracts/DualGovernanceConfigProvider.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {EscrowMock} from "test/mocks/EscrowMock.sol";

contract DualGovernanceStateMachineUnitTests is UnitTest {

    using DualGovernanceStateMachine for DualGovernanceStateMachine.Context;

    address private immutable _ESCROW_MASTER_COPY = address(new EscrowMock());
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
        _stateMachine.initialize(_CONFIG_PROVIDER.getDualGovernanceConfig(), _ESCROW_MASTER_COPY);
    }

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

            _stateMachine.activateNextState(_CONFIG_PROVIDER.getDualGovernanceConfig(), _ESCROW_MASTER_COPY);
            assertEq(_stateMachine.state, State.VetoSignalling);

            _wait(_CONFIG_PROVIDER.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
            _stateMachine.activateNextState(_CONFIG_PROVIDER.getDualGovernanceConfig(), _ESCROW_MASTER_COPY);

            assertEq(_stateMachine.state, State.RageQuit);
            assertEq(_stateMachine.rageQuitRound, Math.min(i + 1, DualGovernanceStateMachine.MAX_RAGE_QUIT_ROUND));

            EscrowMock(signallingEscrow).__setIsRageQuitFinalized(true);
            _stateMachine.activateNextState(_CONFIG_PROVIDER.getDualGovernanceConfig(), _ESCROW_MASTER_COPY);
            assertEq(_stateMachine.state, State.VetoCooldown);
        }

        // after the sequential rage quits chain is broken, the rage quit resets to 0
        _wait(_CONFIG_PROVIDER.VETO_COOLDOWN_DURATION().plusSeconds(1));
        _stateMachine.activateNextState(_CONFIG_PROVIDER.getDualGovernanceConfig(), _ESCROW_MASTER_COPY);

        assertEq(_stateMachine.rageQuitRound, 0);
        assertEq(_stateMachine.state, State.Normal);
    }

}
