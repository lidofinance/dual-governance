// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {Escrow} from "contracts/Escrow.sol";
import {DualGovernanceDeployScript, DualGovernance, EmergencyProtectedTimelock} from "script/Deploy.s.sol";
import {GateSeal, SealBreaker, IGovernanceState, SealBreakerDualGovernance} from "contracts/SealBreaker.sol";

import {Utils} from "../utils/utils.sol";
import {IWithdrawalQueue, IERC20} from "../utils/interfaces.sol";
import {DAO_AGENT, DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER} from "../utils/mainnet-addresses.sol";

contract SealBreakerScenarioTest is Test {
    uint256 private immutable _DELAY = 3 days;
    uint256 private immutable _SEAL_DURATION = type(uint256).max;
    uint256 private immutable _MIN_SEAL_DURATION = 14 days;
    uint256 private immutable _EMERGENCY_MODE_DURATION = 180 days;
    uint256 private immutable _EMERGENCY_PROTECTION_DURATION = 90 days;
    address private immutable _EMERGENCY_COMMITTEE = makeAddr("EMERGENCY_COMMITTEE");
    uint256 internal immutable _RELEASE_DELAY = 5 days;
    uint256 internal immutable _RELEASE_TIMELOCK = 14 days;
    uint256 internal immutable _SEALING_COMMITTEE_LIFETIME = 365 days;
    address private immutable _SEALING_COMMITTEE = makeAddr("SEALING_COMMITTEE");

    GateSeal private _gateSeal;
    address[] private _sealables;
    SealBreakerDualGovernance private _sealBreaker;
    DualGovernance private _dualGovernance;
    EmergencyProtectedTimelock private _timelock;
    DualGovernanceDeployScript private _dualGovernanceDeployScript;

    function setUp() external {
        Utils.selectFork();
        _dualGovernanceDeployScript =
            new DualGovernanceDeployScript(ST_ETH, WST_ETH, BURNER, DAO_VOTING, WITHDRAWAL_QUEUE);

        (_dualGovernance, _timelock,) = _dualGovernanceDeployScript.deploy(
            DAO_VOTING, _DELAY, _EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, _EMERGENCY_MODE_DURATION
        );

        _sealables.push(WITHDRAWAL_QUEUE);

        _gateSeal = new GateSeal(
            _SEALING_COMMITTEE, _SEALING_COMMITTEE_LIFETIME, _SEAL_DURATION, _MIN_SEAL_DURATION, _sealables
        );

        _sealBreaker = new SealBreakerDualGovernance(_RELEASE_DELAY, address(this), address(_dualGovernance.state()));

        _sealBreaker.register(_gateSeal);

        // grant rights to gate seal to pause/resume the withdrawal queue
        vm.startPrank(DAO_AGENT);
        IWithdrawalQueue(WITHDRAWAL_QUEUE).grantRole(
            IWithdrawalQueue(WITHDRAWAL_QUEUE).PAUSE_ROLE(), address(_gateSeal)
        );
        IWithdrawalQueue(WITHDRAWAL_QUEUE).grantRole(
            IWithdrawalQueue(WITHDRAWAL_QUEUE).RESUME_ROLE(), address(_sealBreaker)
        );
        vm.stopPrank();
    }

    function testFork_DualGovernanceLockedThenSeal() external {
        assertFalse(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.Normal));

        address stEthWhale = makeAddr("STETH_WHALE");
        Utils.removeLidoStakingLimit();
        Utils.setupStEthWhale(stEthWhale, 10 * 10 ** 16);
        uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

        // stETH whale locks funds in the signaling escrow and governance enters VetoSignaling state
        Escrow escrow = Escrow(payable(_dualGovernance.signallingEscrow()));
        vm.startPrank(stEthWhale);
        IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
        escrow.lockStEth(stEthWhaleBalance);
        vm.stopPrank();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoSignalling));

        // sealing committee seals Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // seal can't be released before the min sealing duration has passed
        vm.expectRevert(SealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        // validate Withdrawal Queue was paused
        assertTrue(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());

        vm.warp(block.timestamp + _MIN_SEAL_DURATION + 1);

        // validate the dual governance still in the veto signaling state
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoSignalling));

        // seal can't be released before the governance returns to Normal state
        vm.expectRevert(SealBreakerDualGovernance.GovernanceIsLocked.selector);
        _sealBreaker.startRelease(_gateSeal);

        // wait the governance returns to normal state
        vm.warp(block.timestamp + 14 days);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoSignallingDeactivation));
        vm.warp(block.timestamp + _dualGovernance.CONFIG().signallingDeactivationDuration() + 1);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoCooldown));

        // anyone may start release the seal
        _sealBreaker.startRelease(_gateSeal);

        // reverts until timelock
        vm.expectRevert(SealBreaker.ReleaseDelayNotPassed.selector);
        _sealBreaker.enactRelease(_gateSeal);

        // anyone may release the seal after timelock
        vm.warp(block.timestamp + _RELEASE_TIMELOCK);
        _sealBreaker.enactRelease(_gateSeal);
        assertFalse(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());
    }

    function testFork_SealThenDualGovernanceLocked() external {
        assertFalse(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.Normal));

        // sealing committee seals the Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // validate Withdrawal Queue was paused
        assertTrue(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());

        // wait some time, before dual governance enters veto signaling state
        vm.warp(block.timestamp + _RELEASE_TIMELOCK / 2);

        address stEthWhale = makeAddr("STETH_WHALE");
        Utils.removeLidoStakingLimit();
        Utils.setupStEthWhale(stEthWhale, 10 * 10 ** 16);
        uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

        // stETH whale locks funds in the signaling escrow and governance enters VetoSignaling state
        Escrow escrow = Escrow(payable(_dualGovernance.signallingEscrow()));
        vm.startPrank(stEthWhale);
        IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
        escrow.lockStEth(stEthWhaleBalance);
        vm.stopPrank();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoSignalling));

        // validate the dual governance still in the veto signaling state
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoSignalling));

        // seal can't be released before the min sealing duration has passed
        vm.expectRevert(SealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        vm.warp(block.timestamp + _MIN_SEAL_DURATION + 1);

        // seal can't be released before the governance returns to Normal state
        vm.expectRevert(SealBreakerDualGovernance.GovernanceIsLocked.selector);
        _sealBreaker.startRelease(_gateSeal);

        // wait the governance returns to normal state
        vm.warp(block.timestamp + 14 days);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoSignallingDeactivation));
        vm.warp(block.timestamp + _dualGovernance.CONFIG().signallingDeactivationDuration() + 1);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoCooldown));

        // the stETH whale takes his funds back from Escrow
        vm.prank(stEthWhale);
        escrow.unlockStEth();

        vm.warp(block.timestamp + _dualGovernance.CONFIG().signallingCooldownDuration() + 1);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.Normal));

        // now seal may be released
        _sealBreaker.startRelease(_gateSeal);

        // reverts until timelock
        vm.expectRevert(SealBreaker.ReleaseDelayNotPassed.selector);
        _sealBreaker.enactRelease(_gateSeal);

        // anyone may release the seal after timelock
        vm.warp(block.timestamp + _RELEASE_TIMELOCK);
        _sealBreaker.enactRelease(_gateSeal);
        assertFalse(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());
    }

    function testFork_SealWhenDualGovernanceNotLocked() external {
        assertFalse(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.Normal));

        // sealing committee seals the Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // validate Withdrawal Queue was paused
        assertTrue(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());

        // seal can't be released before the min sealing duration has passed
        vm.expectRevert(SealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        vm.warp(block.timestamp + _MIN_SEAL_DURATION + 1);

        // now seal may be released
        _sealBreaker.startRelease(_gateSeal);

        // reverts until timelock
        vm.expectRevert(SealBreaker.ReleaseDelayNotPassed.selector);
        _sealBreaker.enactRelease(_gateSeal);

        // anyone may release the seal after timelock
        vm.warp(block.timestamp + _RELEASE_TIMELOCK);
        _sealBreaker.enactRelease(_gateSeal);
        assertFalse(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());
    }

    function testFork_GateSealMayBeReleasedOnlyOnce() external {
        assertFalse(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.Normal));

        // sealing committee seals the Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // validate Withdrawal Queue was paused
        assertTrue(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());

        // seal can't be released before the min sealing duration has passed
        vm.expectRevert(SealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        vm.warp(block.timestamp + _MIN_SEAL_DURATION + 1);

        // now seal may be released
        _sealBreaker.startRelease(_gateSeal);

        // An attempt to release same gate seal the second time fails
        vm.expectRevert(SealBreaker.GateSealAlreadyReleased.selector);
        _sealBreaker.startRelease(_gateSeal);
    }
}
