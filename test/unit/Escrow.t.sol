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

    address private _withdrawalQueue;

    Duration private _minLockAssetDuration = Durations.from(1 days);
    uint256 private stethAmount = 100 ether;

    function setUp() external {
        _stETH = new StETHMock();
        _stETH.__setShareRate(1);
        _wstETH = IWstETH(address(new ERC20Mock()));
        _withdrawalQueue = address(new WithdrawalQueueMock());
        _masterCopy =
            new Escrow(_stETH, _wstETH, WithdrawalQueueMock(_withdrawalQueue), IDualGovernance(_dualGovernance), 100);
        _escrow = Escrow(payable(Clones.clone(address(_masterCopy))));

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

    function test_getRageQuitEscrowDetails_RevertOn_UnexpectedState_Signaling() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.RageQuitEscrow));
        _escrow.getRageQuitEscrowDetails();
    }

    function test_getRageQuitEscrowDetails_RevertOn_UnexpectedState_NotInitialized() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.RageQuitEscrow));
        _masterCopy.getRageQuitEscrowDetails();
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
            _withdrawalQueue,
            abi.encodeWithSelector(IWithdrawalQueue.getWithdrawalStatus.selector, unstethIds),
            abi.encode(statuses)
        );
        vm.mockCall(_withdrawalQueue, abi.encodeWithSelector(IWithdrawalQueue.transferFrom.selector), abi.encode(true));

        vm.startPrank(_vetoer);
        _escrow.lockUnstETH(unstethIds);
        vm.stopPrank();
    }

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
}
