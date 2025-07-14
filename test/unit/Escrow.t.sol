// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// solhint-disable-next-line no-console
import {console} from "forge-std/console.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";
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

uint256 constant ACCURACY = 2 wei;
uint256 constant ONE_PERCENT_D16 = 10 ** 16;
uint256 constant TWENTY_PERCENTS_D16 = 20 * ONE_PERCENT_D16;

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
    Duration private _maxMinAssetsLockDuration = Durations.from(100 days);
    uint256 private stethAmount = 100 ether;
    uint256 private stethInitialEthAmount = 100 wei + stethAmount;

    function setUp() external {
        uint256 randomSeed = vm.unixTime();
        _random = Random.create(randomSeed);

        // solhint-disable-next-line no-console
        console.log("Using random seed:", randomSeed);

        _stETH = new StETHMock();
        _wstETH = new WstETHMock(_stETH);
        _withdrawalQueue = new WithdrawalQueueMock(_stETH);
        _withdrawalQueue.setMaxStETHWithdrawalAmount(1_000 ether);
        _masterCopy = _createEscrow(100, _maxMinAssetsLockDuration);
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

        vm.mockCall(
            _dualGovernance, abi.encodeWithSelector(IDualGovernance.activateNextState.selector), abi.encode(true)
        );
        _withdrawalQueue.setMinStETHWithdrawalAmount(100);
        _withdrawalQueue.setMaxStETHWithdrawalAmount(1000 * 1e18);

        uint256 variablePercent = Random.nextUint256(_random, TWENTY_PERCENTS_D16);
        uint256 rebaseFactor = 90 * ONE_PERCENT_D16 + variablePercent;
        PercentD16 rebaseFactorD16 = PercentsD16.from(rebaseFactor);

        // solhint-disable-next-line no-console
        console.log("Using ST_ETH rebase factor (%%):", _percentD16ToString(rebaseFactorD16));

        _stETH.rebaseTotalPooledEther(rebaseFactorD16);

        vm.label(address(_escrow), "Escrow");
        vm.label(address(_stETH), "StETHMock");
        vm.label(address(_wstETH), "WstETHMock");
        vm.label(address(_withdrawalQueue), "WithdrawalQueueMock");
    }

    // ---
    // constructor()
    // ---

    function testFuzz_constructor(
        address steth,
        address wsteth,
        address withdrawalQueue,
        address dualGovernance,
        uint256 size,
        Duration maxMinAssetsLockDuration
    ) external {
        Escrow instance = new Escrow(
            IStETH(steth),
            IWstETH(wsteth),
            IWithdrawalQueue(withdrawalQueue),
            IDualGovernance(dualGovernance),
            size,
            maxMinAssetsLockDuration
        );

        assertEq(address(instance.ST_ETH()), address(steth));
        assertEq(address(instance.WST_ETH()), address(wsteth));
        assertEq(address(instance.WITHDRAWAL_QUEUE()), address(withdrawalQueue));
        assertEq(address(instance.DUAL_GOVERNANCE()), address(dualGovernance));
        assertEq(instance.MIN_WITHDRAWALS_BATCH_SIZE(), size);
        assertEq(instance.MAX_MIN_ASSETS_LOCK_DURATION(), maxMinAssetsLockDuration);
    }

    // ---
    // initialize()
    // ---

    function testFuzz_initialize_HappyPath(Duration minAssetLockDuration) external {
        vm.assume(minAssetLockDuration > Durations.ZERO);
        vm.assume(minAssetLockDuration <= _maxMinAssetsLockDuration);

        vm.expectEmit();
        emit EscrowStateLib.EscrowStateChanged(EscrowState.NotInitialized, EscrowState.SignallingEscrow);
        vm.expectEmit();
        emit EscrowStateLib.MinAssetsLockDurationSet(minAssetLockDuration);

        vm.expectCall(address(_stETH), abi.encodeCall(IERC20.approve, (address(_wstETH), type(uint256).max)));
        vm.expectCall(address(_stETH), abi.encodeCall(IERC20.approve, (address(_withdrawalQueue), type(uint256).max)));

        Escrow escrowInstance =
            _createInitializedEscrowProxy({minWithdrawalsBatchSize: 100, minAssetsLockDuration: minAssetLockDuration});

        assertEq(escrowInstance.MIN_WITHDRAWALS_BATCH_SIZE(), 100);
        assertEq(escrowInstance.getMinAssetsLockDuration(), minAssetLockDuration);
        assertTrue(escrowInstance.getEscrowState() == EscrowState.SignallingEscrow);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = escrowInstance.getSignallingEscrowDetails();
        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);
    }

    function test_initialize_RevertOn_CalledNotViaProxy() external {
        Escrow instance = _createEscrow(100, _maxMinAssetsLockDuration);

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
    // getEscrowState()
    // ---

    function test_getEscrowState_HappyPath() external {
        assertTrue(_masterCopy.getEscrowState() == EscrowState.NotInitialized);
        assertTrue(_escrow.getEscrowState() == EscrowState.SignallingEscrow);

        _transitToRageQuit();
        assertTrue(_escrow.getEscrowState() == EscrowState.RageQuitEscrow);
    }

    // ---
    // lockStETH()
    // ---

    function test_lockStETH_HappyPath() external {
        uint256 sharesAmount = 1 ether;
        uint256 amount = _stETH.getPooledEthByShares(sharesAmount);
        uint256 vetoerBalanceBefore = _stETH.balanceOf(_vetoer);
        uint256 escrowBalanceBefore = _stETH.balanceOf(address(_escrow));

        vm.expectCall(
            address(_stETH),
            abi.encodeCall(
                IStETH.transferSharesFrom, (address(_vetoer), address(_escrow), _stETH.getSharesByPooledEth(amount))
            )
        );
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);

        vm.prank(_vetoer);
        uint256 lockedStETHShares = _escrow.lockStETH(amount);

        assertApproxEqAbs(lockedStETHShares, sharesAmount, ACCURACY);

        uint256 vetoerBalanceAfter = _stETH.balanceOf(_vetoer);
        uint256 escrowBalanceAfter = _stETH.balanceOf(address(_escrow));

        assertApproxEqAbs(
            vetoerBalanceAfter,
            _stETH.getPooledEthByShares(_stETH.getSharesByPooledEth(vetoerBalanceBefore) - sharesAmount),
            2 * ACCURACY
        );
        assertApproxEqAbs(
            escrowBalanceAfter,
            _stETH.getPooledEthByShares(_stETH.getSharesByPooledEth(escrowBalanceBefore) + sharesAmount),
            2 * ACCURACY
        );

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

        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.RageQuitEscrow)
        );
        vm.prank(_vetoer);
        _escrow.lockStETH(1 ether);

        assertEq(_stETH.balanceOf(address(_escrow)), 0);
    }

    // ---
    // unlockStETH()
    // ---

    function test_unlockStETH_HappyPath() external {
        uint256 sharesAmount = 1 ether;
        uint256 amount = _stETH.getPooledEthByShares(sharesAmount);

        vm.startPrank(_vetoer);
        _escrow.lockStETH(amount);

        uint256 vetoerBalanceBefore = _stETH.balanceOf(_vetoer);

        _wait(_minLockAssetDuration.plusSeconds(1));

        vm.expectCall(
            address(_stETH),
            abi.encodeCall(IStETH.transferShares, (address(_vetoer), _stETH.getSharesByPooledEth(amount)))
        );
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);
        uint256 unlockedStETHShares = _escrow.unlockStETH();
        assertApproxEqAbs(unlockedStETHShares, sharesAmount, ACCURACY);

        uint256 vetoerBalanceAfter = _stETH.balanceOf(_vetoer);
        uint256 escrowBalanceAfter = _stETH.balanceOf(address(_escrow));

        assertApproxEqAbs(
            vetoerBalanceAfter,
            _stETH.getPooledEthByShares(_stETH.getSharesByPooledEth(vetoerBalanceBefore) + sharesAmount),
            ACCURACY
        );
        assertEq(escrowBalanceAfter, 0);

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
        uint256 amount = _stETH.getPooledEthByShares(1 ether);
        vm.prank(_vetoer);
        _escrow.lockStETH(amount);

        _transitToRageQuit();

        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.RageQuitEscrow)
        );
        vm.prank(_vetoer);
        _escrow.unlockStETH();
    }

    function test_unlockStETH_RevertOn_MinAssetsLockDurationNotPassed() external {
        vm.startPrank(_vetoer);
        _escrow.lockStETH(_stETH.getPooledEthByShares(1 ether));

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
        uint256 sharesAmount = 1 ether;
        uint256 amount = _stETH.getPooledEthByShares(sharesAmount);

        vm.startPrank(_vetoer);
        uint256 wstEthAmount = _wstETH.wrap(amount);
        assertApproxEqAbs(wstEthAmount, sharesAmount, ACCURACY);

        uint256 vetoerWStBalanceBefore = _wstETH.balanceOf(_vetoer);
        uint256 escrowBalanceBefore = _stETH.balanceOf(address(_escrow));
        assertEq(escrowBalanceBefore, 0);

        vm.expectCall(address(_wstETH), abi.encodeCall(IERC20.transferFrom, (_vetoer, address(_escrow), wstEthAmount)));
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);

        uint256 lockedStETHShares = _escrow.lockWstETH(wstEthAmount);
        assertApproxEqAbs(lockedStETHShares, _stETH.getSharesByPooledEth(amount), ACCURACY);

        uint256 vetoerWStBalanceAfter = _wstETH.balanceOf(_vetoer);
        uint256 escrowBalanceAfter = _stETH.balanceOf(address(_escrow));

        assertApproxEqAbs(vetoerWStBalanceAfter, vetoerWStBalanceBefore - lockedStETHShares, ACCURACY);
        assertApproxEqAbs(escrowBalanceAfter, _stETH.getPooledEthByShares(lockedStETHShares), ACCURACY);

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

        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.RageQuitEscrow)
        );
        vm.prank(_vetoer);
        _escrow.lockWstETH(1 ether);
    }

    // ---
    // unlockWstETH()
    // ---

    function test_unlockWstETH_HappyPath() external {
        uint256 sharesAmount = 1 ether;
        uint256 amount = _stETH.getPooledEthByShares(sharesAmount);

        vm.startPrank(_vetoer);
        uint256 wstEthAmount = _wstETH.wrap(amount);
        assertApproxEqAbs(wstEthAmount, sharesAmount, ACCURACY);

        uint256 lockedStETHShares = _escrow.lockWstETH(wstEthAmount);
        assertApproxEqAbs(lockedStETHShares, _stETH.getSharesByPooledEth(amount), ACCURACY);

        _wait(_minLockAssetDuration.plusSeconds(1));

        uint256 vetoerWStBalanceBefore = _wstETH.balanceOf(_vetoer);
        uint256 escrowBalanceBefore = _stETH.balanceOf(address(_escrow));

        vm.expectCall(address(_wstETH), abi.encodeCall(IWstETH.wrap, (escrowBalanceBefore)));
        vm.expectCall(
            address(_wstETH),
            abi.encodeCall(IERC20.transfer, (_vetoer, _stETH.getSharesByPooledEth(escrowBalanceBefore)))
        );
        vm.expectCall(address(_dualGovernance), abi.encodeCall(IDualGovernance.activateNextState, ()), 2);
        uint256 unlockedStETHShares = _escrow.unlockWstETH();

        assertApproxEqAbs(unlockedStETHShares, wstEthAmount, 2 * ACCURACY);

        uint256 vetoerWStBalanceAfter = _wstETH.balanceOf(_vetoer);
        uint256 escrowBalanceAfter = _stETH.balanceOf(address(_escrow));

        assertEq(vetoerWStBalanceAfter, vetoerWStBalanceBefore + unlockedStETHShares);
        assertApproxEqAbs(vetoerWStBalanceAfter, wstEthAmount, 2 * ACCURACY);
        assertApproxEqAbs(escrowBalanceAfter, 0, ACCURACY);

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
        uint256 sharesAmount = 1 ether;
        uint256 amount = _stETH.getPooledEthByShares(sharesAmount);

        vm.startPrank(_vetoer);
        uint256 wstEthAmount = _wstETH.wrap(amount);
        _escrow.lockWstETH(wstEthAmount);
        vm.stopPrank();

        _transitToRageQuit();

        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.RageQuitEscrow)
        );
        vm.prank(_vetoer);
        _escrow.unlockWstETH();

        assertApproxEqAbs(_stETH.balanceOf(address(_escrow)), amount, ACCURACY);
        assertEq(_wstETH.balanceOf(_vetoer), 0);
    }

    function test_unlockWstETH_RevertOn_MinAssetsLockDurationNotPassed() external {
        uint256 sharesAmount = 1 ether;
        uint256 amount = _stETH.getPooledEthByShares(sharesAmount);

        vm.startPrank(_vetoer);
        uint256 wstEthAmount = _wstETH.wrap(amount);
        _escrow.lockWstETH(wstEthAmount);

        uint256 lastLockTimestamp = block.timestamp;

        _wait(_minLockAssetDuration.minusSeconds(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.MinAssetsLockDurationNotPassed.selector,
                Durations.from(lastLockTimestamp) + _minLockAssetDuration
            )
        );
        _escrow.unlockWstETH();

        assertApproxEqAbs(_stETH.balanceOf(address(_escrow)), amount, ACCURACY);
        assertEq(_wstETH.balanceOf(_vetoer), 0);
    }

    // ---
    // lockUnstETH()
    // ---

    function test_lockUnstETH_HappyPath() external {
        uint256[] memory unstethIds = new uint256[](2);
        unstethIds[0] = 1;
        unstethIds[1] = 2;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = new IWithdrawalQueue.WithdrawalRequestStatus[](2);
        statuses[0] = IWithdrawalQueue.WithdrawalRequestStatus(
            1 ether, _stETH.getSharesByPooledEth(1 ether), _vetoer, block.timestamp, false, false
        );
        statuses[1] = IWithdrawalQueue.WithdrawalRequestStatus(
            2 ether, _stETH.getSharesByPooledEth(2 ether), _vetoer, block.timestamp, false, false
        );

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

        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.RageQuitEscrow)
        );
        _escrow.lockUnstETH(unstethIds);
    }

    // ---
    // unlockUnstETH()
    // ---

    function test_unlockUnstETH_HappyPath() external {
        uint256[] memory unstETHAmounts = new uint256[](2);
        unstETHAmounts[0] = _stETH.getPooledEthByShares(1 ether);
        unstETHAmounts[1] = _stETH.getPooledEthByShares(2 ether);

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
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.RageQuitEscrow)
        );
        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstethIds);
    }

    // ---
    // markUnstETHFinalized()
    // ---

    function test_markUnstETHFinalized_HappyPath() external {
        uint256 unstethShares1 = 30 ether;
        uint256 unstethShares2 = 2 ether;
        uint256[] memory unstETHAmounts = new uint256[](2);
        unstETHAmounts[0] = _stETH.getPooledEthByShares(unstethShares1);
        unstETHAmounts[1] = _stETH.getPooledEthByShares(unstethShares2);
        uint256[] memory unstethIds = _vetoerLockedUnstEth(unstETHAmounts);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertApproxEqAbs(
            signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(),
            unstethShares1 + unstethShares2,
            2 * ACCURACY
        );
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 2);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertApproxEqAbs(state.unstETHLockedShares.toUint256(), unstethShares1 + unstethShares2, 2 * ACCURACY);
        assertEq(
            _escrow.getRageQuitSupport().toUint256(),
            PercentsD16.fromFraction({
                numerator: _stETH.getPooledEthByShares(unstethShares1 + unstethShares2),
                denominator: _stETH.totalSupply()
            }).toUint256()
        );

        assertTrue(_escrow.getEscrowState() == EscrowState.SignallingEscrow);

        uint256[] memory hints = new uint256[](2);
        uint256[] memory responses = new uint256[](2);

        hints[0] = 1;
        hints[1] = 1;

        responses[0] = unstETHAmounts[0];
        responses[1] = unstETHAmounts[1];

        _withdrawalQueue.setClaimableEtherResult(responses);
        vm.expectCall(
            address(_withdrawalQueue), abi.encodeCall(IWithdrawalQueue.getClaimableEther, (unstethIds, hints))
        );

        _escrow.markUnstETHFinalized(unstethIds, hints);

        assertTrue(_escrow.getEscrowState() == EscrowState.SignallingEscrow);

        signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), unstETHAmounts[0] + unstETHAmounts[1]);

        state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 2);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertApproxEqAbs(state.unstETHLockedShares.toUint256(), unstethShares1 + unstethShares2, 2 * ACCURACY);

        PercentD16 support = _escrow.getRageQuitSupport();

        assertEq(
            support.toUint256(),
            PercentsD16.fromFraction({
                numerator: unstETHAmounts[0] + unstETHAmounts[1],
                denominator: _stETH.totalSupply() + unstETHAmounts[0] + unstETHAmounts[1]
            }).toUint256()
        );
    }

    function test_markUnstETHFinalized_HappyPath_NFTs_not_locked_in_Escrow() external {
        uint256[] memory unstethIds = new uint256[](2);
        uint256[] memory hints = new uint256[](2);
        uint256[] memory responses = new uint256[](2);

        unstethIds[0] = 1;
        unstethIds[1] = 1;

        hints[0] = 1;
        hints[1] = 1;

        responses[0] = _stETH.getPooledEthByShares(1 ether);
        responses[1] = _stETH.getPooledEthByShares(1 ether);

        _withdrawalQueue.setClaimableEtherResult(responses);
        vm.expectCall(
            address(_withdrawalQueue), abi.encodeCall(IWithdrawalQueue.getClaimableEther, (unstethIds, hints))
        );

        assertTrue(_escrow.getEscrowState() == EscrowState.SignallingEscrow);
        assertEq(_escrow.getRageQuitSupport().toUint256(), 0);

        _escrow.markUnstETHFinalized(unstethIds, hints);

        assertTrue(_escrow.getEscrowState() == EscrowState.SignallingEscrow);
        assertEq(_escrow.getRageQuitSupport().toUint256(), 0);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);
    }

    function test_markUnstETHFinalized_RevertOn_UnexpectedEscrowState() external {
        _transitToRageQuit();

        uint256[] memory unstethIds = new uint256[](1);
        uint256[] memory hints = new uint256[](1);

        unstethIds[0] = 1;
        hints[0] = 1;

        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.RageQuitEscrow)
        );
        _escrow.markUnstETHFinalized(unstethIds, hints);
    }

    function test_markUnstETHFinalized_RevertOn_EmptyUnstETHIds() external {
        uint256[] memory unstethIds = new uint256[](0);
        uint256[] memory hints = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(Escrow.EmptyUnstETHIds.selector));
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
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
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
        uint256 ethAmount = _stETH.getPooledEthByShares(stethAmount);
        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(ethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _withdrawalQueue.setLastCheckpointIndex(1);
        _withdrawalQueue.setCheckpointHints(new uint256[](unstEthIds.length));

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);

        _withdrawalQueue.setClaimableAmount(ethAmount);
        vm.deal(address(_withdrawalQueue), ethAmount);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstEthIds);
        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(ETHValues.from(ethAmount));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0], new uint256[](unstEthIds.length));

        signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertApproxEqAbs(signallingEscrowDetails.totalStETHLockedShares.toUint256(), stethAmount, ACCURACY);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), ethAmount);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertApproxEqAbs(state.stETHLockedShares.toUint256(), stethAmount, ACCURACY);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
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

    function test_claimNextWithdrawalsBatch_2_RevertOn_InvalidFromUnstETHId() external {
        uint256 ethAmount = _stETH.getPooledEthByShares(stethAmount);
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(ethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);

        _withdrawalQueue.setClaimableAmount(ethAmount);
        vm.deal(address(_withdrawalQueue), ethAmount);

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidFromUnstETHId.selector, unstEthIds[0] + 10));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0] + 10, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_InvalidHintsLength() external {
        uint256 ethAmount = _stETH.getPooledEthByShares(stethAmount);
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(ethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);

        _withdrawalQueue.setClaimableAmount(ethAmount);
        vm.deal(address(_withdrawalQueue), ethAmount);

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidHintsLength.selector, 10, 1));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0], new uint256[](10));
    }

    // ---
    // claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount)
    // ---

    function test_claimNextWithdrawalsBatch_1_HappyPath() external {
        uint256 ethAmount = _stETH.getPooledEthByShares(stethAmount);
        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(ethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);

        IEscrow.VetoerDetails memory vetoerState = _escrow.getVetoerDetails(_vetoer);

        assertEq(vetoerState.unstETHIdsCount, 0);
        assertApproxEqAbs(vetoerState.stETHLockedShares.toUint256(), stethAmount, ACCURACY);
        assertEq(vetoerState.unstETHLockedShares.toUint256(), 0);

        _claimStEthViaWQ(unstEthIds, ethAmount);

        signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertApproxEqAbs(signallingEscrowDetails.totalStETHLockedShares.toUint256(), stethAmount, ACCURACY);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), ethAmount);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        vetoerState = _escrow.getVetoerDetails(_vetoer);

        assertEq(vetoerState.unstETHIdsCount, 0);
        assertApproxEqAbs(vetoerState.stETHLockedShares.toUint256(), stethAmount, ACCURACY);
        assertEq(vetoerState.unstETHLockedShares.toUint256(), 0);
    }

    function test_claimNextWithdrawalsBatch_1_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
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

        _vetoerLockedStEth(_stETH.getPooledEthByShares(stethAmount));
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _withdrawalQueue.setLastCheckpointIndex(1);
        _withdrawalQueue.setCheckpointHints(new uint256[](unstEthIds.length + 10));

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);

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

        _vetoerLockedStEth(_stETH.getPooledEthByShares(stethAmount));
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);

        vm.expectRevert(Escrow.UnclaimedBatches.selector);
        _escrow.startRageQuitExtensionPeriod();
    }

    function test_startRageQuitExtensionPeriod_RevertOn_UnfinalizedUnstETHIds() external {
        uint256 ethAmount = _stETH.getPooledEthByShares(stethAmount);
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(ethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);
        _claimStEthViaWQ(unstEthIds, ethAmount);

        _withdrawalQueue.setLastFinalizedRequestId(0);

        vm.expectRevert(Escrow.UnfinalizedUnstETHIds.selector);
        _escrow.startRageQuitExtensionPeriod();
    }

    function test_startRageQuitExtensionPeriod_RevertOn_RepeatedCalls() external {
        _transitToRageQuit();

        _ensureWithdrawalsBatchesQueueClosed();

        assertEq(_escrow.getRageQuitEscrowDetails().rageQuitExtensionPeriodStartedAt, Timestamps.ZERO);

        _ensureRageQuitExtensionPeriodStartedNow();

        assertEq(_escrow.getRageQuitEscrowDetails().rageQuitExtensionPeriodStartedAt, Timestamps.now());

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.RageQuitExtensionPeriodAlreadyStarted.selector));
        _escrow.startRageQuitExtensionPeriod();
    }

    // ---
    // claimUnstETH()
    // ---

    function test_claimUnstETH_HappyPath() external {
        uint256[] memory unstEthAmounts = new uint256[](1);
        unstEthAmounts[0] = _stETH.getPooledEthByShares(1 ether);

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
        assertApproxEqAbs(
            state.unstETHLockedShares.toUint256(), _stETH.getSharesByPooledEth(unstEthAmounts[0]), ACCURACY
        );
    }

    function test_claimUnstETH_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
        _escrow.claimUnstETH(new uint256[](1), new uint256[](1));
    }

    function test_claimUnstETH_RevertOn_InvalidRequestId() external {
        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = _withdrawalQueue.REVERT_ON_ID();
        uint256[] memory hints = new uint256[](1);

        _transitToRageQuit();

        vm.expectRevert(WithdrawalQueueMock.InvalidRequestId.selector);
        _escrow.claimUnstETH(unstETHIds, hints);
    }

    function test_claimUnstETH_RevertOn_ArraysLengthMismatch() external {
        uint256[] memory unstETHIds = new uint256[](2);
        uint256[] memory hints = new uint256[](1);
        uint256[] memory responses = new uint256[](1);
        responses[0] = _stETH.getPooledEthByShares(1 ether);

        _transitToRageQuit();

        _withdrawalQueue.setClaimableEtherResult(responses);

        vm.expectRevert(WithdrawalQueueMock.ArraysLengthMismatch.selector);
        _escrow.claimUnstETH(unstETHIds, hints);
    }

    function test_claimUnstETH_RevertOn_InvalidUnstETHStatus() external {
        uint256[] memory unstEthAmounts = new uint256[](1);
        unstEthAmounts[0] = _stETH.getPooledEthByShares(1 ether);

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

    function test_setMinAssetsLockDuration_RevertOn_RageQuitState() external {
        Duration newMinAssetsLockDuration = Durations.from(1);

        _transitToRageQuit();

        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.RageQuitEscrow)
        );
        vm.prank(_dualGovernance);
        _escrow.setMinAssetsLockDuration(newMinAssetsLockDuration);
    }

    // ---
    // withdrawETH()
    // ---

    function test_withdrawETH_HappyPath() external {
        uint256 ethAmount = _stETH.getPooledEthByShares(stethAmount);
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(ethAmount);
        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);
        _claimStEthViaWQ(unstEthIds, ethAmount);
        _ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        _wait(Durations.from(1));

        vm.startPrank(_vetoer);
        vm.expectEmit();
        emit AssetsAccounting.ETHWithdrawn(
            _vetoer, SharesValues.from(_stETH.getSharesByPooledEth(ethAmount)), ETHValues.from(ethAmount)
        );
        _escrow.withdrawETH();
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore + ethAmount);

        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), _stETH.getSharesByPooledEth(ethAmount));
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), ethAmount);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares.toUint256(), 0);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
    }

    function test_withdrawETH_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
        _escrow.withdrawETH();
    }

    function test_withdrawETH_RevertOn_RageQuitExtensionPeriodNotStarted() external {
        _transitToRageQuit();

        vm.expectRevert(EscrowStateLib.RageQuitExtensionPeriodNotStarted.selector);
        _escrow.withdrawETH();
    }

    function test_withdrawETH_RevertOn_EthWithdrawalsDelayNotPassed() external {
        uint256 ethAmount = _stETH.getPooledEthByShares(stethAmount);
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(ethAmount);

        _transitToRageQuit(Durations.from(1), Durations.from(2));
        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);
        _claimStEthViaWQ(unstEthIds, ethAmount);
        _ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);

        vm.startPrank(_vetoer);
        vm.expectRevert(EscrowStateLib.EthWithdrawalsDelayNotPassed.selector);
        _escrow.withdrawETH();
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore);
    }

    function test_withdrawETH_RevertOn_InvalidSharesValue() external {
        uint256 ethAmount1 = _stETH.getPooledEthByShares(stethAmount);
        uint256 sharesAmount2 = 100 ether;
        uint256 ethAmount2 = _stETH.getPooledEthByShares(sharesAmount2);
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        address _vetoer2 = makeAddr("vetoer2");
        _stETH.mint(_vetoer2, ethAmount2);

        vm.startPrank(_vetoer2);
        _stETH.approve(address(_escrow), type(uint256).max);
        _escrow.lockStETH(ethAmount2);
        vm.stopPrank();

        _vetoerLockedStEth(ethAmount1);

        _wait(_minLockAssetDuration.plusSeconds(1));

        _vetoerUnlockedStEth(ethAmount1);

        _transitToRageQuit();

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);

        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);
        _claimStEthViaWQ(unstEthIds, ethAmount1);
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
        unstEthAmounts[0] = _stETH.getPooledEthByShares(1 ether);
        unstEthAmounts[1] = _stETH.getPooledEthByShares(10 ether);

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
        assertApproxEqAbs(
            state.unstETHLockedShares.toUint256(),
            _stETH.getSharesByPooledEth(unstEthAmounts[0] + unstEthAmounts[1]),
            ACCURACY
        );
    }

    function test_withdrawETH_2_HappyPath_HolderPerspective() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = _stETH.getPooledEthByShares(1 ether);
        unstEthAmounts[1] = _stETH.getPooledEthByShares(10 ether);
        uint256 totalSharesToBeWithdrawn = _stETH.getSharesByPooledEth(unstEthAmounts[0] + unstEthAmounts[1]);

        uint256[] memory unstEthIds = _vetoerLockedUnstEth(unstEthAmounts);
        uint256[] memory hints = _finalizeUnstEth(unstEthAmounts, unstEthIds);

        _transitToRageQuit();
        _ensureWithdrawalsBatchesQueueClosed();
        _ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);
        _wait(Durations.from(1));

        _claimUnstEthFromEscrow(unstEthAmounts, unstEthIds, hints);

        IEscrow.VetoerDetails memory vetoerState = _escrow.getVetoerDetails(_vetoer);

        assertApproxEqAbs(totalSharesToBeWithdrawn, vetoerState.unstETHLockedShares.toUint256(), ACCURACY);
        assertEq(unstEthAmounts.length, vetoerState.unstETHIdsCount);

        uint256[] memory firstWithdrawalUnstEthIds = new uint256[](1);
        firstWithdrawalUnstEthIds[0] = unstEthIds[0];

        vm.startPrank(_vetoer);
        _escrow.withdrawETH(firstWithdrawalUnstEthIds);
        vm.stopPrank();

        IEscrow.VetoerDetails memory vetoerStateAfterFirstWithdrawal = _escrow.getVetoerDetails(_vetoer);

        // Based on current design it is expected that after the first withdrawal these data was not updated
        assertApproxEqAbs(
            totalSharesToBeWithdrawn, vetoerStateAfterFirstWithdrawal.unstETHLockedShares.toUint256(), ACCURACY
        );
        assertEq(unstEthAmounts.length, vetoerStateAfterFirstWithdrawal.unstETHIdsCount);
        // But request is successful and funds are transferred
        assertEq(balanceBefore + unstEthAmounts[0], _vetoer.balance);

        uint256[] memory vetoerUnstETHIds = _escrow.getVetoerUnstETHIds(_vetoer);
        IEscrow.LockedUnstETHDetails[] memory lockedUnstETHDetails = _escrow.getLockedUnstETHDetails(vetoerUnstETHIds);

        uint256 unclaimedUnstETHRecordsCount = 0;
        for (uint256 i = 0; i < lockedUnstETHDetails.length; i++) {
            if (lockedUnstETHDetails[i].status == UnstETHRecordStatus.Claimed) {
                unclaimedUnstETHRecordsCount++;
            }
        }
        uint256[] memory secondWithdrawalUnstEthIds = new uint256[](unclaimedUnstETHRecordsCount);
        unclaimedUnstETHRecordsCount = 0;
        for (uint256 i = 0; i < lockedUnstETHDetails.length; i++) {
            if (lockedUnstETHDetails[i].status == UnstETHRecordStatus.Claimed) {
                secondWithdrawalUnstEthIds[unclaimedUnstETHRecordsCount] = vetoerUnstETHIds[i];
                unclaimedUnstETHRecordsCount++;
            }
        }

        vm.startPrank(_vetoer);
        _escrow.withdrawETH(secondWithdrawalUnstEthIds);
        vm.stopPrank();

        assertEq(balanceBefore + unstEthAmounts[0] + unstEthAmounts[1], _vetoer.balance);
    }

    function test_withdrawETH_2_RevertOn_EmptyUnstETHIds() external {
        vm.expectRevert(Escrow.EmptyUnstETHIds.selector);
        _escrow.withdrawETH(new uint256[](0));
    }

    function test_withdrawETH_2_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
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
        unstEthAmounts[0] = _stETH.getPooledEthByShares(1 ether);
        unstEthAmounts[1] = _stETH.getPooledEthByShares(10 ether);

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
        unstEthAmounts[0] = _stETH.getPooledEthByShares(1 ether);
        unstEthAmounts[1] = _stETH.getPooledEthByShares(10 ether);

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
    // getSignallingEscrowDetails()
    // ---

    function test_getSignallingEscrowDetails() external view {
        IEscrow.SignallingEscrowDetails memory signallingEscrowDetails = _escrow.getSignallingEscrowDetails();

        assertEq(signallingEscrowDetails.totalStETHLockedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalStETHClaimedETH.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256(), 0);
        assertEq(signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);
    }

    // ---
    // getVetoerDetails()
    // ---

    function test_getVetoerDetails() external {
        _vetoerLockedStEth(_stETH.getPooledEthByShares(stethAmount));

        IEscrow.VetoerDetails memory state = _escrow.getVetoerDetails(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertApproxEqAbs(state.stETHLockedShares.toUint256(), stethAmount, ACCURACY);
        assertEq(state.unstETHLockedShares.toUint256(), 0);
        assertEq(state.lastAssetsLockTimestamp, Timestamps.now());
    }

    // ---
    // getVetoerUnstETHIds()
    // ---

    function test_getVetoerUnstETHIds() external {
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = _stETH.getPooledEthByShares(1 ether);
        unstEthAmounts[1] = _stETH.getPooledEthByShares(10 ether);

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
    // getLockedUnstETHDetails()
    // ---

    function test_getLockedUnstETHDetails_HappyPath() external {
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = _stETH.getPooledEthByShares(1 ether);
        unstEthAmounts[1] = _stETH.getPooledEthByShares(10 ether);

        assertEq(_escrow.getVetoerUnstETHIds(_vetoer).length, 0);

        uint256[] memory unstEthIds = _vetoerLockedUnstEth(unstEthAmounts);

        IEscrow.LockedUnstETHDetails[] memory unstETHDetails = _escrow.getLockedUnstETHDetails(unstEthIds);

        assertEq(unstETHDetails.length, unstEthIds.length);

        assertEq(unstETHDetails[0].id, unstEthIds[0]);
        assertEq(unstETHDetails[0].lockedBy, _vetoer);
        assertTrue(unstETHDetails[0].status == UnstETHRecordStatus.Locked);
        assertEq(unstETHDetails[0].shares.toUint256(), _stETH.getSharesByPooledEth(unstEthAmounts[0]));
        assertEq(unstETHDetails[0].claimableAmount.toUint256(), 0);

        assertEq(unstETHDetails[1].id, unstEthIds[1]);
        assertEq(unstETHDetails[1].lockedBy, _vetoer);
        assertTrue(unstETHDetails[1].status == UnstETHRecordStatus.Locked);
        assertEq(unstETHDetails[1].shares.toUint256(), _stETH.getSharesByPooledEth(unstEthAmounts[1]));
        assertEq(unstETHDetails[1].claimableAmount.toUint256(), 0);
    }

    function test_getLockedUnstETHDetails_RevertOn_unstETHNotLocked() external {
        uint256 notLockedUnstETHId = 42;

        uint256[] memory notLockedUnstETHIds = new uint256[](1);
        notLockedUnstETHIds[0] = notLockedUnstETHId;

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector, notLockedUnstETHId, UnstETHRecordStatus.NotLocked
            )
        );
        _escrow.getLockedUnstETHDetails(notLockedUnstETHIds);
    }

    // ---
    // getNextWithdrawalBatch()
    // ---

    function test_getNextWithdrawalBatch() external {
        uint256 ethAmount = _stETH.getPooledEthByShares(stethAmount);
        uint256[] memory unstEthIds = _getUnstEthIdsFromWQ();

        _vetoerLockedStEth(ethAmount);

        _transitToRageQuit();

        uint256[] memory claimableUnstEthIds = _escrow.getNextWithdrawalBatch(100);
        assertEq(claimableUnstEthIds.length, 0);

        _withdrawalQueue.setRequestWithdrawalsResult(unstEthIds);
        _withdrawalQueue.setLastCheckpointIndex(1);
        _withdrawalQueue.setCheckpointHints(new uint256[](unstEthIds.length));
        _ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds);

        claimableUnstEthIds = _escrow.getNextWithdrawalBatch(100);
        assertEq(claimableUnstEthIds.length, unstEthIds.length);
        assertEq(claimableUnstEthIds[0], unstEthIds[0]);

        _withdrawalQueue.setClaimableAmount(ethAmount);
        vm.deal(address(_withdrawalQueue), ethAmount);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstEthIds);
        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(ETHValues.from(ethAmount));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0], new uint256[](unstEthIds.length));

        claimableUnstEthIds = _escrow.getNextWithdrawalBatch(100);
        assertEq(claimableUnstEthIds.length, 0);
    }

    function test_getNextWithdrawalBatch_RevertOn_RageQuit_IsNotStarted() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
        _escrow.getNextWithdrawalBatch(100);
    }

    function test_getNextWithdrawalBatch_RevertOn_UnexpectedEscrowState_Signaling() external {
        uint256 batchLimit = 10;
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
        _escrow.getNextWithdrawalBatch(batchLimit);
    }

    function test_getNextWithdrawalBatch_RevertOn_UnexpectedEscrowState_NotInitialized() external {
        uint256 batchLimit = 10;
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.NotInitialized)
        );
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

    function test_isWithdrawalsBatchesClosed_RevertOn_UnexpectedEscrowState_Signaling() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
        _escrow.isWithdrawalsBatchesClosed();
    }

    function test_isWithdrawalsBatchesClosed_RevertOn_UnexpectedEscrowState_NotInitialized() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.NotInitialized)
        );
        _masterCopy.isWithdrawalsBatchesClosed();
    }

    // ---
    // getUnclaimedUnstETHIdsCount()
    // ---

    function test_getUnclaimedUnstETHIdsCount_RevertOn_UnexpectedEscrowState_Signaling() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
        _escrow.getUnclaimedUnstETHIdsCount();
    }

    function test_getUnclaimedUnstETHIdsCount_RevertOn_UnexpectedEscrowState_NotInitialized() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.NotInitialized)
        );
        _masterCopy.getUnclaimedUnstETHIdsCount();
    }

    // ---
    // getRageQuitSupport()
    // ---

    function test_getRageQuitSupport() external {
        uint256 stEthLockedShares = 80 ether;
        uint256 stEthLockedAmount = _stETH.getPooledEthByShares(stEthLockedShares);
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = _stETH.getPooledEthByShares(1 ether);
        unstEthAmounts[1] = _stETH.getPooledEthByShares(10 ether);
        uint256[] memory finalizedUnstEthAmounts = new uint256[](1);
        uint256[] memory finalizedUnstEthIds = new uint256[](1);

        PercentD16 actualSupport =
            PercentsD16.fromFraction({numerator: stEthLockedAmount, denominator: _stETH.totalSupply()});

        _vetoerLockedStEth(stEthLockedAmount);

        PercentD16 support = _escrow.getRageQuitSupport();
        assertApproxEqAbs(support.toUint256(), actualSupport.toUint256(), ACCURACY);
        assertApproxEqAbs(support.toUint256(), PercentsD16.fromBasisPoints(80_00).toUint256(), ACCURACY);

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
        assertApproxEqAbs(support.toUint256(), actualSupport.toUint256(), ACCURACY);
        assertApproxEqAbs(support.toUint256(), PercentsD16.fromBasisPoints(91_00).toUint256(), ACCURACY);
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

    function test_getRageQuitEscrowDetails_HappyPath() external {
        _transitToRageQuit();

        IRageQuitEscrow.RageQuitEscrowDetails memory details = _escrow.getRageQuitEscrowDetails();
        assertFalse(details.isRageQuitExtensionPeriodStarted);
        assertEq(details.rageQuitExtensionPeriodStartedAt, Timestamps.ZERO);
        assertEq(details.rageQuitEthWithdrawalsDelay, Durations.ZERO);
        assertEq(details.rageQuitExtensionPeriodDuration, Durations.ZERO);

        _ensureWithdrawalsBatchesQueueClosed();

        _ensureRageQuitExtensionPeriodStartedNow();

        details = _escrow.getRageQuitEscrowDetails();
        assertTrue(details.isRageQuitExtensionPeriodStarted);
        assertEq(details.rageQuitExtensionPeriodStartedAt, Timestamps.now());
        assertEq(details.rageQuitEthWithdrawalsDelay, Durations.ZERO);
        assertEq(details.rageQuitExtensionPeriodDuration, Durations.ZERO);
    }

    function test_getRageQuitEscrowDetails_RevertOn_UnexpectedEscrowState_Signaling() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.SignallingEscrow)
        );
        _escrow.getRageQuitEscrowDetails();
    }

    function test_getRageQuitEscrowDetails_RevertOn_UnexpectedEscrowState_NotInitialized() external {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowStateLib.UnexpectedEscrowState.selector, EscrowState.NotInitialized)
        );
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

    function test_MIN_TRANSFERRABLE_ST_ETH_AMOUNT() external view {
        assertEq(_escrow.MIN_TRANSFERRABLE_ST_ETH_AMOUNT(), 100);
    }

    function test_MIN_TRANSFERRABLE_ST_ETH_AMOUNT_gt_minWithdrawableStETHAmountWei_HappyPath() external {
        _stETH.setTotalPooledEther(stethInitialEthAmount);
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
        _stETH.setTotalPooledEther(stethInitialEthAmount);
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
        _stETH.setTotalPooledEther(stethInitialEthAmount);
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
        _stETH.setTotalPooledEther(stethInitialEthAmount);
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

    function _createEscrow(uint256 size, Duration maxMinAssetsLockDuration) internal returns (Escrow) {
        return new Escrow(
            _stETH, _wstETH, _withdrawalQueue, IDualGovernance(_dualGovernance), size, maxMinAssetsLockDuration
        );
    }

    function _createEscrowProxy(uint256 minWithdrawalsBatchSize) internal returns (Escrow) {
        Escrow masterCopy = _createEscrow(minWithdrawalsBatchSize, _maxMinAssetsLockDuration);
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

    function _vetoerLockedStEth(uint256 ethAmount) internal {
        vm.prank(_vetoer);
        _escrow.lockStETH(ethAmount);
    }

    function _vetoerLockedUnstEth(uint256[] memory ethAmounts) internal returns (uint256[] memory unstethIds) {
        unstethIds = new uint256[](ethAmounts.length);
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](ethAmounts.length);

        for (uint256 i = 0; i < ethAmounts.length; ++i) {
            unstethIds[i] = i;
            statuses[i] = IWithdrawalQueue.WithdrawalRequestStatus(
                ethAmounts[i], _stETH.getSharesByPooledEth(ethAmounts[i]), _vetoer, block.timestamp, false, false
            );
        }

        _withdrawalQueue.setWithdrawalRequestsStatuses(statuses);

        vm.prank(_vetoer);
        _escrow.lockUnstETH(unstethIds);
    }

    function _finalizeUnstEth(
        uint256[] memory ethAmounts,
        uint256[] memory finalizedUnstEthIds
    ) internal returns (uint256[] memory hints) {
        assertEq(ethAmounts.length, finalizedUnstEthIds.length);

        hints = new uint256[](ethAmounts.length);
        uint256[] memory responses = new uint256[](ethAmounts.length);

        for (uint256 i = 0; i < ethAmounts.length; ++i) {
            hints[i] = i;
            responses[i] = ethAmounts[i];
        }

        _withdrawalQueue.setClaimableEtherResult(responses);

        _escrow.markUnstETHFinalized(finalizedUnstEthIds, hints);

        for (uint256 i = 0; i < ethAmounts.length; ++i) {
            _stETH.burn(_vetoer, ethAmounts[i]);
        }
    }

    function _claimUnstEthFromEscrow(
        uint256[] memory ethAmounts,
        uint256[] memory unstEthIds,
        uint256[] memory hints
    ) internal returns (uint256 sum) {
        assertEq(ethAmounts.length, unstEthIds.length);
        assertEq(ethAmounts.length, hints.length);

        sum = 0;
        for (uint256 i = 0; i < ethAmounts.length; ++i) {
            sum += ethAmounts[i];
        }

        _withdrawalQueue.setClaimableAmount(sum);
        _withdrawalQueue.setClaimableEtherResult(ethAmounts);
        vm.deal(address(_withdrawalQueue), sum);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHClaimed(unstEthIds, ETHValues.from(sum));
        _escrow.claimUnstETH(unstEthIds, hints);
    }

    function _claimStEthViaWQ(uint256[] memory unstEthIds, uint256 ethAmount) internal {
        _withdrawalQueue.setClaimableAmount(ethAmount);
        _withdrawalQueue.setLastCheckpointIndex(1);
        _withdrawalQueue.setCheckpointHints(new uint256[](unstEthIds.length));
        vm.deal(address(_withdrawalQueue), ethAmount);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstEthIds);
        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(ETHValues.from(ethAmount));
        _escrow.claimNextWithdrawalsBatch(unstEthIds.length);
    }

    function _vetoerUnlockedStEth(uint256 ethAmount) internal {
        vm.startPrank(_vetoer);
        vm.expectEmit();
        emit AssetsAccounting.StETHSharesUnlocked(_vetoer, SharesValues.from(_stETH.getSharesByPooledEth(ethAmount)));
        _escrow.unlockStETH();
        vm.stopPrank();
    }

    function _ensureUnstEthAddedToWithdrawalsBatchesQueue(uint256[] memory unstEthIds) internal {
        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(unstEthIds);
        _escrow.requestNextWithdrawalsBatch(100);

        assertApproxEqAbs(_stETH.balanceOf(address(_escrow)), 0, ACCURACY);
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

    function _percentD16ToString(PercentD16 number) internal view returns (string memory) {
        uint256 intPart = number.toUint256() / ONE_PERCENT_D16;
        uint256 fractionalPart = number.toUint256() - intPart * ONE_PERCENT_D16;

        string memory fractionalChars;
        for (uint256 i = 0; i < 16; ++i) {
            uint256 divider = 10 ** (15 - i);
            uint256 char = fractionalPart / divider;
            fractionalChars = string.concat(fractionalChars, vm.toString(char));
            fractionalPart -= char * divider;
        }

        return string.concat(vm.toString(intPart), ".", fractionalChars);
    }
}
