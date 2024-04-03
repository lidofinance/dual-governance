// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {
    Utils,
    ExecutorCall,
    IDangerousContract,
    ExecutorCallHelpers,
    ScenarioTestBlueprint
} from "../utils/scenario-test-blueprint.sol";

import {Escrow} from "contracts/Escrow.sol";
import {GateSealBreaker, GateSealBreakerDualGovernance, IGateSeal} from "contracts/GateSealBreaker.sol";
import {GateSealMock} from "contracts/mocks/GateSealMock.sol";

import {Utils} from "../utils/utils.sol";
import {IWithdrawalQueue, IERC20} from "../utils/interfaces.sol";
import {IGovernanceState} from "../../contracts/interfaces/IGovernanceState.sol";
import {DAO_AGENT, DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER} from "../utils/mainnet-addresses.sol";

contract SealBreakerScenarioTest is ScenarioTestBlueprint {
    uint256 private immutable _DELAY = 3 days;
    uint256 private immutable _SEAL_DURATION = type(uint256).max;
    uint256 private immutable _MIN_SEAL_DURATION = 14 days;
    uint256 internal immutable _RELEASE_DELAY = 5 days;
    uint256 internal immutable _RELEASE_TIMELOCK = 14 days;

    IGateSeal private _gateSeal;
    address[] private _sealables;
    GateSealBreakerDualGovernance private _sealBreaker;

    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);

        _sealables.push(WITHDRAWAL_QUEUE);

        _gateSeal = IGateSeal(address(new GateSealMock(
            address(_dualGovernance), _SEALING_COMMITTEE, _SEALING_COMMITTEE_LIFETIME, _SEAL_DURATION, _sealables
        )));

        _sealBreaker = new GateSealBreakerDualGovernance(_RELEASE_DELAY, address(this), address(_dualGovernance));

        _sealBreaker.registerGateSeal(_gateSeal);

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
        vm.expectRevert(GateSealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        // validate Withdrawal Queue was paused
        assertTrue(IWithdrawalQueue(WITHDRAWAL_QUEUE).isPaused());

        vm.warp(block.timestamp + _MIN_SEAL_DURATION + 1);

        // validate the dual governance still in the veto signaling state
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoSignalling));

        // seal can't be released before the governance returns to Normal state
        vm.expectRevert(GateSealBreakerDualGovernance.GovernanceIsLocked.selector);
        _sealBreaker.startRelease(_gateSeal);

        // wait the governance returns to normal state
        vm.warp(block.timestamp + 14 days);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoSignallingDeactivation));
        vm.warp(block.timestamp + _dualGovernance.CONFIG().SIGNALLING_DEACTIVATION_DURATION() + 1);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoCooldown));

        // anyone may start release the seal
        _sealBreaker.startRelease(_gateSeal);

        // reverts until timelock
        vm.expectRevert(GateSealBreaker.ReleaseDelayNotPassed.selector);
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
        vm.expectRevert(GateSealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        vm.warp(block.timestamp + _MIN_SEAL_DURATION + 1);

        // seal can't be released before the governance returns to Normal state
        vm.expectRevert(GateSealBreakerDualGovernance.GovernanceIsLocked.selector);
        _sealBreaker.startRelease(_gateSeal);

        // wait the governance returns to normal state
        vm.warp(block.timestamp + 14 days);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoSignallingDeactivation));
        vm.warp(block.timestamp + _dualGovernance.CONFIG().SIGNALLING_DEACTIVATION_DURATION() + 1);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.VetoCooldown));

        // the stETH whale takes his funds back from Escrow
        vm.prank(stEthWhale);
        escrow.unlockStEth();

        vm.warp(block.timestamp + _dualGovernance.CONFIG().SIGNALLING_COOLDOWN_DURATION() + 1);
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.currentState()), uint256(IGovernanceState.State.Normal));

        // now seal may be released
        _sealBreaker.startRelease(_gateSeal);

        // reverts until timelock
        vm.expectRevert(GateSealBreaker.ReleaseDelayNotPassed.selector);
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
        vm.expectRevert(GateSealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        vm.warp(block.timestamp + _MIN_SEAL_DURATION + 1);

        // now seal may be released
        _sealBreaker.startRelease(_gateSeal);

        // reverts until timelock
        vm.expectRevert(GateSealBreaker.ReleaseDelayNotPassed.selector);
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
        vm.expectRevert(GateSealBreaker.MinSealDurationNotPassed.selector);
        _sealBreaker.startRelease(_gateSeal);

        vm.warp(block.timestamp + _MIN_SEAL_DURATION + 1);

        // now seal may be released
        _sealBreaker.startRelease(_gateSeal);

        // An attempt to release same gate seal the second time fails
        vm.expectRevert(GateSealBreaker.GateSealAlreadyReleased.selector);
        _sealBreaker.startRelease(_gateSeal);
    }
}
