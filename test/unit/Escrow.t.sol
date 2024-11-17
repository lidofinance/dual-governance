// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdError} from "forge-std/StdError.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {ETHValues, sendTo} from "contracts/types/ETHValue.sol";
import {SharesValues} from "contracts/types/SharesValue.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

import {Escrow, LockedAssetsTotals, VetoerState} from "contracts/Escrow.sol";

import {EscrowState as EscrowStateLib, State as EscrowState} from "contracts/libraries/EscrowState.sol";
import {WithdrawalsBatchesQueue} from "contracts/libraries/WithdrawalBatchesQueue.sol";
import {AssetsAccounting, UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";

import {IEscrow} from "contracts/interfaces/IEscrow.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {WithdrawalRequestStatus} from "contracts/interfaces/IWithdrawalQueue.sol";

import {StETHMock} from "test/mocks/StETHMock.sol";
import {WstETHMock} from "test/mocks/WstETHMock.sol";
import {WithdrawalQueueMock} from "test/mocks/WithdrawalQueueMock.sol";
import {UnitTest} from "test/utils/unit-test.sol";
import {Random} from "test/utils/random.sol";

contract EscrowUnitTests is UnitTest {
    Random.Context private _random;
    address private _dualGovernance = makeAddr("dualGovernance");
    address private _vetoer = makeAddr("vetoer");

    Escrow private _escrow;

    StETHMock private _stETH;
    WstETHMock private _wstETH;

    address private _withdrawalQueue;

    Duration private _minLockAssetDuration = Durations.from(1 days);
    uint256 private stethAmount = 100 ether;

    function setUp() external {
        _random = Random.create(block.timestamp);

        _stETH = new StETHMock();
        _stETH.__setShareRate(1);
        _wstETH = new WstETHMock();
        _withdrawalQueue = address(new WithdrawalQueueMock(address(_stETH)));
        _escrow = createInitializedEscrowProxy(100, _minLockAssetDuration);

        vm.startPrank(_vetoer);
        ERC20Mock(address(_stETH)).approve(address(_escrow), type(uint256).max);
        ERC20Mock(address(_wstETH)).approve(address(_escrow), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(_escrow));
        ERC20Mock(address(_stETH)).approve(_withdrawalQueue, type(uint256).max);
        vm.stopPrank();

        ERC20Mock(address(_stETH)).mint(_vetoer, stethAmount);
        ERC20Mock(address(_wstETH)).mint(_vetoer, stethAmount);

        vm.mockCall(
            _dualGovernance, abi.encodeWithSelector(IDualGovernance.activateNextState.selector), abi.encode(true)
        );

        WithdrawalQueueMock(_withdrawalQueue).setMinStETHWithdrawalAmount(0);
        WithdrawalQueueMock(_withdrawalQueue).setMaxStETHWithdrawalAmount(20);
    }

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

        vm.expectCall(
            address(_stETH), abi.encodeWithSelector(IERC20.approve.selector, address(_wstETH), type(uint256).max)
        );
        vm.expectCall(
            address(_stETH), abi.encodeWithSelector(IERC20.approve.selector, _withdrawalQueue, type(uint256).max)
        );

        createInitializedEscrowProxy(100, Durations.ZERO);
    }

    function test_initialize_RevertOn_CalledNotViaProxy() external {
        Escrow instance = createEscrow(100);

        vm.expectRevert(Escrow.NonProxyCallsForbidden.selector);
        instance.initialize(Durations.ZERO);
    }

    function testFuzz_initialize_RevertOn_CalledNotFromDualGovernance(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        IEscrow instance = createEscrowProxy(100);

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
        uint256 vetoerBalanceBefore = ERC20Mock(address(_stETH)).balanceOf(_vetoer);
        uint256 escrowBalanceBefore = ERC20Mock(address(_stETH)).balanceOf(address(_escrow));

        vm.expectCall(
            address(_stETH),
            abi.encodeWithSelector(
                StETHMock.transferSharesFrom.selector, address(_vetoer), address(_escrow), sharesAmount
            )
        );
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));

        vm.prank(_vetoer);
        _escrow.lockStETH(amount);

        uint256 vetoerBalanceAfter = ERC20Mock(address(_stETH)).balanceOf(_vetoer);
        uint256 escrowBalanceAfter = ERC20Mock(address(_stETH)).balanceOf(address(_escrow));

        assertEq(vetoerBalanceAfter, vetoerBalanceBefore - amount);
        assertEq(escrowBalanceAfter, escrowBalanceBefore + amount);
    }

    function test_lockStETH_RevertOn_UnexpectedEscrowState() external {
        transitToRageQuit();

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        vm.prank(_vetoer);
        _escrow.lockStETH(1 ether);
    }

    // ---
    // unlockStETH()
    // ---

    function test_unlockStETH_HappyPath() external {
        uint256 amount = 1 ether;
        uint256 sharesAmount = _stETH.getSharesByPooledEth(amount);

        vm.startPrank(_vetoer);
        _escrow.lockStETH(amount);

        uint256 vetoerBalanceBefore = ERC20Mock(address(_stETH)).balanceOf(_vetoer);
        uint256 escrowBalanceBefore = ERC20Mock(address(_stETH)).balanceOf(address(_escrow));

        _wait(_minLockAssetDuration.plusSeconds(1));

        vm.expectCall(
            address(_stETH), abi.encodeWithSelector(IStETH.transferShares.selector, address(_vetoer), sharesAmount)
        );
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));
        _escrow.unlockStETH();

        uint256 vetoerBalanceAfter = ERC20Mock(address(_stETH)).balanceOf(_vetoer);
        uint256 escrowBalanceAfter = ERC20Mock(address(_stETH)).balanceOf(address(_escrow));

        assertEq(vetoerBalanceAfter, vetoerBalanceBefore + amount);
        assertEq(escrowBalanceAfter, escrowBalanceBefore - amount);
    }

    function test_unlockStETH_RevertOn_UnexpectedEscrowState() external {
        vm.prank(_vetoer);
        _escrow.lockStETH(1 ether);

        transitToRageQuit();

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

        uint256 vetoerBalanceBefore = ERC20Mock(address(_wstETH)).balanceOf(_vetoer);
        uint256 escrowBalanceBefore = ERC20Mock(address(_wstETH)).balanceOf(address(_escrow));

        vm.expectCall(
            address(_wstETH), abi.encodeWithSelector(IERC20.transferFrom.selector, _vetoer, address(_escrow), amount)
        );
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));

        vm.mockCall(address(_wstETH), abi.encodeWithSelector(IWstETH.unwrap.selector), abi.encode(amount));

        vm.prank(_vetoer);
        _escrow.lockWstETH(amount);

        uint256 vetoerBalanceAfter = ERC20Mock(address(_wstETH)).balanceOf(_vetoer);
        uint256 escrowBalanceAfter = ERC20Mock(address(_wstETH)).balanceOf(address(_escrow));

        assertEq(vetoerBalanceAfter, vetoerBalanceBefore - amount);
        assertEq(escrowBalanceAfter, escrowBalanceBefore + amount);
    }

    function test_lockWstETH_RevertOn_UnexpectedEscrowState() external {
        transitToRageQuit();

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        vm.prank(_vetoer);
        _escrow.lockWstETH(1 ether);
    }

    // ---
    // unlockWstETH()
    // ---

    function test_unlockWstETH_HappyPath() external {
        uint256 amount = 1 ether;

        vm.mockCall(address(_wstETH), abi.encodeWithSelector(IWstETH.wrap.selector), abi.encode(amount));
        vm.mockCall(address(_wstETH), abi.encodeWithSelector(IWstETH.unwrap.selector), abi.encode(amount));

        vm.startPrank(_vetoer);
        _escrow.lockWstETH(amount);

        _wait(_minLockAssetDuration.plusSeconds(1));

        uint256 vetoerBalanceBefore = ERC20Mock(address(_wstETH)).balanceOf(_vetoer);
        uint256 escrowBalanceBefore = ERC20Mock(address(_wstETH)).balanceOf(address(_escrow));

        vm.expectCall(address(_wstETH), abi.encodeWithSelector(IWstETH.wrap.selector, amount));
        vm.expectCall(address(_wstETH), abi.encodeWithSelector(IERC20.transfer.selector, _vetoer, amount));
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));
        _escrow.unlockWstETH();

        uint256 vetoerBalanceAfter = ERC20Mock(address(_wstETH)).balanceOf(_vetoer);
        uint256 escrowBalanceAfter = ERC20Mock(address(_wstETH)).balanceOf(address(_escrow));

        assertEq(vetoerBalanceAfter, vetoerBalanceBefore + amount);
        assertEq(escrowBalanceAfter, escrowBalanceBefore - amount);
    }

    function test_unlockWstETH_RevertOn_UnexpectedEscrowState() external {
        uint256 amount = 1 ether;
        vm.mockCall(address(_wstETH), abi.encodeWithSelector(IWstETH.unwrap.selector), abi.encode(amount));

        vm.prank(_vetoer);
        _escrow.lockWstETH(amount);

        transitToRageQuit();

        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        vm.prank(_vetoer);
        _escrow.unlockWstETH();
    }

    function test_unlockWstETH_RevertOn_MinAssetsLockDurationNotPassed() external {
        uint256 amount = 1 ether;
        vm.mockCall(address(_wstETH), abi.encodeWithSelector(IWstETH.unwrap.selector), abi.encode(amount));

        vm.startPrank(_vetoer);
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

        WithdrawalRequestStatus[] memory statuses = new WithdrawalRequestStatus[](2);
        statuses[0] = WithdrawalRequestStatus(1 ether, 1 ether, _vetoer, block.timestamp, false, false);
        statuses[1] = WithdrawalRequestStatus(2 ether, 2 ether, _vetoer, block.timestamp, false, false);

        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getWithdrawalStatus.selector, unstethIds),
            abi.encode(statuses)
        );
        vm.mockCall(_withdrawalQueue, abi.encodeWithSelector(IWithdrawalQueue.transferFrom.selector), abi.encode(true));

        vm.expectCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.transferFrom.selector, _vetoer, address(_escrow), unstethIds[0])
        );
        vm.expectCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.transferFrom.selector, _vetoer, address(_escrow), unstethIds[1])
        );
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));

        vm.prank(_vetoer);
        _escrow.lockUnstETH(unstethIds);
    }

    function test_lockUnstETH_RevertOn_EmptyUnstETHIds() external {
        uint256[] memory unstethIds = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(Escrow.EmptyUnstETHIds.selector));
        _escrow.lockUnstETH(unstethIds);
    }

    function test_lockUnstETH_RevertOn_UnexpectedEscrowState() external {
        uint256[] memory unstethIds = new uint256[](1);
        unstethIds[0] = 1;

        transitToRageQuit();

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

        uint256[] memory unstethIds = vetoerLockedUnstEth(unstETHAmounts);

        _wait(_minLockAssetDuration.plusSeconds(1));

        vm.expectCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.transferFrom.selector, address(_escrow), _vetoer, unstethIds[0])
        );
        vm.expectCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.transferFrom.selector, address(_escrow), _vetoer, unstethIds[1])
        );
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));

        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstethIds);
    }

    function test_unlockUnstETH_RevertOn_EmptyUnstETHIds() external {
        uint256[] memory unstethIds = new uint256[](0);

        _wait(_minLockAssetDuration.plusSeconds(1));

        vm.expectRevert(abi.encodeWithSelector(Escrow.EmptyUnstETHIds.selector));
        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstethIds);
    }

    function test_unlockUnstETH_RevertOn_UnexpectedEscrowState() external {
        uint256[] memory unstETHAmounts = new uint256[](1);
        unstETHAmounts[0] = 1 ether;
        uint256[] memory unstethIds = vetoerLockedUnstEth(unstETHAmounts);

        transitToRageQuit();

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

        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getClaimableEther.selector, unstethIds, hints),
            abi.encode(responses)
        );
        vm.expectCall(
            _withdrawalQueue, abi.encodeWithSelector(IWithdrawalQueue.getClaimableEther.selector, unstethIds, hints)
        );

        _escrow.markUnstETHFinalized(unstethIds, hints);
    }

    function test_markUnstETHFinalized_RevertOn_UnexpectedEscrowState() external {
        transitToRageQuit();

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
        WithdrawalQueueMock(_withdrawalQueue).setLastRequestId(lri);

        vm.expectEmit();
        emit EscrowStateLib.RageQuitStarted(Durations.ZERO, Durations.ZERO);
        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueOpened(lri);

        transitToRageQuit();
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
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueOpened(unstEthIds[0] - 1);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        _stETH.mint(address(_escrow), stethAmount);
        WithdrawalQueueMock(_withdrawalQueue).setMinStETHWithdrawalAmount(1);
        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsTransferAmount(stethAmount);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(unstEthIds);
        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueClosed();
        _escrow.requestNextWithdrawalsBatch(100);
    }

    function test_requestNextWithdrawalsBatch_ReturnsEarlyAndClosesWithdrawalsBatchesQueue_When_EscrowHasZeroAmountOfStETH(
    ) external {
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(new uint256[](0));

        ensureWithdrawalsBatchesQueueClosed();
    }

    function test_requestNextWithdrawalsBatch_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.requestNextWithdrawalsBatch(1);
    }

    function test_requestNextWithdrawalsBatch_RevertOn_InvalidBatchSize() external {
        transitToRageQuit();

        uint256 batchSize = 1;

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidBatchSize.selector, batchSize));
        _escrow.requestNextWithdrawalsBatch(batchSize);
    }

    function test_requestNextWithdrawalsBatch_RevertOn_InvalidUnstETHIdsSequence() external {
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueOpened(unstEthIds[0] - 1);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        _stETH.mint(address(_escrow), stethAmount);

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
        LockedAssetsTotals memory escrowLockedAssets = _escrow.getLockedAssetsTotals();

        assertEq(escrowLockedAssets.stETHLockedShares, 0);
        assertEq(escrowLockedAssets.stETHClaimedETH, 0);
        assertEq(escrowLockedAssets.unstETHUnfinalizedShares, 0);
        assertEq(escrowLockedAssets.unstETHFinalizedETH, 0);

        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        WithdrawalQueueMock(_withdrawalQueue).setClaimableAmount(stethAmount);
        vm.deal(_withdrawalQueue, stethAmount);

        vm.mockCall(
            _withdrawalQueue, abi.encodeWithSelector(IWithdrawalQueue.getLastCheckpointIndex.selector), abi.encode(1)
        );
        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.findCheckpointHints.selector),
            abi.encode(new uint256[](unstEthIds.length))
        );

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstEthIds);
        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(ETHValues.from(stethAmount));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0], new uint256[](unstEthIds.length));

        escrowLockedAssets = _escrow.getLockedAssetsTotals();

        assertEq(escrowLockedAssets.stETHLockedShares, stethAmount);
        assertEq(escrowLockedAssets.stETHClaimedETH, stethAmount);
        assertEq(escrowLockedAssets.unstETHUnfinalizedShares, 0);
        assertEq(escrowLockedAssets.unstETHFinalizedETH, 0);
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_UnexpectedState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, 2));
        _escrow.claimNextWithdrawalsBatch(1, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_ClaimingIsFinished() external {
        transitToRageQuit();

        _escrow.requestNextWithdrawalsBatch(100);
        _escrow.startRageQuitExtensionPeriod();

        vm.expectRevert(EscrowStateLib.ClaimingIsFinished.selector);
        _escrow.claimNextWithdrawalsBatch(1, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_EmptyBatch() external {
        transitToRageQuit();

        vm.expectRevert(WithdrawalsBatchesQueue.EmptyBatch.selector);
        _escrow.claimNextWithdrawalsBatch(1, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_UnexpectedUnstETHId() external {
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        WithdrawalQueueMock(_withdrawalQueue).setClaimableAmount(stethAmount);
        vm.deal(_withdrawalQueue, stethAmount);

        vm.expectRevert(Escrow.UnexpectedUnstETHId.selector);
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0] + 10, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_InvalidHintsLength() external {
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        WithdrawalQueueMock(_withdrawalQueue).setClaimableAmount(stethAmount);
        vm.deal(_withdrawalQueue, stethAmount);

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidHintsLength.selector, 10, 1));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0], new uint256[](10));
    }

    // ---
    // claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount)
    // ---

    function test_claimNextWithdrawalsBatch_1_HappyPath() external {
        LockedAssetsTotals memory escrowLockedAssets = _escrow.getLockedAssetsTotals();

        assertEq(escrowLockedAssets.stETHLockedShares, 0);
        assertEq(escrowLockedAssets.stETHClaimedETH, 0);
        assertEq(escrowLockedAssets.unstETHUnfinalizedShares, 0);
        assertEq(escrowLockedAssets.unstETHFinalizedETH, 0);

        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        ensureWithdrawalsBatchesQueueClosed();
        claimStEthViaWQ(unstEthIds, stethAmount);

        escrowLockedAssets = _escrow.getLockedAssetsTotals();

        assertEq(escrowLockedAssets.stETHLockedShares, stethAmount);
        assertEq(escrowLockedAssets.stETHClaimedETH, stethAmount);
        assertEq(escrowLockedAssets.unstETHUnfinalizedShares, 0);
        assertEq(escrowLockedAssets.unstETHFinalizedETH, 0);
    }

    function test_claimNextWithdrawalsBatch_1_RevertOn_UnexpectedState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, 2));
        _escrow.claimNextWithdrawalsBatch(1);
    }

    function test_claimNextWithdrawalsBatch_1_RevertOn_ClaimingIsFinished() external {
        transitToRageQuit();

        _escrow.requestNextWithdrawalsBatch(100);
        _escrow.startRageQuitExtensionPeriod();

        vm.expectRevert(EscrowStateLib.ClaimingIsFinished.selector);
        _escrow.claimNextWithdrawalsBatch(1);
    }

    function test_claimNextWithdrawalsBatch_1_RevertOn_EmptyBatch() external {
        transitToRageQuit();

        vm.expectRevert(WithdrawalsBatchesQueue.EmptyBatch.selector);
        _escrow.claimNextWithdrawalsBatch(1);
    }

    function test_claimNextWithdrawalsBatch_1_RevertOn_InvalidHintsLength() external {
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        vm.mockCall(
            _withdrawalQueue, abi.encodeWithSelector(IWithdrawalQueue.getLastCheckpointIndex.selector), abi.encode(1)
        );
        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.findCheckpointHints.selector, unstEthIds, 1, 1),
            abi.encode(new uint256[](unstEthIds.length + 10))
        );

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidHintsLength.selector, 11, 1));
        _escrow.claimNextWithdrawalsBatch(unstEthIds.length);
    }

    // ---
    // startRageQuitExtensionPeriod()
    // ---

    function test_startRageQuitExtensionPeriod_HappyPath() external {
        transitToRageQuit();

        ensureWithdrawalsBatchesQueueClosed();

        ensureRageQuitExtensionPeriodStartedNow();
    }

    function test_startRageQuitExtensionPeriod_RevertOn_BatchesQueueIsNotClosed() external {
        vm.expectRevert(Escrow.BatchesQueueIsNotClosed.selector);
        _escrow.startRageQuitExtensionPeriod();
    }

    function test_startRageQuitExtensionPeriod_RevertOn_UnclaimedBatches() external {
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        ensureWithdrawalsBatchesQueueClosed();

        vm.expectRevert(Escrow.UnclaimedBatches.selector);
        _escrow.startRageQuitExtensionPeriod();
    }

    function test_startRageQuitExtensionPeriod_RevertOn_UnfinalizedUnstETHIds() external {
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        ensureWithdrawalsBatchesQueueClosed();
        claimStEthViaWQ(unstEthIds, stethAmount);

        WithdrawalQueueMock(_withdrawalQueue).setLastFinalizedRequestId(0);

        vm.expectRevert(Escrow.UnfinalizedUnstETHIds.selector);
        _escrow.startRageQuitExtensionPeriod();
    }

    // ---
    // claimUnstETH()
    // ---

    function test_claimUnstETH_HappyPath() external {
        uint256[] memory unstEthAmounts = new uint256[](1);
        unstEthAmounts[0] = 1 ether;

        uint256[] memory unstEthIds = vetoerLockedUnstEth(unstEthAmounts);
        uint256[] memory hints = finalizeUnstEth(unstEthAmounts, unstEthIds);

        transitToRageQuit();

        claimUnstEthFromEscrow(unstEthAmounts, unstEthIds, hints);
    }

    function test_claimUnstETH_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.claimUnstETH(new uint256[](1), new uint256[](1));
    }

    function test_claimUnstETH_RevertOn_InvalidRequestId() external {
        bytes memory wqInvalidRequestIdError = abi.encode("WithdrawalQueue.InvalidRequestId");
        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory hints = new uint256[](1);

        transitToRageQuit();

        vm.mockCallRevert(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getClaimableEther.selector, unstETHIds, hints),
            wqInvalidRequestIdError
        );

        vm.expectRevert(wqInvalidRequestIdError);
        _escrow.claimUnstETH(unstETHIds, hints);
    }

    function test_claimUnstETH_RevertOn_ArraysLengthMismatch() external {
        bytes memory wqArraysLengthMismatchError = abi.encode("WithdrawalQueue.ArraysLengthMismatch");
        uint256[] memory unstETHIds = new uint256[](2);
        uint256[] memory hints = new uint256[](1);
        uint256[] memory responses = new uint256[](1);
        responses[0] = 1 ether;

        transitToRageQuit();

        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getClaimableEther.selector, unstETHIds, hints),
            abi.encode(responses)
        );

        vm.mockCallRevert(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.claimWithdrawals.selector, unstETHIds, hints),
            wqArraysLengthMismatchError
        );

        vm.expectRevert(wqArraysLengthMismatchError);
        _escrow.claimUnstETH(unstETHIds, hints);
    }

    function test_claimUnstETH_RevertOn_InvalidUnstETHStatus() external {
        uint256[] memory unstEthAmounts = new uint256[](1);
        unstEthAmounts[0] = 1 ether;

        uint256[] memory unstEthIds = new uint256[](1);
        unstEthIds[0] = Random.nextUint256(_random, 100500);

        uint256[] memory hints = finalizeUnstEth(unstEthAmounts, unstEthIds);

        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setClaimableAmount(unstEthAmounts[0]);
        vm.deal(_withdrawalQueue, unstEthAmounts[0]);

        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getClaimableEther.selector, unstEthIds, hints),
            abi.encode(unstEthAmounts)
        );

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
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);
        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        ensureWithdrawalsBatchesQueueClosed();
        claimStEthViaWQ(unstEthIds, stethAmount);
        ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.isRageQuitExtensionPeriodStarted());

        _wait(Durations.from(1));

        vm.startPrank(_vetoer);
        vm.expectEmit();
        emit AssetsAccounting.ETHWithdrawn(_vetoer, SharesValues.from(stethAmount), ETHValues.from(stethAmount));
        _escrow.withdrawETH();
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore + stethAmount);
    }

    function test_withdrawETH_RevertOn_UnexpectedEscrowState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.RageQuitEscrow));
        _escrow.withdrawETH();
    }

    function test_withdrawETH_RevertOn_RageQuitExtensionPeriodNotStarted() external {
        transitToRageQuit();

        vm.expectRevert(EscrowStateLib.RageQuitExtensionPeriodNotStarted.selector);
        _escrow.withdrawETH();
    }

    function test_withdrawETH_RevertOn_EthWithdrawalsDelayNotPassed() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);

        transitToRageQuit(Durations.from(1), Durations.from(2));
        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        ensureWithdrawalsBatchesQueueClosed();
        claimStEthViaWQ(unstEthIds, stethAmount);
        ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.isRageQuitExtensionPeriodStarted());

        vm.startPrank(_vetoer);
        vm.expectRevert(EscrowStateLib.EthWithdrawalsDelayNotPassed.selector);
        _escrow.withdrawETH();
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore);
    }

    function test_withdrawETH_RevertOn_InvalidSharesValue() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        address _vetoer2 = makeAddr("vetoer2");
        _stETH.mint(_vetoer2, 100 ether);

        vm.startPrank(_vetoer2);
        ERC20Mock(address(_stETH)).approve(address(_escrow), type(uint256).max);
        _escrow.lockStETH(100 ether);
        vm.stopPrank();

        vetoerLockedStEth(stethAmount);

        _wait(_minLockAssetDuration.plusSeconds(1));

        vetoerUnlockedStEth(stethAmount);

        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);

        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);
        ensureWithdrawalsBatchesQueueClosed();
        claimStEthViaWQ(unstEthIds, stethAmount);
        ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.isRageQuitExtensionPeriodStarted());

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

        uint256[] memory unstEthIds = vetoerLockedUnstEth(unstEthAmounts);
        uint256[] memory hints = finalizeUnstEth(unstEthAmounts, unstEthIds);

        transitToRageQuit();

        uint256 sum = claimUnstEthFromEscrow(unstEthAmounts, unstEthIds, hints);

        ensureWithdrawalsBatchesQueueClosed();

        ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.isRageQuitExtensionPeriodStarted());

        _wait(Durations.from(1));

        vm.startPrank(_vetoer);
        vm.expectEmit();
        emit AssetsAccounting.UnstETHWithdrawn(unstEthIds, ETHValues.from(sum));
        _escrow.withdrawETH(unstEthIds);
        vm.stopPrank();

        assertEq(_vetoer.balance, balanceBefore + sum);
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
        transitToRageQuit();

        vm.expectRevert(EscrowStateLib.RageQuitExtensionPeriodNotStarted.selector);
        _escrow.withdrawETH(new uint256[](1));
    }

    function test_withdrawETH_2_RevertOn_EthWithdrawalsDelayNotPassed() external {
        uint256 balanceBefore = _vetoer.balance;
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = 1 ether;
        unstEthAmounts[1] = 10 ether;

        uint256[] memory unstEthIds = vetoerLockedUnstEth(unstEthAmounts);
        uint256[] memory hints = finalizeUnstEth(unstEthAmounts, unstEthIds);

        transitToRageQuit(Durations.from(10), Durations.from(10));

        claimUnstEthFromEscrow(unstEthAmounts, unstEthIds, hints);

        ensureWithdrawalsBatchesQueueClosed();

        ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.isRageQuitExtensionPeriodStarted());

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

        uint256[] memory unstEthIds = vetoerLockedUnstEth(unstEthAmounts);
        finalizeUnstEth(unstEthAmounts, unstEthIds);

        transitToRageQuit();

        ensureWithdrawalsBatchesQueueClosed();

        ensureRageQuitExtensionPeriodStartedNow();
        assertTrue(_escrow.isRageQuitExtensionPeriodStarted());

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

    function test_getLockedAssetsTotals() external {
        LockedAssetsTotals memory escrowLockedAssets = _escrow.getLockedAssetsTotals();

        assertEq(escrowLockedAssets.stETHLockedShares, 0);
        assertEq(escrowLockedAssets.stETHClaimedETH, 0);
        assertEq(escrowLockedAssets.unstETHUnfinalizedShares, 0);
        assertEq(escrowLockedAssets.unstETHFinalizedETH, 0);
    }

    // ---
    // getVetoerState()
    // ---

    function test_getVetoerState() external {
        vetoerLockedStEth(stethAmount);

        VetoerState memory state = _escrow.getVetoerState(_vetoer);

        assertEq(state.unstETHIdsCount, 0);
        assertEq(state.stETHLockedShares, _stETH.getSharesByPooledEth(stethAmount));
        assertEq(state.unstETHLockedShares, 0);
        assertEq(state.lastAssetsLockTimestamp, Timestamps.now().toSeconds());
    }

    // ---
    // getUnclaimedUnstETHIdsCount()
    // ---

    function test_getUnclaimedUnstETHIdsCount() external {
        assertEq(_escrow.getUnclaimedUnstETHIdsCount(), 0);
    }

    // ---
    // getNextWithdrawalBatch()
    // ---

    function test_getNextWithdrawalBatch() external {
        uint256[] memory unstEthIds = getUnstEthIdsFromWQ();

        vetoerLockedStEth(stethAmount);

        transitToRageQuit();

        uint256[] memory claimableUnstEthIds = _escrow.getNextWithdrawalBatch(100);
        assertEq(claimableUnstEthIds.length, 0);

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(unstEthIds);
        ensureUnstEthAddedToWithdrawalsBatchesQueue(unstEthIds, stethAmount);

        claimableUnstEthIds = _escrow.getNextWithdrawalBatch(100);
        assertEq(claimableUnstEthIds.length, unstEthIds.length);
        assertEq(claimableUnstEthIds[0], unstEthIds[0]);

        WithdrawalQueueMock(_withdrawalQueue).setClaimableAmount(stethAmount);
        vm.deal(_withdrawalQueue, stethAmount);

        vm.mockCall(
            _withdrawalQueue, abi.encodeWithSelector(IWithdrawalQueue.getLastCheckpointIndex.selector), abi.encode(1)
        );
        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.findCheckpointHints.selector),
            abi.encode(new uint256[](unstEthIds.length))
        );

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstEthIds);
        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(ETHValues.from(stethAmount));
        _escrow.claimNextWithdrawalsBatch(unstEthIds[0], new uint256[](unstEthIds.length));

        claimableUnstEthIds = _escrow.getNextWithdrawalBatch(100);
        assertEq(claimableUnstEthIds.length, 0);
    }

    // TODO: looks like missing check for WithdrawalsBatchesQueue is in Open state
    function test_getNextWithdrawalBatch_RevertOn_RageQuit_IsNotStarted() external {
        vm.expectRevert(stdError.indexOOBError);
        _escrow.getNextWithdrawalBatch(100);
    }

    // ---
    // isWithdrawalsBatchesFinalized()
    // ---

    function test_isWithdrawalsBatchesFinalized() external {
        assertFalse(_escrow.isWithdrawalsBatchesFinalized());

        transitToRageQuit();

        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsResult(new uint256[](0));

        ensureWithdrawalsBatchesQueueClosed();

        assertTrue(_escrow.isWithdrawalsBatchesFinalized());
    }

    // ---
    // isRageQuitExtensionPeriodStarted()
    // ---

    function test_isRageQuitExtensionPeriodStarted() external {
        assertFalse(_escrow.isRageQuitExtensionPeriodStarted());

        transitToRageQuit();

        ensureWithdrawalsBatchesQueueClosed();

        ensureRageQuitExtensionPeriodStartedNow();

        assertTrue(_escrow.isRageQuitExtensionPeriodStarted());

        assertEq(_escrow.getRageQuitExtensionPeriodStartedAt(), Timestamps.now());
    }

    // ---
    // getRageQuitExtensionPeriodStartedAt()
    // ---

    function test_getRageQuitExtensionPeriodStartedAt() external {
        Timestamp res = _escrow.getRageQuitExtensionPeriodStartedAt();
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

        vetoerLockedStEth(stEthLockedAmount);

        PercentD16 support = _escrow.getRageQuitSupport();
        assertEq(support, actualSupport);
        assertEq(support, PercentsD16.fromBasisPoints(80_00));

        // When some unstEth are locked in escrow => rage quit support changed

        uint256[] memory unstEthIds = vetoerLockedUnstEth(unstEthAmounts);

        finalizedUnstEthAmounts[0] = unstEthAmounts[0];
        finalizedUnstEthIds[0] = unstEthIds[0];

        finalizeUnstEth(finalizedUnstEthAmounts, finalizedUnstEthIds);

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
        transitToRageQuit();

        ensureWithdrawalsBatchesQueueClosed();

        ensureRageQuitExtensionPeriodStartedNow();

        _wait(Durations.from(1));

        assertTrue(_escrow.isRageQuitFinalized());
    }

    // ---
    // receive()
    // ---

    function test_receive() external {
        vm.deal(_withdrawalQueue, 1 ether);
        vm.deal(address(this), 1 ether);

        assertEq(address(_escrow).balance, 0);

        vm.startPrank(_withdrawalQueue);
        sendTo(ETHValues.from(1 ether), payable(address(_escrow)));
        vm.stopPrank();

        assertEq(address(_escrow).balance, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidETHSender.selector, address(this), _withdrawalQueue));
        sendTo(ETHValues.from(1 ether), payable(address(_escrow)));

        assertEq(address(_escrow).balance, 1 ether);
        assertEq(address(this).balance, 1 ether);
        assertEq(_withdrawalQueue.balance, 0);
    }

    // ---
    // helper methods
    // ---

    function createEscrow(uint256 size) internal returns (Escrow) {
        return
            new Escrow(_stETH, _wstETH, WithdrawalQueueMock(_withdrawalQueue), IDualGovernance(_dualGovernance), size);
    }

    function createEscrowProxy(uint256 minWithdrawalsBatchSize) internal returns (Escrow) {
        Escrow masterCopy = createEscrow(minWithdrawalsBatchSize);
        return Escrow(payable(Clones.clone(address(masterCopy))));
    }

    function createInitializedEscrowProxy(
        uint256 minWithdrawalsBatchSize,
        Duration minAssetsLockDuration
    ) internal returns (Escrow) {
        Escrow instance = createEscrowProxy(minWithdrawalsBatchSize);

        vm.startPrank(_dualGovernance);
        instance.initialize(minAssetsLockDuration);
        vm.stopPrank();
        return instance;
    }

    function transitToRageQuit() internal {
        vm.startPrank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);
        vm.stopPrank();
    }

    function transitToRageQuit(Duration rqExtensionPeriod, Duration rqEthWithdrawalsDelay) internal {
        vm.startPrank(_dualGovernance);
        _escrow.startRageQuit(rqExtensionPeriod, rqEthWithdrawalsDelay);
        vm.stopPrank();
    }

    function vetoerLockedStEth(uint256 amount) internal {
        vm.startPrank(_vetoer);
        _escrow.lockStETH(amount);
        vm.stopPrank();
    }

    function vetoerLockedUnstEth(uint256[] memory amounts) internal returns (uint256[] memory unstethIds) {
        unstethIds = new uint256[](amounts.length);
        WithdrawalRequestStatus[] memory statuses = new WithdrawalRequestStatus[](amounts.length);

        for (uint256 i = 0; i < amounts.length; ++i) {
            unstethIds[i] = i;
            statuses[i] = WithdrawalRequestStatus(amounts[i], amounts[i], _vetoer, block.timestamp, false, false);
        }

        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getWithdrawalStatus.selector, unstethIds),
            abi.encode(statuses)
        );
        vm.mockCall(_withdrawalQueue, abi.encodeWithSelector(IWithdrawalQueue.transferFrom.selector), abi.encode(true));

        vm.startPrank(_vetoer);
        _escrow.lockUnstETH(unstethIds);
        vm.stopPrank();
    }

    function finalizeUnstEth(
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

        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getClaimableEther.selector, finalizedUnstEthIds, hints),
            abi.encode(responses)
        );

        _escrow.markUnstETHFinalized(finalizedUnstEthIds, hints);

        for (uint256 i = 0; i < amounts.length; ++i) {
            _stETH.burn(_vetoer, amounts[i]);
        }
    }

    function claimUnstEthFromEscrow(
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

        WithdrawalQueueMock(_withdrawalQueue).setClaimableAmount(sum);
        vm.deal(_withdrawalQueue, sum);

        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getClaimableEther.selector, unstEthIds, hints),
            abi.encode(amounts)
        );

        vm.expectEmit();
        emit AssetsAccounting.UnstETHClaimed(unstEthIds, ETHValues.from(sum));
        _escrow.claimUnstETH(unstEthIds, hints);
    }

    function claimStEthViaWQ(uint256[] memory unstEthIds, uint256 amount) internal {
        WithdrawalQueueMock(_withdrawalQueue).setClaimableAmount(amount);
        vm.deal(_withdrawalQueue, amount);

        vm.mockCall(
            _withdrawalQueue, abi.encodeWithSelector(IWithdrawalQueue.getLastCheckpointIndex.selector), abi.encode(1)
        );
        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.findCheckpointHints.selector),
            abi.encode(new uint256[](unstEthIds.length))
        );

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstEthIds);
        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(ETHValues.from(amount));
        _escrow.claimNextWithdrawalsBatch(unstEthIds.length);
    }

    function vetoerUnlockedStEth(uint256 amount) internal {
        vm.startPrank(_vetoer);
        vm.expectEmit();
        emit AssetsAccounting.StETHSharesUnlocked(_vetoer, SharesValues.from(_stETH.getSharesByPooledEth(amount)));
        _escrow.unlockStETH();
        vm.stopPrank();
    }

    function ensureUnstEthAddedToWithdrawalsBatchesQueue(uint256[] memory unstEthIds, uint256 ethAmount) internal {
        WithdrawalQueueMock(_withdrawalQueue).setRequestWithdrawalsTransferAmount(ethAmount);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(unstEthIds);
        _escrow.requestNextWithdrawalsBatch(100);
    }

    function ensureWithdrawalsBatchesQueueClosed() internal {
        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueClosed();
        _escrow.requestNextWithdrawalsBatch(100);
    }

    function ensureRageQuitExtensionPeriodStartedNow() internal {
        vm.expectEmit();
        emit EscrowStateLib.RageQuitExtensionPeriodStarted(Timestamps.now());
        _escrow.startRageQuitExtensionPeriod();
    }

    function getUnstEthIdsFromWQ() internal returns (uint256[] memory unstEthIds) {
        uint256 lri = Random.nextUint256(_random, 100500);
        WithdrawalQueueMock(_withdrawalQueue).setLastRequestId(lri);
        WithdrawalQueueMock(_withdrawalQueue).setLastFinalizedRequestId(lri + 1);

        unstEthIds = new uint256[](1);
        unstEthIds[0] = lri + 1;
    }
}
