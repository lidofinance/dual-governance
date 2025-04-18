// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {EscrowState, State} from "contracts/libraries/EscrowState.sol";
import {WithdrawalsBatchesQueue} from "contracts/libraries/WithdrawalsBatchesQueue.sol";
import {AssetsAccounting, UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";

import {Escrow} from "contracts/Escrow.sol";

import {LidoUtils, DGScenarioTestSetup} from "../utils/integration-tests.sol";

contract EscrowOperationsScenarioTest is DGScenarioTestSetup {
    using LidoUtils for LidoUtils.Context;

    Escrow internal escrow;

    Duration internal immutable _RAGE_QUIT_EXTRA_TIMELOCK = Durations.from(14 days);
    Duration internal immutable _RAGE_QUIT_WITHDRAWALS_TIMELOCK = Durations.from(7 days);

    address internal immutable _VETOER_1 = makeAddr("VETOER_1");
    address internal immutable _VETOER_2 = makeAddr("VETOER_2");

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});

        escrow = Escrow(payable(address(_getVetoSignallingEscrow())));

        _setupStETHBalance(_VETOER_1, PercentsD16.fromBasisPoints(10_00));

        vm.startPrank(_VETOER_1);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        _lido.wstETH.wrap(100_000 * 10 ** 18);
        vm.stopPrank();

        _setupStETHBalance(_VETOER_2, PercentsD16.fromBasisPoints(10_00));

        vm.startPrank(_VETOER_2);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        _lido.wstETH.wrap(1_000_000 * 10 ** 18);
        vm.stopPrank();
    }

    function testFork_RageQuit_RevertOn_UnfinalizedNFTs() external {
        uint256 requestAmount = 10 * 1e18;
        uint256 requestsCount = 10;
        uint256[] memory amounts = new uint256[](requestsCount);
        for (uint256 i = 0; i < requestsCount; ++i) {
            amounts[i] = requestAmount;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        _lockUnstETH(_VETOER_1, unstETHIds);

        vm.prank(address(_dgDeployedContracts.dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        vm.expectRevert(Escrow.BatchesQueueIsNotClosed.selector);
        escrow.startRageQuitExtensionPeriod();

        escrow.requestNextWithdrawalsBatch(96);

        vm.expectRevert(WithdrawalsBatchesQueue.EmptyBatch.selector);
        escrow.claimNextWithdrawalsBatch(0);

        vm.expectRevert(Escrow.UnfinalizedUnstETHIds.selector);
        escrow.startRageQuitExtensionPeriod();

        _finalizeWithdrawalQueue();

        escrow.startRageQuitExtensionPeriod();

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

        escrow.claimUnstETH(unstETHIds, hints);

        assertEq(escrow.isRageQuitFinalized(), false);

        _wait(_RAGE_QUIT_EXTRA_TIMELOCK.plusSeconds(1));
        assertEq(escrow.isRageQuitFinalized(), true);

        _wait(_RAGE_QUIT_WITHDRAWALS_TIMELOCK.plusSeconds(1));

        vm.startPrank(_VETOER_1);
        escrow.withdrawETH(unstETHIds);
        vm.stopPrank();
    }

    function testFork_LockUnlock_RevertOn_RageQuitEscrow() external {
        uint256[] memory nftAmounts = new uint256[](1);
        nftAmounts[0] = 1 ether;

        vm.startPrank(_VETOER_1);
        uint256[] memory lockedWithdrawalNfts = _lido.withdrawalQueue.requestWithdrawals(nftAmounts, _VETOER_1);
        uint256[] memory notLockedWithdrawalNfts = _lido.withdrawalQueue.requestWithdrawals(nftAmounts, _VETOER_1);
        vm.stopPrank();

        _lockStETH(_VETOER_1, 1 ether);
        _lockWstETH(_VETOER_1, 1 ether);
        _lockUnstETH(_VETOER_1, lockedWithdrawalNfts);

        vm.prank(address(_dgDeployedContracts.dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        // ---
        // After the Escrow enters RageQuitEscrow state, lock/unlock of tokens is forbidden
        // ---

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalLockStETH(_VETOER_1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalLockWstETH(_VETOER_1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalLockUnstETH(_VETOER_1, notLockedWithdrawalNfts);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalUnlockStETH(_VETOER_1);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalUnlockWstETH(_VETOER_1);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalUnlockUnstETH(_VETOER_1, lockedWithdrawalNfts);
    }

    function testFork_RageQuit_RevertOn_FrontRunWithTokensUnlock() external {
        uint256[] memory amounts = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            amounts[i] = _lido.withdrawalQueue.MAX_STETH_WITHDRAWAL_AMOUNT() - 1;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);
        // lock enough funds to initiate RageQuit
        _lockStETH(_VETOER_1, PercentsD16.fromBasisPoints(7_50));
        _lockWstETH(_VETOER_2, PercentsD16.fromBasisPoints(7_49));
        _lockUnstETH(_VETOER_1, unstETHIds);
        _assertVetoSignalingState();

        // wait till the last second of the dynamic timelock duration
        _wait(_getVetoSignallingMaxDuration());
        _activateNextState();
        _assertVetoSignalingState();

        assertEq(_getVetoSignallingDuration().addTo(_getVetoSignallingActivatedAt()), Timestamps.now());

        // validate that while the VetoSignalling has not passed, vetoer can unlock funds from Escrow
        uint256 snapshotId = vm.snapshot();
        _unlockStETH(_VETOER_1);
        _assertVetoSignallingDeactivationState();

        // Rollback the state of the node before vetoer unlocked his funds
        vm.revertTo(snapshotId);

        _unlockWstETH(_VETOER_2);
        _assertVetoSignallingDeactivationState();

        // Rollback the state of the node before vetoer unlocked his funds
        vm.revertTo(snapshotId);

        _unlockUnstETH(_VETOER_1, unstETHIds);
        _assertVetoSignallingDeactivationState();

        // Rollback the state of the node before vetoer unlocked his funds
        vm.revertTo(snapshotId);

        // validate that the DualGovernance still in the VetoSignalling state
        _activateNextState();
        _assertVetoSignalingState();

        // wait 1 block duration. Full VetoSignalling duration has passed and RageQuit may be started now
        _wait(Durations.from(12 seconds));

        // validate that RageQuit will start when the activateNextState() is called
        snapshotId = vm.snapshot();
        _activateNextState();
        _assertRageQuitState();

        // Rollback the state of the node as it was before RageQuit activation
        vm.revertTo(snapshotId);

        // The attempt to unlock funds from Escrow will fail
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalUnlockStETH(_VETOER_1);

        // Rollback the state of the node as it was before RageQuit activation
        vm.revertTo(snapshotId);

        // The attempt to unlock funds from Escrow will fail
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalUnlockWstETH(_VETOER_2);

        // Rollback the state of the node as it was before RageQuit activation
        vm.revertTo(snapshotId);

        // The attempt to unlock funds from Escrow will fail
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalUnlockUnstETH(_VETOER_1, unstETHIds);
    }

    function testFork_ClaimingUnstETH_RevertOn_UnstETHFromWithdrawalBatch() external {
        // Prepare vetoer1 unstETH nft to lock in Escrow
        uint256 requestAmount = 10 * 1e18;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = requestAmount;
        vm.prank(_VETOER_1);
        uint256[] memory unstETHIdsVetoer1 = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        // Should be the same as vetoer1 unstETH nft
        uint256 lastRequestIdBeforeBatch = _lido.withdrawalQueue.getLastRequestId();

        // Lock unstETH nfts
        _lockUnstETH(_VETOER_1, unstETHIdsVetoer1);
        // Lock stETH to generate batch
        _lockStETH(_VETOER_1, 20 * requestAmount);

        vm.prank(address(_dgDeployedContracts.dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        uint256 batchSizeLimit = 16;
        // Generate batch with stETH locked in Escrow
        escrow.requestNextWithdrawalsBatch(batchSizeLimit);

        uint256[] memory nextWithdrawalBatch = escrow.getNextWithdrawalBatch(batchSizeLimit);
        assertEq(nextWithdrawalBatch.length, 1);
        assertEq(nextWithdrawalBatch[0], _lido.withdrawalQueue.getLastRequestId());

        // Should be the id of unstETH nft in the batch
        uint256 requestIdFromBatch = nextWithdrawalBatch[0];

        // validate that the new unstEth nft is created
        assertEq(requestIdFromBatch, lastRequestIdBeforeBatch + 1);

        _finalizeWithdrawalQueue();

        // Check that unstETH nft of vetoer1 could be claimed
        uint256[] memory unstETHIdsToClaim = new uint256[](1);
        unstETHIdsToClaim[0] = lastRequestIdBeforeBatch;
        uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
            unstETHIdsToClaim, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );
        escrow.claimUnstETH(unstETHIdsToClaim, hints);

        // The attempt to claim funds of untEth from Escrow generated batch will fail
        unstETHIdsToClaim[0] = requestIdFromBatch;
        hints = _lido.withdrawalQueue.findCheckpointHints(
            unstETHIdsToClaim, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector, requestIdFromBatch, UnstETHRecordStatus.NotLocked
            )
        );
        escrow.claimUnstETH(unstETHIdsToClaim, hints);

        // The rage quit process can be successfully finished
        while (escrow.getUnclaimedUnstETHIdsCount() > 0) {
            escrow.claimNextWithdrawalsBatch(batchSizeLimit);
        }

        escrow.startRageQuitExtensionPeriod();
        assertEq(escrow.isRageQuitFinalized(), false);

        _wait(_RAGE_QUIT_EXTRA_TIMELOCK.plusSeconds(1));
        assertEq(escrow.isRageQuitFinalized(), true);

        _wait(_RAGE_QUIT_WITHDRAWALS_TIMELOCK.plusSeconds(1));

        vm.startPrank(_VETOER_1);
        escrow.withdrawETH();
        escrow.withdrawETH(unstETHIdsVetoer1);
        vm.stopPrank();
    }

    // TODO: implement!
    // function testFork_VetoSignallingFlashLoan_RevertOn_SameAddress() external {}

    // TODO: implement!
    // function testFork_VetoSignallingFlashLoan_HappyPath_MultipleAddresses() external {}

    // ---
    // Helper external methods to test reverts
    // ---

    function externalLockUnstETH(address vetoer, uint256[] memory unstETHIds) external {
        _lockUnstETH(vetoer, unstETHIds);
    }

    function externalLockStETH(address vetoer, uint256 stEthAmount) external {
        _lockStETH(vetoer, stEthAmount);
    }

    function externalLockWstETH(address vetoer, uint256 wstEthAmount) external {
        _lockWstETH(vetoer, wstEthAmount);
    }

    function externalUnlockStETH(address vetoer) external {
        _unlockStETH(vetoer);
    }

    function externalUnlockWstETH(address vetoer) external {
        _unlockWstETH(vetoer);
    }

    function externalUnlockUnstETH(address vetoer, uint256[] memory nftIds) external {
        _unlockUnstETH(vetoer, nftIds);
    }
}
