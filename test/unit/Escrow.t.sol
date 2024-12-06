// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdError} from "forge-std/StdError.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {ETHValues} from "contracts/types/ETHValue.sol";
import {SharesValues} from "contracts/types/SharesValue.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

import {Escrow} from "contracts/Escrow.sol";
import {EscrowState as EscrowStateLib, State as EscrowState} from "contracts/libraries/EscrowState.sol";
import {WithdrawalsBatchesQueue} from "contracts/libraries/WithdrawalsBatchesQueue.sol";
import {AssetsAccounting, UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";

import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

import {StETHMock} from "scripts/lido-mocks/StETHMock.sol";
import {WstETHMock} from "test/mocks/WstETHMock.sol";
import {WithdrawalQueueMock} from "test/mocks/WithdrawalQueueMock.sol";
import {UnitTest} from "test/utils/unit-test.sol";
import {Random} from "test/utils/random.sol";

interface IEscrow is ISignallingEscrow, IRageQuitEscrow {}

contract EscrowUnitTests is UnitTest {
    Random.Context private _random;
    address private _dualGovernance = makeAddr("dualGovernance");
    address private _vetoer = makeAddr("vetoer");

    Escrow private _masterCopy;
    Escrow private _escrow;

    StETHMock private _stETH;
    WstETHMock private _wstETH;

    WithdrawalQueueMock private _withdrawalQueue;

    Duration private _minLockAssetDuration = Durations.from(1 days);
    uint256 private stethAmount = 100 ether;

    function setUp() external {
        _random = Random.create(block.timestamp);
        _stETH = new StETHMock();
        _wstETH = new WstETHMock(_stETH);
        _withdrawalQueue = new WithdrawalQueueMock(_stETH);
        _withdrawalQueue.setMaxStETHWithdrawalAmount(1_000 ether);
        _masterCopy = _createEscrow(100);
        _escrow =
            _createInitializedEscrowProxy({minWithdrawalsBatchSize: 100, minAssetsLockDuration: _minLockAssetDuration});

        vm.prank(address(_escrow));
        _stETH.approve(address(_withdrawalQueue), type(uint256).max);

        vm.startPrank(_vetoer);
        _stETH.approve(address(_escrow), type(uint256).max);
        _stETH.approve(address(_wstETH), type(uint256).max);
        _wstETH.approve(address(_escrow), type(uint256).max);
        vm.stopPrank();

        _stETH.mint(_vetoer, stethAmount);
        _wstETH.mint(_vetoer, stethAmount);

        vm.mockCall(
            _dualGovernance, abi.encodeWithSelector(IDualGovernance.activateNextState.selector), abi.encode(true)
        );
        _withdrawalQueue.setMinStETHWithdrawalAmount(100);
        _withdrawalQueue.setMaxStETHWithdrawalAmount(1000 * 1e18);

        vm.label(address(_escrow), "Escrow");
        vm.label(address(_stETH), "StETHMock");
        vm.label(address(_wstETH), "WstETHMock");
        vm.label(address(_withdrawalQueue), "WithdrawalQueueMock");
    }

    /*  */

    // ---
    // constructor()
    // ---

    function testFuzz_constructor(
        address steth,
        address wsteth,
        address withdrawalQueue,
        address dualGovernance,
        uint256 size
    ) external {
        Escrow instance = new Escrow(
            IStETH(steth), IWstETH(wsteth), IWithdrawalQueue(withdrawalQueue), IDualGovernance(dualGovernance), size
        );

        assertEq(address(instance.ST_ETH()), address(steth));
        assertEq(address(instance.WST_ETH()), address(wsteth));
        assertEq(address(instance.WITHDRAWAL_QUEUE()), address(withdrawalQueue));
        assertEq(address(instance.DUAL_GOVERNANCE()), address(dualGovernance));
        assertEq(instance.MIN_WITHDRAWALS_BATCH_SIZE(), size);
    }

    // ---
    // initialize()
    // ---

    function test_initialize_HappyPath() external {
        vm.expectEmit();
        emit EscrowStateLib.EscrowStateChanged(EscrowState.NotInitialized, EscrowState.SignallingEscrow);
        vm.expectEmit();
        emit EscrowStateLib.MinAssetsLockDurationSet(Durations.ZERO);

        vm.expectCall(address(_stETH), abi.encodeCall(IERC20.approve, (address(_wstETH), type(uint256).max)));
        vm.expectCall(address(_stETH), abi.encodeCall(IERC20.approve, (address(_withdrawalQueue), type(uint256).max)));

        _createInitializedEscrowProxy({minWithdrawalsBatchSize: 100, minAssetsLockDuration: Durations.ZERO});

        assertEq(_escrow.MIN_WITHDRAWALS_BATCH_SIZE(), 100);
    }

    function test_initialize_RevertOn_CalledNotViaProxy() external {
        Escrow instance = _createEscrow(100);

        vm.expectRevert(Escrow.NonProxyCallsForbidden.selector);
        instance.initialize(Durations.ZERO);
    }

    function testFuzz_initialize_RevertOn_CalledNotFromDualGovernance(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        IEscrow instance = IEscrow(address(_createEscrowProxy(100)));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Escrow.CallerIsNotDualGovernance.selector, stranger));
        instance.initialize(Durations.ZERO);
    }

    // ---
    // lockStETH()
    // ---

    function test_lockStETH_HappyPath() external {
        uint256 amount = 1 ether;

        uint256 sharesAmount = _stETH.getSharesByPooledEth(amount);
        uint256 vetoerBalanceBefore = _stETH.balanceOf(_vetoer);
        uint256 escrowBalanceBefore = _stETH.balanceOf(address(_escrow));

        vm.expectCall(
            address(_stETH),
            abi.encodeCall(IStETH.transferSharesFrom, (address(_vetoer), address(_escrow), sharesAmount))
        );
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);

        vm.prank(_vetoer);
        uint256 lockedStETHShares = _escrow.lockStETH(amount);

        assertEq(lockedStETHShares, sharesAmount);

        uint256 vetoerBalanceAfter = _stETH.balanceOf(_vetoer);
        uint256 escrowBalanceAfter = _stETH.balanceOf(address(_escrow));

        assertEq(vetoerBalanceAfter, vetoerBalanceBefore - amount);
        assertEq(escrowBalanceAfter, escrowBalanceBefore + amount);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), lockedStETHShares);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares.toUint256(), lockedStETHShares);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
        assertEq(state.lastAssetsLockTimestamp, Timestamps.now());
    }

    function test_lockStETH_RevertOn_UnexpectedEscrowState() external {
        _transitToRageQuit();

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        vm.prank(_vetoer);
        _escrow.lockStETH(1 ether);

        assertEq(_stETH.balanceOf(address(_escrow)), 0);
    }

    // ---
    // unlockStETH()
    // ---

    function test_unlockStETH_HappyPath() external {
        uint256 amount = 1 ether;
        uint256 sharesAmount = _stETH.getSharesByPooledEth(amount);

        vm.startPrank(_vetoer);
        _escrow.lockStETH(amount);

        uint256 vetoerBalanceBefore = _stETH.balanceOf(_vetoer);
        uint256 escrowBalanceBefore = _stETH.balanceOf(address(_escrow));

        _wait(_minLockAssetDuration.plusSeconds(1));

        vm.expectCall(address(_stETH), abi.encodeCall(IStETH.transferShares, (address(_vetoer), sharesAmount)));
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);
        uint256 unlockedStETHShares = _escrow.unlockStETH();
        assertEq(unlockedStETHShares, sharesAmount);

        uint256 vetoerBalanceAfter = _stETH.balanceOf(_vetoer);
        uint256 escrowBalanceAfter = _stETH.balanceOf(address(_escrow));

        assertEq(vetoerBalanceAfter, vetoerBalanceBefore + amount);
        assertEq(escrowBalanceAfter, escrowBalanceBefore - amount);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
    }

    function test_unlockStETH_RevertOn_UnexpectedEscrowState() external {
        vm.prank(_vetoer);
        _escrow.lockStETH(1 ether);

        _transitToRageQuit();

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        vm.prank(_vetoer);
        _escrow.unlockStETH();
    }

    function test_unlockStETH_RevertOn_MinAssetsLockDurationNotPassed() external {
        vm.startPrank(_vetoer);
        _escrow.lockStETH(1 ether);

        uint256 lastLockTimestamp = block.timestamp;

        _wait(_minLockAssetDuration.minusSeconds(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.MinAssetsLockDurationNotPassed.selector,
                Durations.from(lastLockTimestamp) + _minLockAssetDuration
            )
        );
        _escrow.unlockStETH();
    }

    // ---
    // lockWstETH()
    // ---

    function test_lockWstETH_HappyPath() external {
        uint256 amount = 1 ether;

        vm.startPrank(_vetoer);
        _wstETH.wrap(amount);

        uint256 vetoerWStBalanceBefore = _wstETH.balanceOf(_vetoer);
        uint256 escrowBalanceBefore = _stETH.balanceOf(address(_escrow));

        vm.expectCall(address(_wstETH), abi.encodeCall(IERC20.transferFrom, (_vetoer, address(_escrow), amount)));
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);

        uint256 lockedStETHShares = _escrow.lockWstETH(amount);
        assertEq(lockedStETHShares, _stETH.getSharesByPooledEth(amount));

        uint256 vetoerWStBalanceAfter = _wstETH.balanceOf(_vetoer);
        uint256 escrowBalanceAfter = _stETH.balanceOf(address(_escrow));

        assertEq(vetoerWStBalanceAfter, vetoerWStBalanceBefore - lockedStETHShares);
        assertEq(escrowBalanceAfter, escrowBalanceBefore + lockedStETHShares);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), lockedStETHShares);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares.toUint256(), lockedStETHShares);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
        assertEq(state.lastAssetsLockTimestamp, Timestamps.now());
    }

    function test_lockWstETH_RevertOn_UnexpectedEscrowState() external {
        _transitToRageQuit();

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        vm.prank(_vetoer);
        _escrow.lockWstETH(1 ether);
    }

    // ---
    // unlockWstETH()
    // ---

    function test_unlockWstETH_HappyPath() external {
        uint256 amount = 1 ether;

        vm.startPrank(_vetoer);
        _wstETH.wrap(amount);

        _escrow.lockWstETH(amount);

        _wait(_minLockAssetDuration.plusSeconds(1));

        uint256 vetoerWStBalanceBefore = _wstETH.balanceOf(_vetoer);
        uint256 escrowBalanceBefore = _stETH.balanceOf(address(_escrow));

        vm.expectCall(address(_wstETH), abi.encodeCall(IWstETH.wrap, (amount)));
        vm.expectCall(address(_wstETH), abi.encodeCall(IERC20.transfer, (_vetoer, amount)));
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);
        uint256 unlockedStETHShares = _escrow.unlockWstETH();

        assertEq(unlockedStETHShares, _stETH.getPooledEthByShares(amount));

        uint256 vetoerWStBalanceAfter = _wstETH.balanceOf(_vetoer);
        uint256 escrowBalanceAfter = _stETH.balanceOf(address(_escrow));

        assertEq(vetoerWStBalanceAfter, vetoerWStBalanceBefore + unlockedStETHShares);
        assertEq(escrowBalanceAfter, escrowBalanceBefore - unlockedStETHShares);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
    }

    function test_unlockWstETH_RevertOn_UnexpectedEscrowState() external {
        uint256 amount = 1 ether;

        vm.startPrank(_vetoer);
        _wstETH.wrap(amount);
        _escrow.lockWstETH(amount);
        vm.stopPrank();

        _transitToRageQuit();

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        vm.prank(_vetoer);
        _escrow.unlockWstETH();
    }

    function test_unlockWstETH_RevertOn_MinAssetsLockDurationNotPassed() external {
        uint256 amount = 1 ether;

        vm.startPrank(_vetoer);
        _wstETH.wrap(amount);
        _escrow.lockWstETH(amount);

        uint256 lastLockTimestamp = block.timestamp;

        _wait(_minLockAssetDuration.minusSeconds(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.MinAssetsLockDurationNotPassed.selector,
                Durations.from(lastLockTimestamp) + _minLockAssetDuration
            )
        );
        _escrow.unlockWstETH();
    }

    // ---
    // lockUnstETH()
    // ---

    function test_lockUnstETH_HappyPath() external {
        uint256[] memory unstethIds = new uint256[](2);
        unstethIds[0] = 1;
        unstethIds[1] = 2;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = new IWithdrawalQueue.WithdrawalRequestStatus[](2);
        statuses[0] = IWithdrawalQueue.WithdrawalRequestStatus(1 ether, 1 ether, _vetoer, block.timestamp, false, false);
        statuses[1] = IWithdrawalQueue.WithdrawalRequestStatus(2 ether, 2 ether, _vetoer, block.timestamp, false, false);

        _withdrawalQueue.setWithdrawalRequestsStatuses(statuses);

        vm.expectCall(
            address(_withdrawalQueue),
            abi.encodeCall(IWithdrawalQueue.transferFrom, (_vetoer, address(_escrow), unstethIds[0]))
        );
        vm.expectCall(
            address(_withdrawalQueue),
            abi.encodeCall(IWithdrawalQueue.transferFrom, (_vetoer, address(_escrow), unstethIds[1]))
        );
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);

        vm.prank(_vetoer);
        _escrow.lockUnstETH(unstethIds);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(
            signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(),
            statuses[0].amountOfShares + statuses[1].amountOfShares
        );
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 2);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertEq(state.unstETHLockedShares.toUint256(), statuses[0].amountOfShares + statuses[1].amountOfShares);
    }

    function test_lockUnstETH_RevertOn_EmptyUnstETHIds() external {
        uint256[] memory unstethIds = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(Escrow.EmptyUnstETHIds.selector));
        _escrow.lockUnstETH(unstethIds);
    }

    function test_lockUnstETH_RevertOn_UnexpectedEscrowState() external {
        uint256[] memory unstethIds = new uint256[](1);
        unstethIds[0] = 1;

        _transitToRageQuit();

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        _escrow.lockUnstETH(unstethIds);
    }

    // ---
    // unlockUnstETH()
    // ---

    function test_unlockUnstETH_HappyPath() external {
        uint256[] memory unstETHAmounts = new uint256[](2);
        unstETHAmounts[0] = 1 ether;
        unstETHAmounts[1] = 2 ether;

        uint256[] memory unstethIds = _vetoerLockedUnstEth(unstETHAmounts);

        _wait(_minLockAssetDuration.plusSeconds(1));

        vm.expectCall(
            address(_withdrawalQueue),
            abi.encodeCall(IWithdrawalQueue.transferFrom, (address(_escrow), _vetoer, unstethIds[0]))
        );
        vm.expectCall(
            address(_withdrawalQueue),
            abi.encodeCall(IWithdrawalQueue.transferFrom, (address(_escrow), _vetoer, unstethIds[1]))
        );
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);

        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstethIds);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
    }

    function test_unlockUnstETH_EmptyUnstETHIds() external {
        uint256[] memory unstethIds = new uint256[](0);

        _wait(_minLockAssetDuration.plusSeconds(1));

        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 0);

        vm.expectRevert(Escrow.EmptyUnstETHIds.selector);
        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstethIds);
    }

    function test_unlockUnstETH_RevertOn_MinAssetsLockDurationNotPassed() external {
        uint256[] memory unstethIds = new uint256[](1);

        _wait(_minLockAssetDuration.minusSeconds(1));

        // Exception. Due to no assets of holder registered in Escrow.
        vm.expectRevert(
            abi.encodeWithSelector(AssetsAccounting.MinAssetsLockDurationNotPassed.selector, _minLockAssetDuration)
        );
        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstethIds);
    }

    function test_unlockUnstETH_RevertOn_UnexpectedEscrowState() external {
        _transitToRageQuit();

        uint256[] memory unstethIds = new uint256[](1);
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstethIds);
    }

    // ---
    // markUnstETHFinalized()
    // ---

    function test_markUnstETHFinalized_HappyPath() external {
        uint256[] memory unstethIds = new uint256[](2);
        uint256[] memory hints = new uint256[](2);
        uint256[] memory responses = new uint256[](2);

        unstethIds[0] = 1;
        unstethIds[1] = 1;

        hints[0] = 1;
        hints[1] = 1;

        responses[0] = 1 ether;
        responses[1] = 1 ether;

        _withdrawalQueue.setClaimableEtherResult(responses);
        vm.expectCall(
            address(_withdrawalQueue), abi.encodeCall(IWithdrawalQueue.getClaimableEther, (unstethIds, hints))
        );

        _escrow.markUnstETHFinalized(unstethIds, hints);
    }

    function test_markUnstETHFinalized_RevertOn_UnexpectedEscrowState() external {
        _transitToRageQuit();

        uint256[] memory unstethIds = new uint256[](0);
        uint256[] memory hints = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        _escrow.markUnstETHFinalized(unstethIds, hints);
    }

    // ---
    // startRageQuit()
    // ---

    function test_startRageQuit_HappyPath() external {
        uint256 lri = Random.nextUint256(_random, 100500);
        _withdrawalQueue.setLastRequestId(lri);

        vm.expectEmit();
        emit EscrowStateLib.RageQuitStarted(Durations.ZERO, Durations.ZERO);
        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalsBatchesQueueOpened(lri);

        _transitToRageQuit();
    }

    function testFuzz_startRageQuit_RevertOn_CalledNotByDualGovernance(address stranger) external {
        vm.assume(stranger != _dualGovernance);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Escrow.CallerIsNotDualGovernance.selector, stranger));
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);
    }

    // ---
    // requestNextWithdrawalsBatch()
    // ---

    function test_requestNextWithdrawalsBatch_HappyPath() external {
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalsBatchesQueueOpened(unstEthIds[0] - 1);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _stETH.mint(address(_escrow), stethAmount);
        _withdrawalQueue.setMinStETHWithdrawalAmount(1);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(unstEthIds);
        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalsBatchesQueueClosed();
        _escrow.requestNextWithdrawalsBatch(100);
    }

    function test_requestNextWithdrawalsBatch_ReturnsEarlyAndClosesWithdrawalsBatchesQueue_When_EscrowHasZeroAmountOfStETH(
    ) external {
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(new uint256[](0));

        _ensureWithdrawalsBatchesQueueClosed();
    }

    function test_requestNextWithdrawalsBatch_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.requestNextWithdrawalsBatch(1);
    }

    function test_requestNextWithdrawalsBatch_RevertOn_InvalidBatchSize() external {
        _transitToRageQuit();

        uint256 batchSize = 1;

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidBatchSize.selector, batchSize));
        _escrow.requestNextWithdrawalsBatch(batchSize);
    }

    function test_requestNextWithdrawalsBatch_RevertOn_InvalidUnstETHIdsSequence() external {
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalsBatchesQueueOpened(unstEthIds[0] - 1);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _stETH.mint(address(_escrow), stethAmount);
        _withdrawalQueue.setRequestWithdrawalsTransferAmount(
            stethAmount - 2 * _escrow.MIN_TRANSFERRABLE_ST_ETH_AMOUNT()
        );

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(unstEthIds);
        _escrow.requestNextWithdrawalsBatch(100);

        vm.expectRevert(WithdrawalsBatchesQueue.InvalidUnstETHIdsSequence.selector);
        _escrow.requestNextWithdrawalsBatch(100);
    }

    // ---
    // claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] calldata hints)
    // ---

    function test_claimNextWithdrawalsBatch_2_HappyPath() external {
        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _withdrawalQueue.setLastCheckpointIndex(1);
        _withdrawalQueue.setCheckpointHints(new uint256[](unstEthIds.length));

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        _withdrawalQueue.setClaimableAmount(stethAmount);
        vm.deal(address(_withdrawalQueue), stethAmount);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstEthIds);
        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(ETHValues.from(stethAmount));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0], new uint256[](unstEthIds.length));

        signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), stethAmount);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), stethAmount);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares.toUint256(), stethAmount);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_UnexpectedState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, 2));
        _escrow.claimNextWithdrawalsBatch(1, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_ClaimingIsFinished() external {
        _transitToRageQuit();

        _escrow.requestNextWithdrawalsBatch(100);
        _escrow.startRageQuitExtensionPeriod();

        vm.expectRevert(EscrowStateLib.ClaimingIsFinished.selector);
        _escrow.claimNextWithdrawalsBatch(1, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_EmptyBatch() external {
        _transitToRageQuit();

        vm.expectRevert(WithdrawalsBatchesQueue.EmptyBatch.selector);
        _escrow.claimNextWithdrawalsBatch(1, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_UnexpectedUnstETHId() external {
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        _withdrawalQueue.setClaimableAmount(stethAmount);
        vm.deal(address(_withdrawalQueue), stethAmount);

        vm.expectRevert(Escrow.UnexpectedUnstETHId.selector);
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0] + 10, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_InvalidHintsLength() external {
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        _withdrawalQueue.setClaimableAmount(stethAmount);
        vm.deal(address(_withdrawalQueue), stethAmount);

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidHintsLength.selector, 10, 1));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0], new uint256[](10));
    }

    // ---
    // claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount)
    // ---

    function test_claimNextWithdrawalsBatch_1_HappyPath() external {
        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        IEscrow.VetoerDetails memory vetoerState = _escrow.getVetoerDetails(_vetoer);

        assertEq(vetoerState.unstETHIdsCount, 0);
        assertEq(vetoerState.stETHLockedShares.toUint256(), stethAmount);
        assertEq(vetoerState.unstETHLockedShares.toUint256(), 0);

        _claimStEthViaWQ(unstEthIds, stethAmount);

        signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), stethAmount);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), stethAmount);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        vetoerState = _escrow.getVetoerDetails(_vetoer);

        assertEq(vetoerState.unstETHIdsCount, 0);
        assertEq(vetoerState.stETHLockedShares.toUint256(), stethAmount);
        assertEq(vetoerState.unstETHLockedShares.toUint256(), 0);
    }

    function test_claimNextWithdrawalsBatch_1_RevertOn_UnexpectedState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, 2));
        _escrow.claimNextWithdrawalsBatch(1);
    }

    function test_claimNextWithdrawalsBatch_1_RevertOn_ClaimingIsFinished() external {
        _transitToRageQuit();

        _escrow.requestNextWithdrawalsBatch(100);
        _escrow.startRageQuitExtensionPeriod();

        vm.expectRevert(EscrowStateLib.ClaimingIsFinished.selector);
        _escrow.claimNextWithdrawalsBatch(1);
    }

    function test_claimNextWithdrawalsBatch_1_RevertOn_EmptyBatch() external {
        _transitToRageQuit();

        vm.expectRevert(WithdrawalsBatchesQueue.EmptyBatch.selector);
        _escrow.claimNextWithdrawalsBatch(1);
    }

    function test_claimNextWithdrawalsBatch_1_RevertOn_InvalidHintsLength() external {
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _withdrawalQueue.setLastCheckpointIndex(1);
        _withdrawalQueue.setCheckpointHints(new uint256[](unstEthIds.length + 10));

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidHintsLength.selector, 11, 1));
        _escrow.claimNextWithdrawalsBatch(unstEthIds.length);
    }

    // ---
    // startRageQuitExtensionPeriod()
    // ---

    function test_startRageQuitExtensionPeriod_HappyPath() external {
        _transitToRageQuit();

        _ensureWithdrawalsBatchesQueueClosed();

        _ensureRageQuitExtensionPeriodStartedNow();
    }

    function test_startRageQuitExtensionPeriod_RevertOn_BatchesQueueIsNotClosed() external {
        vm.expectRevert(Escrow.BatchesQueueIsNotClosed.selector);
        _escrow.startRageQuitExtensionPeriod();
    }

    function test_startRageQuitExtensionPeriod_RevertOn_UnclaimedBatches() external {
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        vm.expectRevert(Escrow.UnclaimedBatches.selector);
        _escrow.startRageQuitExtensionPeriod();
    }

    function test_startRageQuitExtensionPeriod_RevertOn_UnfinalizedUnstETHIds() external {
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        _claimStEthViaWQ(unstEthIds, stethAmount);

        _withdrawalQueue.setLastFinalizedRequestId(0);

        vm.expectRevert(Escrow.UnfinalizedUnstETHIds.selector);
        _escrow.startRageQuitExtensionPeriod();
    }

    // ---
    // claimUnstETH()
    // ---

    function test_claimUnstETH_HappyPath() external {
        uint256[] memory unstEthAmounts = new uint256[](1);
        unstEthAmounts[0] = 1 ether;

        uint256[] memory unstEthIds = _vetoerLockedUnstEth(unstEthAmounts);
        uint256[] memory hints = _finalizeUnstEth(unstEthAmounts, unstEthIds);

        _transitToRageQuit();

        _claimUnstEthFromEscrow(unstEthAmounts, unstEthIds, hints);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), unstEthAmounts[0]);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 1);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertEq(state.unstETHLockedShares.toUint256(), unstEthAmounts[0]);
    }

    function test_claimUnstETH_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.claimUnstETH(new uint256[](1), new uint256[](1));
    }

    function test_claimUnstETH_RevertOn_InvalidRequestId() external {
        bytes memory wqInvalidRequestIdError = abi.encode("WithdrawalQueue.InvalidRequestId");
        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = _withdrawalQueue.REVERT_ON_ID();
        uint256[] memory hints = new uint256[](1);

        _transitToRageQuit();

        vm.expectRevert(WithdrawalQueueMock.InvalidRequestId.selector);
        _escrow.claimUnstETH(unstETHIds, hints);
    }

    function test_claimUnstETH_RevertOn_ArraysLengthMismatch() external {
        bytes memory wqArraysLengthMismatchError = abi.encode("WithdrawalQueue.ArraysLengthMismatch");
        uint256[] memory unstETHIds = new uint256[](2);
        uint256[] memory hints = new uint256[](1);
        uint256[] memory responses = new uint256[](1);
        responses[0] = 1 ether;

        _transitToRageQuit();

        _withdrawalQueue.setClaimableEtherResult(responses);

        vm.expectRevert(WithdrawalQueueMock.ArraysLengthMismatch.selector);
        _escrow.claimUnstETH(unstETHIds, hints);
    }

    function test_claimUnstETH_RevertOn_InvalidUnstETHStatus() external {
        uint256[] memory unstEthAmounts = new uint256[](1);
        unstEthAmounts[0] = 1 ether;

        uint256[] memory unstEthIds = new uint256[](1);
        unstEthIds[0] = Random.nextUint256(_random, 100500);

        uint256[] memory hints = _finalizeUnstEth(unstEthAmounts, unstEthIds);

        _transitToRageQuit();

        _withdrawalQueue.setClaimableAmount(unstEthAmounts[0]);
        _withdrawalQueue.setClaimableEtherResult(unstEthAmounts);
        vm.deal(address(_withdrawalQueue), unstEthAmounts[0]);

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector, unstEthIds[0], UnstETHRecordStatus.NotLocked
            )
        );
        _escrow.claimUnstETH(unstEthIds, hints);
    }

    // ---
    // setMinAssetsLockDuration()
    // ---

    function test_setMinAssetsLockDuration_HappyPath() external {
        Duration newMinAssetsLockDuration = Durations.from(200);
        vm.expectEmit();
        emit EscrowStateLib.MinAssetsLockDurationSet(newMinAssetsLockDuration);
        vm.prank(_dualGovernance);
        _escrow.setMinAssetsLockDuration(newMinAssetsLockDuration);
    }

    function testFuzz_setMinAssetsLockDuration_RevertOn_CalledNotFromDualGovernance(address stranger) external {
        vm.assume(stranger != _dualGovernance);

        Duration newMinAssetsLockDuration = Durations.from(200);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Escrow.CallerIsNotDualGovernance.selector, stranger));
        _escrow.setMinAssetsLockDuration(newMinAssetsLockDuration);
    }

    // ---
    // withdrawETH()
    // ---

    function test_withdrawETH_HappyPath() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        _claimStEthViaWQ(unstEthIds, stethAmount);
        _ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        _wait(Durations.from(1));

        vm.startPrank(_vetoer);
        vm.expectEmit();
        emit AssetsAccounting.ETHWithdrawn(_vetoer, SharesValues.from(stethAmount), ETHValues.from(stethAmount));
        _escrow.withdrawETH();
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore + stethAmount);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), stethAmount);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), stethAmount);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
    }

    function test_withdrawETH_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.withdrawETH();
    }

    function test_withdrawETH_RevertOn_RageQuitExtensionPeriodNotStarted() external {
        _transitToRageQuit();

        vm.expectRevert(EscrowStateLib.RageQuitExtensionPeriodNotStarted.selector);
        _escrow.withdrawETH();
    }

    function test_withdrawETH_RevertOn_EthWithdrawalsDelayNotPassed() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);

        _transitToRageQuit(Durations.from(1), Durations.from(2));
        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        _claimStEthViaWQ(unstEthIds, stethAmount);
        _ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        vm.startPrank(_vetoer);
        vm.expectRevert(EscrowStateLib.EthWithdrawalsDelayNotPassed.selector);
        _escrow.withdrawETH();
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore);
    }

    function test_withdrawETH_RevertOn_InvalidSharesValue() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        address _vetoer2 = makeAddr("vetoer2");
        _stETH.mint(_vetoer2, 100 ether);

        vm.startPrank(_vetoer2);
        _stETH.approve(address(_escrow), type(uint256).max);
        _escrow.lockStETH(100 ether);
        vm.stopPrank();

        _vetoerLockedStEth(stethAmount);

        _wait(_minLockAssetDuration.plusSeconds(1));

        _vetoerUnlockedStEth(stethAmount);

        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        _claimStEthViaWQ(unstEthIds, stethAmount);
        _ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        _wait(_minLockAssetDuration);

        vm.startPrank(_vetoer);
        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, SharesValues.ZERO));
        _escrow.withdrawETH();
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore);
    }

    // ---
    // withdrawETH(uint256[] calldata unstETHIds)
    // ---

    function test_withdrawETH_2_HappyPath() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = 1 ether;
        unstEthAmounts[1] = 10 ether;

        uint256[] memory unstEthIds = _vetoerLockedUnstEth(unstEthAmounts);
        uint256[] memory hints = _finalizeUnstEth(unstEthAmounts, unstEthIds);

        _transitToRageQuit();

        uint256 sum = _claimUnstEthFromEscrow(unstEthAmounts, unstEthIds, hints);

        _ensureWithdrawalsBatchesQueueClosed();

        _ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        _wait(Durations.from(1));

        vm.startPrank(_vetoer);
        vm.expectEmit();
        emit AssetsAccounting.UnstETHWithdrawn(unstEthIds, ETHValues.from(sum));
        _escrow.withdrawETH(unstEthIds);
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore + sum);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), unstEthAmounts[0] + unstEthAmounts[1]);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 2);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertEq(state.unstETHLockedShares.toUint256(), unstEthAmounts[0] + unstEthAmounts[1]);
    }

    function test_withdrawETH_2_RevertOn_EmptyUnstETHIds() external {
        vm.expectRevert(Escrow.EmptyUnstETHIds.selector);
        _escrow.withdrawETH(new uint256[](0));
    }

    function test_withdrawETH_2_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.withdrawETH(new uint256[](1));
    }

    function test_withdrawETH_2_RevertOn_RageQuitExtensionPeriodNotStarted() external {
        _transitToRageQuit();

        vm.expectRevert(EscrowStateLib.RageQuitExtensionPeriodNotStarted.selector);
        _escrow.withdrawETH(new uint256[](1));
    }

    function test_withdrawETH_2_RevertOn_EthWithdrawalsDelayNotPassed() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = 1 ether;
        unstEthAmounts[1] = 10 ether;

        uint256[] memory unstEthIds = _vetoerLockedUnstEth(unstEthAmounts);
        uint256[] memory hints = _finalizeUnstEth(unstEthAmounts, unstEthIds);

        _transitToRageQuit(Durations.from(10), Durations.from(10));

        _claimUnstEthFromEscrow(unstEthAmounts, unstEthIds, hints);

        _ensureWithdrawalsBatchesQueueClosed();

        _ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        _wait(Durations.from(1));

        vm.startPrank(_vetoer);
        vm.expectRevert(EscrowStateLib.EthWithdrawalsDelayNotPassed.selector);
        _escrow.withdrawETH(unstEthIds);
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore);
    }

    function test_withdrawETH_2_RevertOn_InvalidUnstETHStatus() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = 1 ether;
        unstEthAmounts[1] = 10 ether;

        uint256[] memory unstEthIds = _vetoerLockedUnstEth(unstEthAmounts);
        _finalizeUnstEth(unstEthAmounts, unstEthIds);

        _transitToRageQuit();

        _ensureWithdrawalsBatchesQueueClosed();

        _ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        _wait(Durations.from(1));

        vm.startPrank(_vetoer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector, unstEthIds[0], UnstETHRecordStatus.Finalized
            )
        );
        _escrow.withdrawETH(unstEthIds);
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore);
    }

    // ---
    // getLockedAssetsTotals()
    // ---

    function test_getLockedAssetsTotals() external view {
        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);
    }

    // ---
    // getVetoerState()
    // ---

    function test_getVetoerState() external {
        _vetoerLockedStEth(stethAmount);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares.toUint256(), _stETH.getSharesByPooledEth(stethAmount));
        assertEq(state.unstETHLockedShares.toUint256(), 0);
        assertEq(state.lastAssetsLockTimestamp, Timestamps.now());
    }

    // ---
    // getVetoerUnstETHIds()
    // ---

    function test_getVetoerUnstETHIds() external {
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = 1 ether;
        unstEthAmounts[1] = 10 ether;

        assertEq(_escrow.getVetoerUnstETHIds(_vetoer).length, 0);

        uint256[] memory unstEthIds = _vetoerLockedUnstEth(unstEthAmounts);

        uint256[] memory vetoerUnstEthIds = _escrow.getVetoerUnstETHIds(_vetoer);

        assertEq(vetoerUnstEthIds.length, unstEthIds.length);
        assertEq(vetoerUnstEthIds[0], unstEthIds[0]);
        assertEq(vetoerUnstEthIds[1], unstEthIds[1]);

        _wait(_minLockAssetDuration.plusSeconds(1));

        uint256[] memory unstEthIdsToUnlock = new uint256[](1);
        unstEthIdsToUnlock[0] = unstEthIds[0];

        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstEthIdsToUnlock);
        vetoerUnstEthIds = _escrow.getVetoerUnstETHIds(_vetoer);

        assertEq(vetoerUnstEthIds.length, 1);
        assertEq(vetoerUnstEthIds[0], unstEthIds[1]);

        unstEthIdsToUnlock[0] = unstEthIds[1];
        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstEthIdsToUnlock);

        assertEq(_escrow.getVetoerUnstETHIds(_vetoer).length, 0);
    }

    // ---
    // getNextWithdrawalBatch()
    // ---

    function test_getNextWithdrawalBatch() external {
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(stethAmount);

        _transitToRageQuit();

        uint256[] memory claimableUnstEthIds = _escrow.getNextWithdrawalBatch(100);
        assertEq(claimableUnstEthIds.length, 0);

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _withdrawalQueue.setLastCheckpointIndex(1);
        _withdrawalQueue.setCheckpointHints(new uint256[](unstEthIds.length));
        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        claimableUnstEthIds = _escrow.getNextWithdrawalBatch(100);
        assertEq(claimableUnstEthIds.length, unstEthIds.length);
        assertEq(claimableUnstEthIds[0], unstEthIds[0]);

        _withdrawalQueue.setClaimableAmount(stethAmount);
        vm.deal(address(_withdrawalQueue), stethAmount);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstEthIds);
        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(ETHValues.from(stethAmount));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0], new uint256[](unstEthIds.length));

        claimableUnstEthIds = _escrow.getNextWithdrawalBatch(100);
        assertEq(claimableUnstEthIds.length, 0);
    }

    function test_getNextWithdrawalBatch_RevertOn_RageQuit_IsNotStarted() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.getNextWithdrawalBatch(100);
    }

    function test_getNextWithdrawalBatch_RevertOn_UnexpectedState_Signaling() external {
        uint256 batchLimit = 10;
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.getNextWithdrawalBatch(batchLimit);
    }

    function test_getNextWithdrawalBatch_RevertOn_UnexpectedState_NotInitialized() external {
        uint256 batchLimit = 10;
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _masterCopy.getNextWithdrawalBatch(batchLimit);
    }

    // ---
    // isWithdrawalsBatchesClosed()
    // ---

    function test_isWithdrawalsBatchesClosed() external {
        _transitToRageQuit();
        assertFalse(_escrow.isWithdrawalsBatchesClosed());

        _withdrawalQueue.setRequestWithdrawalsResult(new uint256[](0));

        _ensureWithdrawalsBatchesQueueClosed();

        assertTrue(_escrow.isWithdrawalsBatchesClosed());
    }

    function test_isWithdrawalsBatchesClosed_RevertOn_UnexpectedState_Signaling() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.isWithdrawalsBatchesClosed();
    }

    function test_isWithdrawalsBatchesClosed_RevertOn_UnexpectedState_NotInitialized() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _masterCopy.isWithdrawalsBatchesClosed();
    }

    // ---
    // isRageQuitExtensionPeriodStarted()
    // ---

    function test_isRageQuitExtensionPeriodStarted() external {
        _transitToRageQuit();

        assertFalse(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        _ensureWithdrawalsBatchesQueueClosed();

        _ensureRageQuitExtensionPeriodStartedNow();

        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        assertEq(_escrow.getRageQuitEscrowDetails().rageQuitExtensionPeriodStartedAt, Timestamps.now());
    }

    // ---
    // getRageQuitExtensionPeriodStartedAt()
    // ---

    function test_getRageQuitExtensionPeriodStartedAt_RevertOn_NotInitializedState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _masterCopy.getRageQuitEscrowDetails();
    }

    function test_getRageQuitExtensionPeriodStartedAt_RevertOn_SignallingState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.getRageQuitEscrowDetails().rageQuitExtensionPeriodStartedAt;
    }

    function test_getRageQuitExtensionPeriodStartedAt() external {
        _transitToRageQuit();
        Timestamp res = _escrow.getRageQuitEscrowDetails().rageQuitExtensionPeriodStartedAt;
        assertEq(res.toSeconds(), Timestamps.ZERO.toSeconds());
    }

    // ---
    // getRageQuitSupport()
    // ---

    function test_getRageQuitSupport() external {
        uint256 stEthLockedAmount = 80 ether + 100 wei;
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = 1 ether;
        unstEthAmounts[1] = 10 ether;
        uint256[] memory finalizedUnstEthAmounts = new uint256[](1);
        uint256[] memory finalizedUnstEthIds = new uint256[](1);

        PercentD16 actualSupport =
            PercentsD16.fromFraction({numerator: stEthLockedAmount, denominator: _stETH.totalSupply()});

        _vetoerLockedStEth(stEthLockedAmount);

        PercentD16 support = _escrow.getRageQuitSupport();
        assertEq(support, actualSupport);
        assertEq(support, PercentsD16.fromBasisPoints(80_00));

        // When some unstEth are locked in escrow => rage quit support changed

        uint256[] memory unstEthIds = _vetoerLockedUnstEth(unstEthAmounts);

        finalizedUnstEthAmounts[0] = unstEthAmounts[0];
        finalizedUnstEthIds[0] = unstEthIds[0];

        _finalizeUnstEth(finalizedUnstEthAmounts, finalizedUnstEthIds);

        actualSupport = PercentsD16.fromFraction({
            numerator: stEthLockedAmount + unstEthAmounts[1] + unstEthAmounts[0],
            denominator: _stETH.totalSupply() + unstEthAmounts[0]
        });

        support = _escrow.getRageQuitSupport();
        assertEq(support, actualSupport);
        assertEq(support, PercentsD16.fromBasisPoints(91_00));
    }

    // ---
    // isRageQuitFinalized()
    // ---

    function test_isRageQuitFinalized() external {
        _transitToRageQuit();

        _ensureWithdrawalsBatchesQueueClosed();

        _ensureRageQuitExtensionPeriodStartedNow();

        _wait(Durations.from(1));

        assertTrue(_escrow.isRageQuitFinalized());
    }

    // ---
    // getRageQuitEscrowDetails()
    // ---

    function test_getRageQuitEscrowDetails_RevertOn_UnexpectedState_Signaling() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.getRageQuitEscrowDetails();
    }

    function test_getRageQuitEscrowDetails_RevertOn_UnexpectedState_NotInitialized() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _masterCopy.getRageQuitEscrowDetails();
    }

    // ---
    // receive()
    // ---

    function test_receive() external {
        vm.deal(address(_withdrawalQueue), 1 ether);
        vm.deal(address(this), 1 ether);

        assertEq(address(_escrow).balance, 0);

        vm.startPrank(address(_withdrawalQueue));
        ETHValues.from(1 ether).sendTo(payable(address(_escrow)));
        vm.stopPrank();

        assertEq(address(_escrow).balance, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Escrow.InvalidETHSender.selector, address(this), address(_withdrawalQueue))
        );
        ETHValues.from(1 ether).sendTo(payable(address(_escrow)));

        assertEq(address(_escrow).balance, 1 ether);
        assertEq(address(this).balance, 1 ether);
        assertEq(address(_withdrawalQueue).balance, 0);
    }

    // ---
    // MIN_TRANSFERRABLE_ST_ETH_AMOUNT
    // ---

    function test_MIN_TRANSFERRABLE_ST_ETH_AMOUNT() external {
        assertEq(_escrow.MIN_TRANSFERRABLE_ST_ETH_AMOUNT(), 100);
    }

    function test_MIN_TRANSFERRABLE_ST_ETH_AMOUNT_gt_minWithdrawableStETHAmountWei_HappyPath() external {
        uint256 amountToLock = 100;

        uint256 minWithdrawableStETHAmountWei = 99;
        assertEq(_escrow.MIN_TRANSFERRABLE_ST_ETH_AMOUNT(), 100);
        _withdrawalQueue.setMinStETHWithdrawalAmount(minWithdrawableStETHAmountWei);

        // Lock stETH
        _stETH.mint(_vetoer, amountToLock);
        vm.prank(_vetoer);
        _escrow.lockStETH(amountToLock);
        assertEq(_stETH.balanceOf(address(_escrow)), amountToLock);

        // Request withdrawal
        vm.prank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);
        assertEq(_escrow.getNextWithdrawalBatch(100).length, 0);
        assertEq(_escrow.isWithdrawalsBatchesClosed(), false);

        uint256[] memory unstEthIds = new uint256[](1);
        unstEthIds[0] = 1;
        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _escrow.requestNextWithdrawalsBatch(100);

        assertEq(_stETH.balanceOf(address(_escrow)), 0);
        assertEq(_escrow.getNextWithdrawalBatch(100).length, 1);
        assertEq(_escrow.isWithdrawalsBatchesClosed(), true);
    }

    function test_MIN_TRANSFERRABLE_ST_ETH_AMOUNT_gt_minWithdrawableStETHAmountWei_HappyPath_closes_queue() external {
        uint256 amountToLock = 99;

        uint256 minWithdrawableStETHAmountWei = 99;
        assertEq(_escrow.MIN_TRANSFERRABLE_ST_ETH_AMOUNT(), 100);
        _withdrawalQueue.setMinStETHWithdrawalAmount(minWithdrawableStETHAmountWei);

        // Lock stETH
        _stETH.mint(_vetoer, amountToLock);
        vm.prank(_vetoer);
        _escrow.lockStETH(amountToLock);
        assertEq(_stETH.balanceOf(address(_escrow)), amountToLock);

        // Request withdrawal
        vm.prank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);
        assertEq(_escrow.getNextWithdrawalBatch(100).length, 0);
        assertEq(_escrow.isWithdrawalsBatchesClosed(), false);

        uint256[] memory unstEthIds = new uint256[](0);
        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _escrow.requestNextWithdrawalsBatch(100);

        assertEq(_stETH.balanceOf(address(_escrow)), 99);
        assertEq(_escrow.getNextWithdrawalBatch(100).length, 0);
        assertEq(_escrow.isWithdrawalsBatchesClosed(), true);
    }

    function test_MIN_TRANSFERRABLE_ST_ETH_AMOUNT_lt_minWithdrawableStETHAmountWei_HappyPath() external {
        uint256 amountToLock = 101;

        uint256 minWithdrawableStETHAmountWei = 101;
        assertEq(_escrow.MIN_TRANSFERRABLE_ST_ETH_AMOUNT(), 100);
        _withdrawalQueue.setMinStETHWithdrawalAmount(minWithdrawableStETHAmountWei);

        // Lock stETH
        _stETH.mint(_vetoer, amountToLock);
        vm.prank(_vetoer);
        _escrow.lockStETH(amountToLock);
        assertEq(_stETH.balanceOf(address(_escrow)), amountToLock);

        // Request withdrawal
        vm.prank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);
        assertEq(_escrow.getNextWithdrawalBatch(100).length, 0);
        assertEq(_escrow.isWithdrawalsBatchesClosed(), false);

        uint256[] memory unstEthIds = new uint256[](1);
        unstEthIds[0] = 1;
        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _escrow.requestNextWithdrawalsBatch(100);

        assertEq(_stETH.balanceOf(address(_escrow)), 0);
        assertEq(_escrow.getNextWithdrawalBatch(100).length, 1);
        assertEq(_escrow.isWithdrawalsBatchesClosed(), true);
    }

    function test_MIN_TRANSFERRABLE_ST_ETH_AMOUNT_lt_minWithdrawableStETHAmountWei_HappyPath_closes_queue() external {
        uint256 amountToLock = 100;

        uint256 minWithdrawableStETHAmountWei = 101;
        assertEq(_escrow.MIN_TRANSFERRABLE_ST_ETH_AMOUNT(), 100);
        _withdrawalQueue.setMinStETHWithdrawalAmount(minWithdrawableStETHAmountWei);

        // Lock stETH
        _stETH.mint(_vetoer, amountToLock);
        vm.prank(_vetoer);
        _escrow.lockStETH(amountToLock);
        assertEq(_stETH.balanceOf(address(_escrow)), amountToLock);

        // Request withdrawal
        vm.prank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);
        assertEq(_escrow.getNextWithdrawalBatch(100).length, 0);
        assertEq(_escrow.isWithdrawalsBatchesClosed(), false);

        uint256[] memory unstEthIds = new uint256[](1);
        unstEthIds[0] = 1;
        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _escrow.requestNextWithdrawalsBatch(100);

        assertEq(_stETH.balanceOf(address(_escrow)), 100);
        assertEq(_escrow.getNextWithdrawalBatch(100).length, 0);
        assertEq(_escrow.isWithdrawalsBatchesClosed(), true);
    }

    // ---
    // helper methods
    // ---

    function _createEscrow(uint256 size) internal returns (Escrow) {
        return new Escrow(_stETH, _wstETH, _withdrawalQueue, IDualGovernance(_dualGovernance), size);
    }

    function _createEscrowProxy(uint256 minWithdrawalsBatchSize) internal returns (Escrow) {
        Escrow masterCopy = _createEscrow(minWithdrawalsBatchSize);
        return Escrow(payable(Clones.clone(address(masterCopy))));
    }

    function _createInitializedEscrowProxy(
        uint256 minWithdrawalsBatchSize,
        Duration minAssetsLockDuration
    ) internal returns (Escrow) {
        Escrow instance = _createEscrowProxy(minWithdrawalsBatchSize);

        vm.prank(_dualGovernance);
        instance.initialize(minAssetsLockDuration);
        return instance;
    }

    function _transitToRageQuit() internal {
        vm.prank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);
    }

    function _transitToRageQuit(Duration rqExtensionPeriod, Duration rqEthWithdrawalsDelay) internal {
        vm.prank(_dualGovernance);
        _escrow.startRageQuit(rqExtensionPeriod, rqEthWithdrawalsDelay);
    }

    function _vetoerLockedStEth(uint256 amount) internal {
        vm.prank(_vetoer);
        _escrow.lockStETH(amount);
    }

    function _vetoerLockedUnstEth(uint256[] memory amounts) internal returns (uint256[] memory unstethIds) {
        unstethIds = new uint256[](amounts.length);
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](amounts.length);

        for (uint256 i = 0; i < amounts.length; ++i) {
            unstethIds[i] = i;
            statuses[i] =
                IWithdrawalQueue.WithdrawalRequestStatus(amounts[i], amounts[i], _vetoer, block.timestamp, false, false);
        }

        _withdrawalQueue.setWithdrawalRequestsStatuses(statuses);

        vm.prank(_vetoer);
        _escrow.lockUnstETH(unstethIds);
    }

    function _finalizeUnstEth(
        uint256[] memory amounts,
        uint256[] memory finalizedUnstEthIds
    ) internal returns (uint256[] memory hints) {
        assertEq(amounts.length, finalizedUnstEthIds.length);

        hints = new uint256[](amounts.length);
        uint256[] memory responses = new uint256[](amounts.length);

        for (uint256 i = 0; i < amounts.length; ++i) {
            hints[i] = i;
            responses[i] = amounts[i];
        }

        _withdrawalQueue.setClaimableEtherResult(responses);

        _escrow.markUnstETHFinalized(finalizedUnstEthIds, hints);

        for (uint256 i = 0; i < amounts.length; ++i) {
            _stETH.burn(_vetoer, amounts[i]);
        }
    }

    function _claimUnstEthFromEscrow(
        uint256[] memory amounts,
        uint256[] memory unstEthIds,
        uint256[] memory hints
    ) internal returns (uint256 sum) {
        assertEq(amounts.length, unstEthIds.length);
        assertEq(amounts.length, hints.length);

        sum = 0;
        for (uint256 i = 0; i < amounts.length; ++i) {
            sum += amounts[i];
        }

        _withdrawalQueue.setClaimableAmount(sum);
        _withdrawalQueue.setClaimableEtherResult(amounts);
        vm.deal(address(_withdrawalQueue), sum);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHClaimed(unstEthIds, ETHValues.from(sum));
        _escrow.claimUnstETH(unstEthIds, hints);
    }

    function _claimStEthViaWQ(uint256[] memory unstEthIds, uint256 amount) internal {
        _withdrawalQueue.setClaimableAmount(amount);
        _withdrawalQueue.setLastCheckpointIndex(1);
        _withdrawalQueue.setCheckpointHints(new uint256[](unstEthIds.length));
        vm.deal(address(_withdrawalQueue), amount);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstEthIds);
        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(ETHValues.from(amount));
        _escrow.claimNextWithdrawalsBatch(unstEthIds.length);
    }

    function _vetoerUnlockedStEth(uint256 amount) internal {
        vm.startPrank(_vetoer);
        vm.expectEmit();
        emit AssetsAccounting.StETHSharesUnlocked(_vetoer, SharesValues.from(_stETH.getSharesByPooledEth(amount)));
        _escrow.unlockStETH();
        vm.stopPrank();
    }

    function _ensureUnstEthAddedToWithdrawalsBatchesQueue(uint256[] memory unstEthIds, uint256 ethAmount) internal {
        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(unstEthIds);
        _escrow.requestNextWithdrawalsBatch(100);

        assertEq(_stETH.balanceOf(address(_escrow)), 0);
    }

    function _ensureWithdrawalsBatchesQueueClosed() internal {
        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalsBatchesQueueClosed();
        _escrow.requestNextWithdrawalsBatch(100);
    }

    function _ensureRageQuitExtensionPeriodStartedNow() internal {
        vm.expectEmit();
        emit EscrowStateLib.RageQuitExtensionPeriodStarted(Timestamps.now());
        _escrow.startRageQuitExtensionPeriod();
    }

    function _getUnstEthIdsFromWQ() internal returns (uint256[] memory unstEthIds) {
        uint256 lri = Random.nextUint256(_random, 100500);
        _withdrawalQueue.setLastRequestId(lri);
        _withdrawalQueue.setLastFinalizedRequestId(lri + 1);

        unstEthIds = new uint256[](1);
        unstEthIds[0] = lri + 1;
    }
}
