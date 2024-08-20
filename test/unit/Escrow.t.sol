// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IEscrow} from "contracts/interfaces/IEscrow.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {Escrow} from "contracts/Escrow.sol";
import {EscrowState as EscrowStateLib, State as EscrowState} from "contracts/libraries/EscrowState.sol";
import {WithdrawalsBatchesQueue} from "contracts/libraries/WithdrawalBatchesQueue.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {StETHMock} from "test/mocks/StETHMock.sol";
import {WstETHMock} from "test/mocks/WstETHMock.sol";
import {DualGovernanceMock} from "test/mocks/DualGovernanceMock.sol";
import {WithdrawalQueueMock} from "test/mocks/WithdrawalQueueMock.sol";
import {UnitTest} from "test/utils/unit-test.sol";
import {Random} from "test/utils/random.sol";

contract EscrowUnitTests is UnitTest {
    Random.Context private _random;
    IStETH private _stETH;
    IWstETH private _wstETH;
    WithdrawalQueueMock private _withdrawalQueue;
    DualGovernanceMock private _dualGovernance;

    function setUp() external {
        _random = Random.create(block.timestamp);
        _stETH = new StETHMock();
        _wstETH = new WstETHMock();
        _dualGovernance = new DualGovernanceMock();
        _withdrawalQueue = new WithdrawalQueueMock();
    }

    // ---
    // Escrow constructor()
    // ---

    function testFuzz_Escrow_constructor(uint256 size) external {
        Escrow instance = new Escrow(_stETH, _wstETH, _withdrawalQueue, _dualGovernance, size);

        assertEq(address(instance.ST_ETH()), address(_stETH));
        assertEq(address(instance.WST_ETH()), address(_wstETH));
        assertEq(address(instance.WITHDRAWAL_QUEUE()), address(_withdrawalQueue));
        assertEq(address(instance.DUAL_GOVERNANCE()), address(_dualGovernance));
        assertEq(instance.MIN_WITHDRAWALS_BATCH_SIZE(), size);
    }

    // ---
    // initialize()
    // ---

    function test_initialize_HappyPath() external {
        vm.expectEmit();
        emit EscrowStateLib.EscrowStateChanged(EscrowState.NotInitialized, EscrowState.SignallingEscrow);
        emit EscrowStateLib.MinAssetsLockDurationSet(Durations.ZERO);

        createInitializedEscrowProxy(100, Durations.ZERO);
    }

    function test_initialize_RevertWhen_CalledNotViaProxy() external {
        Escrow instance = createEscrow(100);

        vm.expectRevert(Escrow.NonProxyCallsForbidden.selector);
        instance.initialize(Durations.ZERO);
    }

    function test_initialize_RevertWhen_CalledNotFromDualGovernance() external {
        IEscrow instance = createEscrowProxy(100);

        vm.expectRevert(abi.encodeWithSelector(Escrow.CallerIsNotDualGovernance.selector, address(this)));

        instance.initialize(Durations.ZERO);
    }

    // ---
    // requestNextWithdrawalsBatch()
    // ---

    function test_requestNextWithdrawalsBatch_RevertOn_InvalidBatchSize() external {
        IEscrow instance = createInitializedEscrowProxy(100, Durations.ZERO);

        uint256 lri = Random.nextUint256(_random, 100500);
        _withdrawalQueue.setLastRequestId(lri);

        _dualGovernance.startRageQuitForEscrow(instance, Durations.from(1), Durations.from(2));

        uint256 batchSize = 99;
        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidBatchSize.selector, batchSize));
        instance.requestNextWithdrawalsBatch(99);
    }

    // ---
    // claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] calldata hints)
    // ---

    function test_claimNextWithdrawalsBatch_2_RevertOn_UnexpectedUnstETHId() external {
        IEscrow instance = createInitializedEscrowProxy(100, Durations.ZERO);

        uint256 lri = Random.nextUint256(_random, 100500);
        _withdrawalQueue.setLastRequestId(lri);
        _withdrawalQueue.setLastFinalizedRequestId(lri + 1);

        uint256[] memory withdrawalReqIds = new uint256[](1);
        withdrawalReqIds[0] = lri + 1;

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueOpened(lri);
        _dualGovernance.startRageQuitForEscrow(instance, Durations.from(1), Durations.from(2));

        _withdrawalQueue.setMinStETHWithdrawalAmount(0);
        _withdrawalQueue.setMaxStETHWithdrawalAmount(20);
        _withdrawalQueue.setRequestWithdrawalsResult(withdrawalReqIds);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(withdrawalReqIds);
        instance.requestNextWithdrawalsBatch(100);

        vm.expectRevert(Escrow.UnexpectedUnstETHId.selector);
        instance.claimNextWithdrawalsBatch(lri + 10, new uint256[](1));
    }

    function test_claimNextWithdrawalsBatch_2_RevertOn_InvalidHintsLength() external {
        IEscrow instance = createInitializedEscrowProxy(100, Durations.ZERO);

        uint256 lri = Random.nextUint256(_random, 100500);
        _withdrawalQueue.setLastRequestId(lri);
        _withdrawalQueue.setLastFinalizedRequestId(lri + 1);

        uint256[] memory withdrawalReqIds = new uint256[](1);
        withdrawalReqIds[0] = lri + 1;

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueOpened(lri);
        _dualGovernance.startRageQuitForEscrow(instance, Durations.from(1), Durations.from(2));

        _withdrawalQueue.setMinStETHWithdrawalAmount(0);
        _withdrawalQueue.setMaxStETHWithdrawalAmount(20);
        _withdrawalQueue.setRequestWithdrawalsResult(withdrawalReqIds);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(withdrawalReqIds);
        instance.requestNextWithdrawalsBatch(100);

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidHintsLength.selector, 10, 1));
        instance.claimNextWithdrawalsBatch(lri + 1, new uint256[](10));
    }

    // ---
    // startRageQuitExtensionDelay()
    // ---

    function test_startRageQuitExtensionDelay_RevertOn_UnclaimedBatches() external {
        IEscrow instance = createInitializedEscrowProxy(100, Durations.ZERO);

        uint256 lri = Random.nextUint256(_random, 100500);
        _withdrawalQueue.setLastRequestId(lri);
        _withdrawalQueue.setLastFinalizedRequestId(lri + 1);

        uint256[] memory withdrawalReqIds = new uint256[](1);
        withdrawalReqIds[0] = lri + 1;

        _dualGovernance.startRageQuitForEscrow(instance, Durations.from(1), Durations.from(2));
        _withdrawalQueue.setMinStETHWithdrawalAmount(0);
        _withdrawalQueue.setMaxStETHWithdrawalAmount(20);
        _withdrawalQueue.setRequestWithdrawalsResult(withdrawalReqIds);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(withdrawalReqIds);
        instance.requestNextWithdrawalsBatch(100);

        _withdrawalQueue.setMinStETHWithdrawalAmount(10);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueClosed();
        instance.requestNextWithdrawalsBatch(100);

        vm.expectRevert(Escrow.UnclaimedBatches.selector);
        instance.startRageQuitExtensionDelay();
    }

    // ---
    // setMinAssetsLockDuration()
    // ---

    function test_setMinAssetsLockDuration_HappyPath() external {
        IEscrow instance = createInitializedEscrowProxy(100, Durations.ZERO);

        Duration newMinAssetsLockDuration = Durations.from(200);
        vm.expectEmit();
        emit EscrowStateLib.MinAssetsLockDurationSet(newMinAssetsLockDuration);
        _dualGovernance.setMinAssetsLockDurationForEscrow(instance, newMinAssetsLockDuration);
    }

    // ---
    // isRageQuitExtensionDelayStarted()
    // ---

    function test_isRageQuitExtensionDelayStarted() external {
        IEscrow instance = createInitializedEscrowProxy(100, Durations.ZERO);

        bool res = instance.isRageQuitExtensionDelayStarted();
        assertFalse(res);
    }

    // ---
    // getRageQuitExtensionDelayStartedAt()
    // ---

    function test_getRageQuitExtensionDelayStartedAt() external {
        IEscrow instance = createInitializedEscrowProxy(100, Durations.ZERO);

        Timestamp res = instance.getRageQuitExtensionDelayStartedAt();
        assertEq(res.toSeconds(), Timestamps.ZERO.toSeconds());
    }

    // ---
    // helper methods
    // ---

    function createEscrow(uint256 size) internal returns (Escrow) {
        return new Escrow(_stETH, _wstETH, _withdrawalQueue, _dualGovernance, size);
    }

    function createEscrowProxy(uint256 minWithdrawalsBatchSize) internal returns (IEscrow) {
        Escrow masterCopy = createEscrow(minWithdrawalsBatchSize);
        return IEscrow(Clones.clone(address(masterCopy)));
    }

    function createInitializedEscrowProxy(
        uint256 minWithdrawalsBatchSize,
        Duration minAssetsLockDuration
    ) internal returns (IEscrow) {
        IEscrow instance = createEscrowProxy(minWithdrawalsBatchSize);

        _dualGovernance.initializeEscrow(instance, minAssetsLockDuration);
        return instance;
    }
}
