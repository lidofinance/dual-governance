// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdError} from "forge-std/StdError.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {ETHValues, sendTo} from "contracts/types/ETHValue.sol";
import {SharesValues} from "contracts/types/SharesValue.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

import {Escrow} from "contracts/Escrow.sol";
import {EscrowState, State} from "contracts/libraries/EscrowState.sol";

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

import {StETHMock} from "test/mocks/StETHMock.sol";
import {WithdrawalQueueMock} from "test/mocks/WithdrawalQueueMock.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract EscrowUnitTests is UnitTest {
    address private _dualGovernance = makeAddr("dualGovernance");
    address private _vetoer = makeAddr("vetoer");

    Escrow private _masterCopy;
    Escrow private _escrow;

    StETHMock private _stETH;
    IWstETH private _wstETH;

    WithdrawalQueueMock private _withdrawalQueue;

    Duration private _minLockAssetDuration = Durations.from(1 days);
    uint256 private stethAmount = 100 ether;

    function setUp() external {
        _stETH = new StETHMock();
        _stETH.__setShareRate(1);
        _wstETH = IWstETH(address(new ERC20Mock()));
        _withdrawalQueue = new WithdrawalQueueMock(_stETH);
        _withdrawalQueue.setMaxStETHWithdrawalAmount(1_000 ether);
        _masterCopy = new Escrow(
            _stETH,
            _wstETH,
            WithdrawalQueueMock(_withdrawalQueue),
            IDualGovernance(_dualGovernance),
            100,
            Durations.from(1000)
        );
        _escrow = Escrow(payable(Clones.clone(address(_masterCopy))));

        vm.prank(address(_escrow));
        _stETH.approve(address(_withdrawalQueue), type(uint256).max);

        vm.prank(_dualGovernance);
        _escrow.initialize(_minLockAssetDuration);

        vm.startPrank(_vetoer);
        ERC20Mock(address(_stETH)).approve(address(_escrow), type(uint256).max);
        ERC20Mock(address(_wstETH)).approve(address(_escrow), type(uint256).max);
        vm.stopPrank();

        vm.mockCall(
            _dualGovernance, abi.encodeWithSelector(IDualGovernance.activateNextState.selector), abi.encode(true)
        );
    }
    // ---
    // getVetoerUnstETHIds()
    // ---

    function test_getVetoerUnstETHIds() external {
        uint256[] memory unstEthAmounts = new uint256[](2);
        unstEthAmounts[0] = 1 ether;
        unstEthAmounts[1] = 10 ether;

        assertEq(_escrow.getVetoerUnstETHIds(_vetoer).length, 0);

        uint256[] memory unstEthIds = vetoerLockedUnstEth(unstEthAmounts);

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
    // getUnclaimedUnstETHIdsCount()
    // ---

    function test_getUnclaimedUnstETHIdsCount_RevertOn_UnexpectedState_Signaling() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.RageQuitEscrow));
        _escrow.getUnclaimedUnstETHIdsCount();
    }

    function test_getUnclaimedUnstETHIdsCount_RevertOn_UnexpectedState_NotInitialized() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.RageQuitEscrow));
        _masterCopy.getUnclaimedUnstETHIdsCount();
    }

    // ---
    // getNextWithdrawalBatch()
    // ---

    function test_getNextWithdrawalBatch_RevertOn_UnexpectedState_Signaling() external {
        uint256 batchLimit = 10;
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.RageQuitEscrow));
        _escrow.getNextWithdrawalBatch(batchLimit);
    }

    function test_getNextWithdrawalBatch_RevertOn_UnexpectedState_NotInitialized() external {
        uint256 batchLimit = 10;
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.RageQuitEscrow));
        _masterCopy.getNextWithdrawalBatch(batchLimit);
    }

    // ---
    // isWithdrawalsBatchesClosed()
    // ---

    function test_isWithdrawalsBatchesClosed_RevertOn_UnexpectedState_Signaling() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.RageQuitEscrow));
        _escrow.isWithdrawalsBatchesClosed();
    }

    function test_isWithdrawalsBatchesClosed_RevertOn_UnexpectedState_NotInitialized() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.RageQuitEscrow));
        _masterCopy.isWithdrawalsBatchesClosed();
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

    function vetoerLockedUnstEth(uint256[] memory amounts) internal returns (uint256[] memory unstethIds) {
        unstethIds = new uint256[](amounts.length);
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](amounts.length);

        for (uint256 i = 0; i < amounts.length; ++i) {
            unstethIds[i] = i;
            statuses[i] =
                IWithdrawalQueue.WithdrawalRequestStatus(amounts[i], amounts[i], _vetoer, block.timestamp, false, false);
        }

        vm.mockCall(
            address(_withdrawalQueue),
            abi.encodeWithSelector(IWithdrawalQueue.getWithdrawalStatus.selector, unstethIds),
            abi.encode(statuses)
        );
        vm.mockCall(
            address(_withdrawalQueue), abi.encodeWithSelector(IWithdrawalQueue.transferFrom.selector), abi.encode(true)
        );

        vm.startPrank(_vetoer);
        _escrow.lockUnstETH(unstethIds);
        vm.stopPrank();
    }
}
