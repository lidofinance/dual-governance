// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {WithdrawalRequestStatus} from "../utils/interfaces.sol";
import {Duration as DurationType} from "contracts/types/Duration.sol";
import {
    Escrow,
    Balances,
    VetoerState,
    LockedAssetsTotals,
    WITHDRAWAL_QUEUE,
    ScenarioTestBlueprint,
    Durations
} from "../utils/scenario-test-blueprint.sol";

contract TestHelpers is ScenarioTestBlueprint {
    function rebase(int256 deltaBP) public {
        bytes32 CL_BALANCE_POSITION = 0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483; // keccak256("lido.Lido.beaconBalance");

        uint256 totalSupply = _ST_ETH.totalSupply();
        uint256 clBalance = uint256(vm.load(address(_ST_ETH), CL_BALANCE_POSITION));

        int256 delta = (deltaBP * int256(totalSupply) / 10000);
        vm.store(address(_ST_ETH), CL_BALANCE_POSITION, bytes32(uint256(int256(clBalance) + delta)));

        assertEq(
            uint256(int256(totalSupply) * deltaBP / 10000 + int256(totalSupply)), _ST_ETH.totalSupply(), "total supply"
        );
    }

    function finalizeWQ() public {
        uint256 lastRequestId = _WITHDRAWAL_QUEUE.getLastRequestId();
        finalizeWQ(lastRequestId);
    }

    function finalizeWQ(uint256 id) public {
        uint256 finalizationShareRate = _ST_ETH.getPooledEthByShares(1e27) + 1e9; // TODO check finalization rate
        address lido = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        vm.prank(lido);
        _WITHDRAWAL_QUEUE.finalize(id, finalizationShareRate);

        bytes32 LOCKED_ETHER_AMOUNT_POSITION = 0x0e27eaa2e71c8572ab988fef0b54cd45bbd1740de1e22343fb6cda7536edc12f; // keccak256("lido.WithdrawalQueue.lockedEtherAmount");

        vm.store(WITHDRAWAL_QUEUE, LOCKED_ETHER_AMOUNT_POSITION, bytes32(address(WITHDRAWAL_QUEUE).balance));
    }
}

contract EscrowHappyPath is TestHelpers {
    Escrow internal escrow;

    DurationType internal immutable _RAGE_QUIT_EXTRA_TIMELOCK = Durations.from(14 days);
    DurationType internal immutable _RAGE_QUIT_WITHDRAWALS_TIMELOCK = Durations.from(7 days);

    address internal immutable _VETOER_1 = makeAddr("VETOER_1");
    address internal immutable _VETOER_2 = makeAddr("VETOER_2");

    Balances internal _firstVetoerBalances;
    Balances internal _secondVetoerBalances;

    function setUp() external {
        _selectFork();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);

        escrow = _getVetoSignallingEscrow();

        _setupStETHWhale(_VETOER_1);
        vm.startPrank(_VETOER_1);
        _ST_ETH.approve(address(_WST_ETH), type(uint256).max);
        _ST_ETH.approve(address(escrow), type(uint256).max);
        _ST_ETH.approve(address(_WITHDRAWAL_QUEUE), type(uint256).max);
        _WST_ETH.approve(address(escrow), type(uint256).max);

        _WST_ETH.wrap(100_000 * 10 ** 18);
        vm.stopPrank();

        _setupStETHWhale(_VETOER_2);
        vm.startPrank(_VETOER_2);
        _ST_ETH.approve(address(_WST_ETH), type(uint256).max);
        _ST_ETH.approve(address(escrow), type(uint256).max);
        _ST_ETH.approve(address(_WITHDRAWAL_QUEUE), type(uint256).max);
        _WST_ETH.approve(address(escrow), type(uint256).max);

        _WST_ETH.wrap(100_000 * 10 ** 18);
        vm.stopPrank();

        _firstVetoerBalances = _getBalances(_VETOER_1);
        _secondVetoerBalances = _getBalances(_VETOER_2);
    }

    function test_lock_unlock() public {
        uint256 firstVetoerStETHBalanceBefore = _ST_ETH.balanceOf(_VETOER_1);
        uint256 firstVetoerWstETHBalanceBefore = _WST_ETH.balanceOf(_VETOER_1);

        uint256 secondVetoerStETHBalanceBefore = _ST_ETH.balanceOf(_VETOER_2);
        uint256 secondVetoerWstETHBalanceBefore = _WST_ETH.balanceOf(_VETOER_2);

        _lockStETH(_VETOER_1, 10 ** 18);
        _lockWstETH(_VETOER_1, 2 * 10 ** 18);

        _lockStETH(_VETOER_2, 3 * 10 ** 18);
        _lockWstETH(_VETOER_2, 5 * 10 ** 18);

        _wait(_config.SIGNALLING_ESCROW_MIN_LOCK_TIME().plusSeconds(1));

        _unlockStETH(_VETOER_1);
        _unlockWstETH(_VETOER_1);
        _unlockStETH(_VETOER_2);
        _unlockWstETH(_VETOER_2);

        assertEq(firstVetoerWstETHBalanceBefore, _WST_ETH.balanceOf(_VETOER_1));
        assertApproxEqAbs(firstVetoerStETHBalanceBefore, _ST_ETH.balanceOf(_VETOER_1), 1);

        assertEq(secondVetoerWstETHBalanceBefore, _WST_ETH.balanceOf(_VETOER_2));
        assertApproxEqAbs(secondVetoerStETHBalanceBefore, _ST_ETH.balanceOf(_VETOER_2), 1);
    }

    function test_lock_unlock_w_rebase() public {
        uint256 firstVetoerStETHAmount = 10 * 10 ** 18;
        uint256 firstVetoerStETHShares = _ST_ETH.getSharesByPooledEth(firstVetoerStETHAmount);
        uint256 firstVetoerWstETHAmount = 11 * 10 ** 18;

        uint256 secondVetoerStETHAmount = 13 * 10 ** 18;
        uint256 secondVetoerStETHShares = _ST_ETH.getSharesByPooledEth(secondVetoerStETHAmount);
        uint256 secondVetoerWstETHAmount = 17 * 10 ** 18;

        _lockStETH(_VETOER_1, firstVetoerStETHAmount);
        _lockWstETH(_VETOER_1, firstVetoerWstETHAmount);

        _lockStETH(_VETOER_2, secondVetoerStETHAmount);
        _lockWstETH(_VETOER_2, secondVetoerWstETHAmount);

        rebase(100);

        uint256 firstVetoerStETHSharesAfterRebase = _ST_ETH.sharesOf(_VETOER_1);
        uint256 firstVetoerWstETHBalanceAfterRebase = _WST_ETH.balanceOf(_VETOER_1);

        uint256 secondVetoerStETHSharesAfterRebase = _ST_ETH.sharesOf(_VETOER_2);
        uint256 secondVetoerWstETHBalanceAfterRebase = _WST_ETH.balanceOf(_VETOER_2);

        _wait(_config.SIGNALLING_ESCROW_MIN_LOCK_TIME().plusSeconds(1));

        _unlockStETH(_VETOER_1);
        _unlockWstETH(_VETOER_1);

        _unlockStETH(_VETOER_2);
        _unlockWstETH(_VETOER_2);

        assertApproxEqAbs(
            _ST_ETH.getPooledEthByShares(firstVetoerStETHSharesAfterRebase + firstVetoerStETHShares),
            _ST_ETH.balanceOf(_VETOER_1),
            1
        );
        assertEq(firstVetoerWstETHBalanceAfterRebase + firstVetoerWstETHAmount, _WST_ETH.balanceOf(_VETOER_1));

        assertApproxEqAbs(
            _ST_ETH.getPooledEthByShares(secondVetoerStETHSharesAfterRebase + secondVetoerStETHShares),
            _ST_ETH.balanceOf(_VETOER_2),
            1
        );
        assertEq(secondVetoerWstETHBalanceAfterRebase + secondVetoerWstETHAmount, _WST_ETH.balanceOf(_VETOER_2));
    }

    function test_lock_unlock_w_negative_rebase() public {
        uint256 firstVetoerStETHAmount = 10 * 10 ** 18;
        uint256 firstVetoerWstETHAmount = 11 * 10 ** 18;

        uint256 secondVetoerStETHAmount = 13 * 10 ** 18;
        uint256 secondVetoerWstETHAmount = 17 * 10 ** 18;

        uint256 firstVetoerStETHSharesBefore = _ST_ETH.sharesOf(_VETOER_1);
        uint256 firstVetoerWstETHBalanceBefore = _WST_ETH.balanceOf(_VETOER_1);

        uint256 secondVetoerStETHSharesBefore = _ST_ETH.sharesOf(_VETOER_2);
        uint256 secondVetoerWstETHBalanceBefore = _WST_ETH.balanceOf(_VETOER_2);

        _lockStETH(_VETOER_1, firstVetoerStETHAmount);
        _lockWstETH(_VETOER_1, firstVetoerWstETHAmount);

        _lockStETH(_VETOER_2, secondVetoerStETHAmount);
        _lockWstETH(_VETOER_2, secondVetoerWstETHAmount);

        rebase(-100);

        _wait(_config.SIGNALLING_ESCROW_MIN_LOCK_TIME().plusSeconds(1));

        _unlockStETH(_VETOER_1);
        _unlockWstETH(_VETOER_1);

        _unlockStETH(_VETOER_2);
        _unlockWstETH(_VETOER_2);

        assertApproxEqAbs(_ST_ETH.getPooledEthByShares(firstVetoerStETHSharesBefore), _ST_ETH.balanceOf(_VETOER_1), 1);
        assertEq(firstVetoerWstETHBalanceBefore, _WST_ETH.balanceOf(_VETOER_1));

        assertApproxEqAbs(_ST_ETH.getPooledEthByShares(secondVetoerStETHSharesBefore), _ST_ETH.balanceOf(_VETOER_2), 1);
        assertEq(secondVetoerWstETHBalanceBefore, _WST_ETH.balanceOf(_VETOER_2));
    }

    function test_lock_unlock_withdrawal_nfts() public {
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _WITHDRAWAL_QUEUE.requestWithdrawals(amounts, _VETOER_1);

        _lockUnstETH(_VETOER_1, unstETHIds);

        _wait(_config.SIGNALLING_ESCROW_MIN_LOCK_TIME().plusSeconds(1));

        _unlockUnstETH(_VETOER_1, unstETHIds);
    }

    function test_lock_withdrawal_nfts_reverts_on_finalized() public {
        uint256[] memory amounts = new uint256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _WITHDRAWAL_QUEUE.requestWithdrawals(amounts, _VETOER_1);

        finalizeWQ();

        vm.expectRevert();
        this.externalLockUnstETH(_VETOER_1, unstETHIds);
    }

    function test_check_finalization() public {
        uint256 totalSharesLocked = _ST_ETH.getSharesByPooledEth(2 * 1e18);
        uint256 expectedSharesFinalized = _ST_ETH.getSharesByPooledEth(1 * 1e18);
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _WITHDRAWAL_QUEUE.requestWithdrawals(amounts, _VETOER_1);

        _lockUnstETH(_VETOER_1, unstETHIds);

        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).unstETHShares, totalSharesLocked, 1);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().shares, totalSharesLocked, 1);
        assertEq(escrow.getLockedAssetsTotals().sharesFinalized, 0);

        finalizeWQ(unstETHIds[0]);
        uint256[] memory hints =
            _WITHDRAWAL_QUEUE.findCheckpointHints(unstETHIds, 1, _WITHDRAWAL_QUEUE.getLastCheckpointIndex());
        escrow.markUnstETHFinalized(unstETHIds, hints);

        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).unstETHShares, totalSharesLocked, 1);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().shares, totalSharesLocked, 1);

        assertApproxEqAbs(escrow.getLockedAssetsTotals().sharesFinalized, expectedSharesFinalized, 1);
        uint256 ethAmountFinalized = _WITHDRAWAL_QUEUE.getClaimableEther(unstETHIds, hints)[0];
        assertApproxEqAbs(escrow.getLockedAssetsTotals().amountFinalized, ethAmountFinalized, 1);
    }

    function test_get_rage_quit_support() public {
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        uint256 totalSupply = _ST_ETH.totalSupply();

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _WITHDRAWAL_QUEUE.requestWithdrawals(amounts, _VETOER_1);

        uint256 amountToLock = 1e18;
        uint256 sharesToLock = _ST_ETH.getSharesByPooledEth(amountToLock);

        _lockStETH(_VETOER_1, amountToLock);
        _lockWstETH(_VETOER_1, sharesToLock);
        _lockUnstETH(_VETOER_1, unstETHIds);

        VetoerState memory vetoerState = escrow.getVetoerState(_VETOER_1);
        assertApproxEqAbs(vetoerState.stETHShares, sharesToLock, 1);
        assertEq(vetoerState.wstETHShares, sharesToLock);
        assertApproxEqAbs(vetoerState.unstETHShares, _ST_ETH.getSharesByPooledEth(2e18), 1);

        uint256 rageQuitSupport = escrow.getRageQuitSupport();
        assertEq(rageQuitSupport, 4 * 1e18 * 1e18 / totalSupply);

        finalizeWQ(unstETHIds[0]);
        uint256[] memory hints =
            _WITHDRAWAL_QUEUE.findCheckpointHints(unstETHIds, 1, _WITHDRAWAL_QUEUE.getLastCheckpointIndex());
        escrow.markUnstETHFinalized(unstETHIds, hints);

        LockedAssetsTotals memory totals = escrow.getLockedAssetsTotals();

        assertApproxEqAbs(totals.sharesFinalized, sharesToLock, 1);
        uint256 ethAmountFinalized = _WITHDRAWAL_QUEUE.getClaimableEther(unstETHIds, hints)[0];
        assertApproxEqAbs(totals.amountFinalized, ethAmountFinalized, 1);

        rageQuitSupport = escrow.getRageQuitSupport();
        assertEq(
            rageQuitSupport,
            10 ** 18 * (_ST_ETH.getPooledEthByShares(3 * sharesToLock) + ethAmountFinalized)
                / (_ST_ETH.totalSupply() + ethAmountFinalized)
        );
    }

    function test_rage_quit() public {
        uint256 requestAmount = 1000 * 1e18;
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            amounts[i] = requestAmount;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _WITHDRAWAL_QUEUE.requestWithdrawals(amounts, _VETOER_1);

        uint256 requestShares = _ST_ETH.getSharesByPooledEth(30 * requestAmount);

        _lockStETH(_VETOER_1, 20 * requestAmount);
        _lockWstETH(_VETOER_1, requestShares);
        _lockUnstETH(_VETOER_1, unstETHIds);

        rebase(100);

        vm.expectRevert();
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        vm.prank(address(_dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        uint256 escrowStETHBalance = _ST_ETH.balanceOf(address(escrow));
        uint256 expectedWithdrawalBatchesCount = escrowStETHBalance / requestAmount + 1;
        assertEq(_WITHDRAWAL_QUEUE.balanceOf(address(escrow)), 10);

        escrow.requestNextWithdrawalsBatch(10);

        assertEq(_WITHDRAWAL_QUEUE.balanceOf(address(escrow)), 20);

        escrow.requestNextWithdrawalsBatch(200);

        assertEq(_WITHDRAWAL_QUEUE.balanceOf(address(escrow)), 10 + expectedWithdrawalBatchesCount);
        assertEq(escrow.isRageQuitFinalized(), false);

        vm.deal(WITHDRAWAL_QUEUE, 1000 * requestAmount);
        finalizeWQ();

        (uint256 offset, uint256 total, uint256[] memory unstETHIdsToClaim) =
            escrow.getNextWithdrawalBatches(expectedWithdrawalBatchesCount);
        assertEq(total, expectedWithdrawalBatchesCount);

        WithdrawalRequestStatus[] memory statuses = _WITHDRAWAL_QUEUE.getWithdrawalStatus(unstETHIdsToClaim);

        for (uint256 i = 0; i < statuses.length; ++i) {
            assertTrue(statuses[i].isFinalized);
            assertFalse(statuses[i].isClaimed);
        }

        uint256[] memory hints =
            _WITHDRAWAL_QUEUE.findCheckpointHints(unstETHIdsToClaim, 1, _WITHDRAWAL_QUEUE.getLastCheckpointIndex());

        escrow.claimNextWithdrawalsBatch(offset, hints);

        assertEq(escrow.isRageQuitFinalized(), false);

        // ---
        // unstETH holders claim their withdrawal requests
        // ---
        {
            uint256[] memory hints =
                _WITHDRAWAL_QUEUE.findCheckpointHints(unstETHIds, 1, _WITHDRAWAL_QUEUE.getLastCheckpointIndex());
            escrow.claimUnstETH(unstETHIds, hints);

            // but it can't be withdrawn before withdrawal timelock has passed
            vm.expectRevert();
            vm.prank(_VETOER_1);
            escrow.withdrawUnstETHAsETH(unstETHIds);
        }

        vm.expectRevert();
        vm.prank(_VETOER_1);
        escrow.withdrawStETHAsETH();

        _wait(_RAGE_QUIT_EXTRA_TIMELOCK.plusSeconds(1));
        assertEq(escrow.isRageQuitFinalized(), true);

        _wait(_RAGE_QUIT_WITHDRAWALS_TIMELOCK.plusSeconds(1));

        vm.startPrank(_VETOER_1);
        escrow.withdrawStETHAsETH();
        escrow.withdrawUnstETHAsETH(unstETHIds);
        vm.stopPrank();
    }

    function test_wq_requests_only_happy_path() public {
        uint256 requestAmount = 10 * 1e18;
        uint256 requestsCount = 10;
        uint256[] memory amounts = new uint256[](requestsCount);
        for (uint256 i = 0; i < requestsCount; ++i) {
            amounts[i] = requestAmount;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _WITHDRAWAL_QUEUE.requestWithdrawals(amounts, _VETOER_1);

        _lockUnstETH(_VETOER_1, unstETHIds);

        vm.prank(address(_dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        vm.deal(WITHDRAWAL_QUEUE, 100 * requestAmount);
        finalizeWQ();

        escrow.claimNextWithdrawalsBatch(0, new uint256[](0));

        assertEq(escrow.isRageQuitFinalized(), false);

        uint256[] memory hints =
            _WITHDRAWAL_QUEUE.findCheckpointHints(unstETHIds, 1, _WITHDRAWAL_QUEUE.getLastCheckpointIndex());

        escrow.claimUnstETH(unstETHIds, hints);

        assertEq(escrow.isRageQuitFinalized(), false);

        _wait(_RAGE_QUIT_EXTRA_TIMELOCK.plusSeconds(1));
        assertEq(escrow.isRageQuitFinalized(), true);

        _wait(_RAGE_QUIT_WITHDRAWALS_TIMELOCK.plusSeconds(1));

        vm.startPrank(_VETOER_1);
        escrow.withdrawUnstETHAsETH(unstETHIds);
        vm.stopPrank();
    }

    function test_request_st_eth_wst_eth_withdrawals() external {
        uint256 firstVetoerStETHAmount = 10 ether;
        uint256 firstVetoerWstETHAmount = 11 ether;

        uint256 firstVetoerStETHShares = _ST_ETH.getSharesByPooledEth(firstVetoerStETHAmount);
        uint256 totalSharesLocked = firstVetoerWstETHAmount + firstVetoerStETHShares;

        _lockStETH(_VETOER_1, firstVetoerStETHAmount);
        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).stETHShares, firstVetoerStETHShares, 1);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().shares, firstVetoerStETHShares, 1);

        _lockWstETH(_VETOER_1, firstVetoerWstETHAmount);
        assertEq(escrow.getVetoerState(_VETOER_1).wstETHShares, firstVetoerWstETHAmount);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().shares, totalSharesLocked, 1);

        _wait(_config.SIGNALLING_ESCROW_MIN_LOCK_TIME().plusSeconds(1));

        uint256[] memory stETHWithdrawalRequestAmounts = new uint256[](1);
        stETHWithdrawalRequestAmounts[0] = firstVetoerStETHAmount;

        vm.prank(_VETOER_1);
        uint256[] memory stETHWithdrawalRequestIds = escrow.requestWithdrawalsStETH(stETHWithdrawalRequestAmounts);

        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).unstETHShares, firstVetoerStETHShares, 1);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().shares, totalSharesLocked, 1);

        uint256[] memory wstETHWithdrawalRequestAmounts = new uint256[](1);
        wstETHWithdrawalRequestAmounts[0] = firstVetoerWstETHAmount;

        vm.prank(_VETOER_1);
        uint256[] memory wstETHWithdrawalRequestIds = escrow.requestWithdrawalsWstETH(wstETHWithdrawalRequestAmounts);

        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).unstETHShares, totalSharesLocked, 1);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().shares, totalSharesLocked, 1);

        finalizeWQ(wstETHWithdrawalRequestIds[0]);

        escrow.markUnstETHFinalized(
            stETHWithdrawalRequestIds,
            _WITHDRAWAL_QUEUE.findCheckpointHints(
                stETHWithdrawalRequestIds, 1, _WITHDRAWAL_QUEUE.getLastCheckpointIndex()
            )
        );
        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).unstETHShares, totalSharesLocked, 1);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().shares, totalSharesLocked, 1);

        escrow.markUnstETHFinalized(
            wstETHWithdrawalRequestIds,
            _WITHDRAWAL_QUEUE.findCheckpointHints(
                wstETHWithdrawalRequestIds, 1, _WITHDRAWAL_QUEUE.getLastCheckpointIndex()
            )
        );
        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).unstETHShares, totalSharesLocked, 1);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().shares, totalSharesLocked, 1);

        _wait(_config.SIGNALLING_ESCROW_MIN_LOCK_TIME().plusSeconds(1));

        vm.prank(_VETOER_1);
        escrow.unlockUnstETH(stETHWithdrawalRequestIds);

        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).unstETHShares, firstVetoerWstETHAmount, 1);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().shares, firstVetoerWstETHAmount, 1);

        vm.prank(_VETOER_1);
        escrow.unlockUnstETH(wstETHWithdrawalRequestIds);
    }

    function externalLockUnstETH(address vetoer, uint256[] memory unstETHIds) external {
        _lockUnstETH(vetoer, unstETHIds);
    }
}
