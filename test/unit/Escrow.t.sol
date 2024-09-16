// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {Escrow} from "contracts/Escrow.sol";

import {EscrowState as EscrowStateLib, State as EscrowState} from "contracts/libraries/EscrowState.sol";
import {AssetsAccounting} from "contracts/libraries/AssetsAccounting.sol";

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

contract EscrowUnitTests is UnitTest {
    address private _dualGovernance = makeAddr("dualGovernance");
    address private _vetoer = makeAddr("vetoer");

    Escrow private _escrow;

    StETHMock private _stETH;
    WstETHMock private _wstETH;

    address private _withdrawalQueue;

    Duration _minLockAssetDuration = Durations.from(1 days);

    function setUp() external {
        _stETH = new StETHMock();
        _wstETH = new WstETHMock();
        _withdrawalQueue = address(new WithdrawalQueueMock());
        _escrow = createInitializedEscrowProxy(100, _minLockAssetDuration);

        vm.startPrank(_vetoer);
        ERC20Mock(address(_stETH)).approve(address(_escrow), type(uint256).max);
        ERC20Mock(address(_wstETH)).approve(address(_escrow), type(uint256).max);
        vm.stopPrank();

        ERC20Mock(address(_stETH)).mint(_vetoer, 100 ether);
        ERC20Mock(address(_wstETH)).mint(_vetoer, 100 ether);

        vm.mockCall(
            _dualGovernance, abi.encodeWithSelector(IDualGovernance.activateNextState.selector), abi.encode(true)
        );
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

        vm.startPrank(_vetoer);
        _escrow.lockStETH(amount);

        uint256 vetoerBalanceAfter = ERC20Mock(address(_stETH)).balanceOf(_vetoer);
        uint256 escrowBalanceAfter = ERC20Mock(address(_stETH)).balanceOf(address(_escrow));

        assertEq(vetoerBalanceAfter, vetoerBalanceBefore - amount);
        assertEq(escrowBalanceAfter, escrowBalanceBefore + amount);
    }

    function test_lockStETH_RevertOn_UnexpectedEscrowState() external {
        vm.prank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);

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

        vm.prank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);

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

    function test_lockUnstETH_RevertOn_EmplyUnstETHIds() external {
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

        vm.prank(_vetoer);
        _escrow.lockUnstETH(unstethIds);

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

    function test_unlockUnstETH_EmplyUnstETHIds() external {
        uint256[] memory unstethIds = new uint256[](0);

        _wait(_minLockAssetDuration.plusSeconds(1));

        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));
        vm.expectCall(address(_dualGovernance), abi.encodeWithSelector(IDualGovernance.activateNextState.selector));

        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstethIds);
    }

    function test_unlockUnstETH_RevertOn_MinAssetsLockDurationNotPassed() external {
        uint256[] memory unstethIds = new uint256[](0);

        _wait(_minLockAssetDuration.minusSeconds(1));

        // Exception. Due to no assets of holder registered in Escrow.
        vm.expectRevert(
            abi.encodeWithSelector(AssetsAccounting.MinAssetsLockDurationNotPassed.selector, _minLockAssetDuration)
        );
        vm.prank(_vetoer);
        _escrow.unlockUnstETH(unstethIds);
    }

    function test_unlockUnstETH_RevertOn_UnexpectedEscrowState() external {
        transitToRageQuit();

        uint256[] memory unstethIds = new uint256[](0);
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
    // requestWithdrawals()
    // ---

    function test_requestWithdrawals_HappyPath() external {
        uint256 amount = 3 ether;
        vm.prank(_vetoer);
        _escrow.lockStETH(amount);

        uint256[] memory stethAmounts = new uint256[](2);

        stethAmounts[0] = 1 ether;
        stethAmounts[1] = 2 ether;

        uint256[] memory responses = new uint256[](1);
        responses[0] = 1;

        WithdrawalRequestStatus[] memory statuses = new WithdrawalRequestStatus[](1);
        statuses[0] =
            WithdrawalRequestStatus(amount, _stETH.getSharesByPooledEth(amount), _vetoer, block.timestamp, false, false);

        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.requestWithdrawals.selector, stethAmounts, address(_escrow)),
            abi.encode(responses)
        );
        vm.mockCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getWithdrawalStatus.selector, responses),
            abi.encode(statuses)
        );
        vm.expectCall(
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.requestWithdrawals.selector, stethAmounts, address(_escrow))
        );
        vm.expectCall(
            _withdrawalQueue, abi.encodeWithSelector(IWithdrawalQueue.getWithdrawalStatus.selector, responses)
        );

        vm.prank(_vetoer);
        _escrow.requestWithdrawals(stethAmounts);
    }

    function test_requestWithdrawals_RevertOn_UnexpectedEscrowState() external {
        transitToRageQuit();

        uint256[] memory stethAmounts = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(EscrowStateLib.UnexpectedState.selector, EscrowState.SignallingEscrow));
        _escrow.requestWithdrawals(stethAmounts);
    }

    // ---
    // startRageQuit()
    // ---

    // TODO: check is it enough?
    function test_startRageQuit_HappyPath() external {
        vm.expectEmit();
        emit EscrowStateLib.RageQuitStarted(Durations.ZERO, Durations.ZERO);

        vm.prank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);
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

    function test_requestNextWithdrawalsBatch_HapyPath() external {}

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

        vm.prank(_dualGovernance);
        instance.initialize(minAssetsLockDuration);
        return instance;
    }

    function transitToRageQuit() internal {
        vm.prank(_dualGovernance);
        _escrow.startRageQuit(Durations.ZERO, Durations.ZERO);
    }
}
