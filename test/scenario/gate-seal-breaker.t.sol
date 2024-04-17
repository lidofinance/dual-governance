// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {percents, ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";

import {GateSealMock} from "../mocks/GateSealMock.sol";
import {GateSealBreaker, IGateSeal} from "contracts/GateSealBreaker.sol";

import {DAO_AGENT} from "../utils/mainnet-addresses.sol";

contract SealBreakerScenarioTest is ScenarioTestBlueprint {
    uint256 private immutable _RELEASE_DELAY = 5 days;
    uint256 private immutable _MIN_SEAL_DURATION = 14 days;

    address private immutable _VETOER = makeAddr("VETOER");

    IGateSeal private _gateSeal;
    address[] private _sealables;
    GateSealBreaker private _sealBreaker;

    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);

        _sealables.push(address(_WITHDRAWAL_QUEUE));

        _gateSeal = new GateSealMock(_MIN_SEAL_DURATION, _SEALING_COMMITTEE_LIFETIME);

        _sealBreaker = new GateSealBreaker(_RELEASE_DELAY, address(this), address(_dualGovernance));

        _sealBreaker.registerGateSeal(_gateSeal);

        // grant rights to gate seal to pause/resume the withdrawal queue
        vm.startPrank(DAO_AGENT);
        _WITHDRAWAL_QUEUE.grantRole(_WITHDRAWAL_QUEUE.PAUSE_ROLE(), address(_gateSeal));
        _WITHDRAWAL_QUEUE.grantRole(_WITHDRAWAL_QUEUE.RESUME_ROLE(), address(_sealBreaker));
        vm.stopPrank();
    }

    function testFork_DualGovernanceLockedThenSeal() external {
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
        _assertNormalState();

        _lockStETH(_VETOER, percents("10.0"));
        _assertVetoSignalingState();

        // sealing committee seals Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // seal can't be released before the min sealing duration has passed
        vm.expectRevert(GateSealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        // validate Withdrawal Queue was paused
        assertTrue(_WITHDRAWAL_QUEUE.isPaused());

        _wait(_MIN_SEAL_DURATION + 1);

        // validate the dual governance still in the veto signaling state
        _assertVetoSignalingState();

        // seal can't be released before the governance returns to Normal state
        vm.expectRevert(GateSealBreaker.GovernanceLocked.selector);
        _sealBreaker.startRelease(_gateSeal);

        // wait the governance returns to normal state
        _wait(14 days);
        _activateNextState();
        _assertVetoSignalingDeactivationState();

        _wait(_config.SIGNALLING_DEACTIVATION_DURATION() + 1);
        _activateNextState();
        _assertVetoCooldownState();

        // anyone may start release the seal
        _sealBreaker.startRelease(_gateSeal);

        // reverts until timelock
        vm.expectRevert(GateSealBreaker.ReleaseDelayNotPassed.selector);
        _sealBreaker.enactRelease(_gateSeal);

        // anyone may release the seal after timelock
        _wait(_RELEASE_DELAY + 1);
        _sealBreaker.enactRelease(_gateSeal);

        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
    }

    function testFork_SealThenDualGovernanceLocked() external {
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
        _assertNormalState();

        // sealing committee seals the Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // validate Withdrawal Queue was paused
        assertTrue(_WITHDRAWAL_QUEUE.isPaused());

        // wait some time, before dual governance enters veto signaling state
        _wait(_MIN_SEAL_DURATION / 2);

        _lockStETH(_VETOER, percents("10.0"));
        _assertVetoSignalingState();

        // seal can't be released before the min sealing duration has passed
        vm.expectRevert(GateSealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        _wait(_MIN_SEAL_DURATION / 2 + 1);

        // seal can't be released before the governance returns to Normal state
        vm.expectRevert(GateSealBreaker.GovernanceLocked.selector);
        _sealBreaker.startRelease(_gateSeal);

        // wait the governance returns to normal state
        _wait(14 days);
        _activateNextState();
        _assertVetoSignalingDeactivationState();

        _wait(_dualGovernance.CONFIG().SIGNALLING_DEACTIVATION_DURATION() + 1);
        _activateNextState();
        _assertVetoCooldownState();

        // the stETH whale takes his funds back from Escrow
        _unlockStETH(_VETOER);

        _wait(_dualGovernance.CONFIG().SIGNALLING_COOLDOWN_DURATION() + 1);
        _activateNextState();
        _assertNormalState();

        // now seal may be released
        _sealBreaker.startRelease(_gateSeal);

        // reverts until timelock
        vm.expectRevert(GateSealBreaker.ReleaseDelayNotPassed.selector);
        _sealBreaker.enactRelease(_gateSeal);

        // anyone may release the seal after timelock
        _wait(_RELEASE_DELAY + 1);
        _sealBreaker.enactRelease(_gateSeal);
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
    }

    function testFork_SealWhenDualGovernanceNotLocked() external {
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
        _assertNormalState();

        // sealing committee seals the Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // validate Withdrawal Queue was paused
        assertTrue(_WITHDRAWAL_QUEUE.isPaused());

        // seal can't be released before the min sealing duration has passed
        vm.expectRevert(GateSealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        vm.warp(block.timestamp + _MIN_SEAL_DURATION + 1);

        // now seal may be released
        _sealBreaker.startRelease(_gateSeal);

        // reverts until timelock
        vm.expectRevert(GateSealBreaker.ReleaseDelayNotPassed.selector);
        _sealBreaker.enactRelease(_gateSeal);

        // anyone may release the seal after timelock
        _wait(_RELEASE_DELAY + 1);
        _sealBreaker.enactRelease(_gateSeal);

        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
    }

    function testFork_GateSealMayBeReleasedOnlyOnce() external {
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
        _assertNormalState();

        // sealing committee seals the Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // validate Withdrawal Queue was paused
        assertTrue(_WITHDRAWAL_QUEUE.isPaused());

        // seal can't be released before the min sealing duration has passed
        vm.expectRevert(GateSealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        _wait(_MIN_SEAL_DURATION + 1);

        // now seal may be released
        _sealBreaker.startRelease(_gateSeal);

        // An attempt to release same gate seal the second time fails
        vm.expectRevert(GateSealBreaker.GateSealAlreadyReleased.selector);
        _sealBreaker.startRelease(_gateSeal);
    }
}
