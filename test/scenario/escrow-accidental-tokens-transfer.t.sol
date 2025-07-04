// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";
import {State} from "contracts/libraries/EscrowState.sol";
import {AssetsAccounting, UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";
import {ExternalCall} from "contracts/libraries/ExecutableProposals.sol";
import {Escrow} from "contracts/Escrow.sol";

import {LidoUtils, DGScenarioTestSetup} from "../utils/integration-tests.sol";

uint256 constant ACCURACY = 2 wei;
uint256 constant WITHDRAWALS_BATCH_SIZE = 128;
uint256 constant POOL_ACCUMULATED_ERROR = 150 wei;

contract EscrowAccidentalTokensTransferScenarioTest is DGScenarioTestSetup {
    using LidoUtils for LidoUtils.Context;

    Escrow internal escrow;

    address internal immutable _VETOER_1 = makeAddr("VETOER_1");
    address internal immutable _VETOER_2 = makeAddr("VETOER_2");
    address internal immutable _VETOER_3 = makeAddr("VETOER_3");
    uint256 internal _proposalId;
    uint256 internal transferredEthAmount = 10 ether;
    uint256[] internal vetoer3UnstETHIds;

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});

        escrow = Escrow(payable(address(_getVetoSignallingEscrow())));

        _setupStETHBalance(_VETOER_1, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(20_00));
        _setupWstETHBalance(_VETOER_1, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));

        vm.startPrank(_VETOER_1);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        vm.stopPrank();

        _setupStETHBalance(_VETOER_2, PercentsD16.fromBasisPoints(10_00));
        _setupWstETHBalance(_VETOER_2, 100 ether);

        vm.startPrank(_VETOER_2);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        vm.stopPrank();

        _setupStETHBalance(_VETOER_3, 500 ether);
        _setupWstETHBalance(_VETOER_3, 50 ether);

        vm.startPrank(_VETOER_3);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        vm.stopPrank();
    }

    function testFork_AccidentallyTransferredTokens_MayNotBeUnlocked_From_VetoSignallingEscrow() external {
        uint256 vetoer1LockedStEthShares = 6 ether;
        uint256 vetoer1LockedWStEthAmount = 5 ether;
        uint256 vetoer1LockedUnStEthShares = 4 ether;
        uint256[] memory vetoer1UnstETHIds;

        uint256 vetoer2TransferredStEthShares = 3 ether;
        uint256 vetoer2TransferredWStEthAmount = 2 ether;
        uint256 vetoer2TransferredUnStEthShares = 1 ether;
        uint256[] memory vetoer2UnstETHIds;

        PercentD16 expectedRageQuitSupport = PercentsD16.fromFraction({
            numerator: _lido.stETH.getPooledEthByShares(
                vetoer1LockedStEthShares + vetoer1LockedWStEthAmount + vetoer1LockedUnStEthShares
            ),
            denominator: _lido.stETH.totalSupply()
        });

        _step("1. Vetoer1 locks funds in escrow");
        {
            _assertNormalState();

            vetoer1UnstETHIds =
                _getSingleUnstEth(_VETOER_1, _lido.stETH.getPooledEthByShares(vetoer1LockedUnStEthShares));
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer1UnstETHIds[0]), _VETOER_1);

            _lockStETH(_VETOER_1, _lido.stETH.getPooledEthByShares(vetoer1LockedStEthShares));
            _lockWstETH(_VETOER_1, vetoer1LockedWStEthAmount);
            _lockUnstETH(_VETOER_1, vetoer1UnstETHIds);

            _activateNextState();
            _assertNormalState();

            assertEq(escrow.getRageQuitSupport(), expectedRageQuitSupport);
            assertApproxEqAbs(
                _lido.stETH.balanceOf(address(escrow)),
                _lido.stETH.getPooledEthByShares(vetoer1LockedStEthShares + vetoer1LockedWStEthAmount),
                2 * ACCURACY
            );
            assertEq(_lido.wstETH.balanceOf(address(escrow)), 0);

            assertEq(_lido.withdrawalQueue.ownerOf(vetoer1UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer1UnstETHIds)[0].amountOfShares,
                vetoer1LockedUnStEthShares,
                ACCURACY
            );
        }

        _step(
            "2. Vetoer2 accidentally transfers stETH, wstETH and unstETH to VetoSignalling escrow (and some contract transfers there ETH during selfdestruct)"
        );
        {
            vetoer2UnstETHIds =
                _getSingleUnstEth(_VETOER_2, _lido.stETH.getPooledEthByShares(vetoer2TransferredUnStEthShares));
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer2UnstETHIds[0]), _VETOER_2);

            vm.startPrank(_VETOER_2);
            _lido.stETH.transferShares(address(escrow), vetoer2TransferredStEthShares);
            _lido.wstETH.transfer(address(escrow), vetoer2TransferredWStEthAmount);
            _lido.withdrawalQueue.transferFrom(_VETOER_2, address(escrow), vetoer2UnstETHIds[0]);
            vm.stopPrank();

            // The current Escrow implementation accepts ETH only from the WithdrawalQueue contract, so a direct transfer isn’t possible.
            // vm.deal() call here simulates a selfdestruct for simplicity.
            vm.deal(address(escrow), transferredEthAmount);

            _activateNextState();
            _assertNormalState();

            assertEq(escrow.getRageQuitSupport(), expectedRageQuitSupport);

            // Vetoer1's stETH + Vetoer1's wstETH + Vetoer2's stETH (transferred)
            uint256 expectedEscrowShares =
                vetoer1LockedStEthShares + vetoer1LockedWStEthAmount + vetoer2TransferredStEthShares;
            assertApproxEqAbs(_lido.stETH.sharesOf(address(escrow)), expectedEscrowShares, ACCURACY);
            assertEq(_lido.wstETH.balanceOf(address(escrow)), vetoer2TransferredWStEthAmount);
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer2UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer2UnstETHIds)[0].amountOfShares,
                vetoer2TransferredUnStEthShares,
                ACCURACY
            );
            assertEq(address(escrow).balance, transferredEthAmount);
        }

        _step("3. Positive rebase happened");
        {
            PercentD16 rebasePercent = PercentsD16.fromBasisPoints(100_01);
            _simulateRebase(rebasePercent);

            PercentD16 newExpectedRageQuitSupport = PercentsD16.fromFraction({
                numerator: _lido.stETH.getPooledEthByShares(
                    vetoer1LockedStEthShares + vetoer1LockedWStEthAmount + vetoer1LockedUnStEthShares
                ),
                denominator: _lido.stETH.totalSupply()
            });

            assertEq(escrow.getRageQuitSupport(), newExpectedRageQuitSupport);
            assertApproxEqAbs(
                _lido.stETH.sharesOf(address(escrow)),
                vetoer1LockedStEthShares + vetoer1LockedWStEthAmount + vetoer2TransferredStEthShares,
                ACCURACY
            );

            assertEq(_lido.wstETH.balanceOf(address(escrow)), vetoer2TransferredWStEthAmount);

            assertEq(_lido.withdrawalQueue.ownerOf(vetoer1UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer1UnstETHIds)[0].amountOfShares,
                vetoer1LockedUnStEthShares,
                ACCURACY
            );

            assertEq(_lido.withdrawalQueue.ownerOf(vetoer2UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer2UnstETHIds)[0].amountOfShares,
                vetoer2TransferredUnStEthShares,
                ACCURACY
            );
        }

        _step("4. Vetoer1 unlocks own funds from VetoSignalling escrow");
        {
            _assertNormalState();

            uint256 vetoer1BalanceBeforeUnlock = _lido.stETH.balanceOf(_VETOER_1);

            _wait(_getMinAssetsLockDuration().plusSeconds(1));
            _unlockStETH(_VETOER_1);
            _unlockUnstETH(_VETOER_1, vetoer1UnstETHIds);

            assertApproxEqAbs(
                // all locked stETH and wstETH was withdrawn as stETH
                vetoer1BalanceBeforeUnlock
                    + _lido.stETH.getPooledEthByShares(vetoer1LockedStEthShares + vetoer1LockedWStEthAmount),
                _lido.stETH.balanceOf(_VETOER_1),
                ACCURACY * 2 // wstETH lock adds rounding error
            );

            assertApproxEqAbs(_lido.stETH.sharesOf(address(escrow)), vetoer2TransferredStEthShares, ACCURACY);

            assertEq(_lido.wstETH.balanceOf(address(escrow)), vetoer2TransferredWStEthAmount);

            assertEq(_lido.withdrawalQueue.ownerOf(vetoer1UnstETHIds[0]), _VETOER_1);

            assertEq(_lido.withdrawalQueue.ownerOf(vetoer2UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer2UnstETHIds)[0].amountOfShares,
                vetoer2TransferredUnStEthShares,
                ACCURACY
            );
        }

        _step(
            "5. Vetoer2's accidentally transferred stETH, wStETH and unstETH are still in VetoSignalling escrow and cannot be unlocked (and transferred ETH as well)"
        );
        {
            _assertNormalState();

            assertEq(escrow.getRageQuitSupport(), PercentsD16.from(0));
            assertApproxEqAbs(
                _lido.stETH.balanceOf(address(escrow)),
                _lido.stETH.getPooledEthByShares(vetoer2TransferredStEthShares),
                ACCURACY
            );
            assertEq(_lido.wstETH.balanceOf(address(escrow)), vetoer2TransferredWStEthAmount);
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer2UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer2UnstETHIds)[0].amountOfShares,
                vetoer2TransferredUnStEthShares,
                ACCURACY
            );

            vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, 0));
            this.external__unlockStETH(_VETOER_2);

            vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, 0));
            this.external__unlockWstETH(_VETOER_2);

            vm.expectRevert(
                abi.encodeWithSelector(
                    AssetsAccounting.InvalidUnstETHStatus.selector, vetoer2UnstETHIds[0], UnstETHRecordStatus.NotLocked
                )
            );
            this.external__unlockUnstETH(_VETOER_2, vetoer2UnstETHIds);

            assertEq(address(escrow).balance, transferredEthAmount);
        }
    }

    function testFork_AccidentallyTransferredTokens_MayNotBeUnlocked_From_RageQuitEscrow() external {
        PercentD16 vetoer1StEthPercent = _getSecondSealRageQuitSupport() - PercentsD16.fromBasisPoints(50);
        uint256 lockedStEthShares = _lido.calcSharesFromPercentageOfTVL(vetoer1StEthPercent);
        uint256 lockedStEth = _lido.stETH.getPooledEthByShares(lockedStEthShares);
        uint256 lockedWStEth = _lido.calcSharesFromPercentageOfTVL(PercentsD16.fromBasisPoints(51));
        uint256 lockedUnStEthShares = 1 ether;
        uint256[] memory vetoer1UnstETHIds;

        uint256 transferredStEthShares = 100 ether;
        uint256 transferredWStEthAmount = 2 ether;
        uint256 transferredUnStEthShares = 1 ether;
        uint256[] memory vetoer2UnstETHIds;

        PercentD16 expectedRageQuitSupport = PercentsD16.fromFraction({
            numerator: lockedStEthShares + lockedWStEth + lockedUnStEthShares,
            denominator: _lido.stETH.getTotalShares()
        });

        _step("1. New proposal submission.");
        {
            _assertNormalState();

            ExternalCall[] memory calls = _getMockTargetRegularStaffCalls(3);

            _proposalId = _submitProposalByAdminProposer(calls, "DAO performs potentially dangerous action");
            _assertProposalSubmitted(_proposalId);
        }

        _step("2. Proposal scheduling.");
        {
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            _assertCanSchedule(_proposalId, true);

            _scheduleProposal(_proposalId);
            _assertProposalScheduled(_proposalId);
        }

        _step(
            "3. Vetoer2 accidentally transfers stETH, wstETH and unstETH to VetoSignalling escrow (and some contract transfers there ETH during selfdestruct)."
        );
        {
            vetoer2UnstETHIds = _getSingleUnstEth(_VETOER_2, _lido.stETH.getPooledEthByShares(transferredUnStEthShares));
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer2UnstETHIds[0]), _VETOER_2);

            vm.startPrank(_VETOER_2);
            _lido.stETH.transferShares(address(escrow), transferredStEthShares);
            _lido.wstETH.transfer(address(escrow), transferredWStEthAmount);
            _lido.withdrawalQueue.transferFrom(_VETOER_2, address(escrow), vetoer2UnstETHIds[0]);
            vm.stopPrank();

            // The current Escrow implementation accepts ETH only from the WithdrawalQueue contract, so a direct transfer isn’t possible.
            // vm.deal() call here simulates a selfdestruct for simplicity.
            vm.deal(address(escrow), transferredEthAmount);

            _activateNextState();
            _assertNormalState();

            assertEq(escrow.getRageQuitSupport(), PercentsD16.from(0));
            assertApproxEqAbs(_lido.stETH.sharesOf(address(escrow)), transferredStEthShares, ACCURACY);

            assertEq(_lido.wstETH.balanceOf(address(escrow)), transferredWStEthAmount);
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer2UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer2UnstETHIds)[0].amountOfShares,
                transferredUnStEthShares,
                ACCURACY
            );
            assertEq(address(escrow).balance, transferredEthAmount);
        }

        _step("4. Vetoer1 locks funds in escrow.");
        {
            _assertNormalState();

            vetoer1UnstETHIds = _getSingleUnstEth(_VETOER_1, _lido.stETH.getPooledEthByShares(lockedUnStEthShares));
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer1UnstETHIds[0]), _VETOER_1);

            _lockStETH(_VETOER_1, lockedStEth);
            _lockWstETH(_VETOER_1, lockedWStEth);
            _lockUnstETH(_VETOER_1, vetoer1UnstETHIds);
            _assertVetoSignalingState();

            assertEq(escrow.getRageQuitSupport(), expectedRageQuitSupport);

            // Vetoer1's stETH + Vetoer1's wstETH + Vetoer2's stETH (transferred)
            uint256 expectedEscrowShares = lockedStEthShares + lockedWStEth + transferredStEthShares;
            assertApproxEqAbs(_lido.stETH.sharesOf(address(escrow)), expectedEscrowShares, ACCURACY);

            assertEq(_lido.wstETH.balanceOf(address(escrow)), transferredWStEthAmount);

            assertEq(_lido.withdrawalQueue.ownerOf(vetoer1UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer1UnstETHIds)[0].amountOfShares,
                lockedUnStEthShares,
                ACCURACY
            );
        }

        _step("5. Transition to RageQuit.");
        {
            _wait(_getVetoSignallingDuration().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();
        }

        _step("6. Vetoer3 accidentally transfers stETH, wstETH and unstETH to RageQuitEscrow.");
        {
            // solhint-disable-next-line reentrancy
            vetoer3UnstETHIds = _getSingleUnstEth(_VETOER_3, _lido.stETH.getPooledEthByShares(lockedUnStEthShares));
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer3UnstETHIds[0]), _VETOER_3);

            vm.startPrank(_VETOER_3);
            _lido.stETH.transferShares(address(escrow), transferredStEthShares);
            _lido.wstETH.transfer(address(escrow), transferredWStEthAmount);
            _lido.withdrawalQueue.transferFrom(_VETOER_3, address(escrow), vetoer3UnstETHIds[0]);
            vm.stopPrank();

            // The current Escrow implementation accepts ETH only from the WithdrawalQueue contract, so a direct transfer isn’t possible.
            // vm.deal() call here simulates a selfdestruct for simplicity.
            vm.deal(address(escrow), address(escrow).balance + transferredEthAmount);

            _activateNextState();
            _assertRageQuitState();

            assertEq(escrow.getRageQuitSupport(), expectedRageQuitSupport);

            // Vetoer1's stETH + Vetoer1's wstETH + Vetoer2's stETH (transferred) + Vetoer3's stETH (transferred)
            uint256 expectedEscrowShares =
                lockedStEthShares + lockedWStEth + transferredStEthShares + transferredStEthShares;
            assertApproxEqAbs(_lido.stETH.sharesOf(address(escrow)), expectedEscrowShares, ACCURACY);

            assertEq(_lido.wstETH.balanceOf(address(escrow)), transferredWStEthAmount + transferredWStEthAmount);

            assertEq(_lido.withdrawalQueue.ownerOf(vetoer3UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer3UnstETHIds)[0].amountOfShares,
                lockedUnStEthShares,
                ACCURACY
            );

            assertEq(address(escrow).balance, 2 * transferredEthAmount);
        }

        uint256 totalWithdrawnETH;
        _step("7. Claiming withdrawals and end of Rage Quit.");
        {
            uint256 totalETHBefore = address(escrow).balance;
            uint256 totalLockedStETHBefore = _lido.stETH.balanceOf(address(escrow));

            _requestWithdrawals(escrow);

            while (_lido.withdrawalQueue.getLastRequestId() != _lido.withdrawalQueue.getLastFinalizedRequestId()) {
                _finalizeWithdrawalQueue();
            }

            while (escrow.getUnclaimedUnstETHIdsCount() > 0) {
                escrow.claimNextWithdrawalsBatch(WITHDRAWALS_BATCH_SIZE);
            }

            uint256 totalETHAfter = address(escrow).balance;
            uint256 totalLockedStETHAfter = _lido.stETH.balanceOf(address(escrow));
            totalWithdrawnETH = totalETHAfter - totalETHBefore;

            // During the RageQuit finalization of the batches each withdrawal NFT may loose 1-2 wei during
            // claiming due to share rate rounding error.
            assertApproxEqAbs(
                totalLockedStETHBefore - totalLockedStETHAfter, totalWithdrawnETH, 100 * POOL_ACCUMULATED_ERROR
            );

            escrow.startRageQuitExtensionPeriod();
        }

        _step("8. All Vetoer1's funds and Vetoer2,3's stETHs are converted to ETH and returned to Vetoer1.");
        {
            _wait(_getRageQuitExtensionPeriodDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoCooldownState();

            _wait(_getRageQuitEthWithdrawalsDelay().plusSeconds(1));

            uint256 vetoer1BalanceBefore = _VETOER_1.balance;

            // Vetoer1's stETH + Vetoer1's wstETH + Vetoer2's stETH (transferred) + Vetoer3's stETH (transferred)
            vm.startPrank(_VETOER_1);
            escrow.withdrawETH();
            vm.stopPrank();

            // Vetoer1's stETH + Vetoer1's wstETH + Vetoer2's stETH (transferred) + Vetoer3's stETH (transferred).
            // As Vetoer1 was the only one user locked funds it should receive all the funds after withdraw.
            assertApproxEqAbs(_VETOER_1.balance - vetoer1BalanceBefore, totalWithdrawnETH, POOL_ACCUMULATED_ERROR);

            _assertVetoCooldownState();
        }

        _step("9. Back to normal state.");
        {
            _activateNextState();
            _assertNormalState();
        }

        _step(
            "10. Vetoer2's and Vetoer3's accidentally transferred wStETH and unstETH are buried in RageQuitEscrow forever (and transferred ETH as well)."
        );
        {
            _assertNormalState();

            PercentD16 expectedRageQuitSupport = PercentsD16.fromFraction({
                numerator: lockedStEthShares + lockedWStEth + lockedUnStEthShares,
                denominator: _lido.stETH.getTotalShares()
            });

            assertEq(escrow.getRageQuitSupport(), expectedRageQuitSupport);
            assertApproxEqAbs(
                _lido.stETH.balanceOf(address(escrow)), 0, _lido.withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT()
            );
            assertEq(_lido.wstETH.balanceOf(address(escrow)), 2 * transferredWStEthAmount); // Vetoer2's + Vetoer3's wStETH
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer2UnstETHIds[0]), address(escrow));
            assertEq(_lido.withdrawalQueue.ownerOf(vetoer3UnstETHIds[0]), address(escrow));
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer2UnstETHIds)[0].amountOfShares,
                transferredUnStEthShares, // Vetoer2's unStETH
                ACCURACY
            );
            assertApproxEqAbs(
                _lido.withdrawalQueue.getWithdrawalStatus(vetoer3UnstETHIds)[0].amountOfShares,
                transferredUnStEthShares, // Vetoer3's unStETH
                ACCURACY
            );

            assertNotEq(address(escrow), address(_getVetoSignallingEscrow())); // escrow address is not equal to the actual VetoSignalling escrow instance
            assert(escrow.getEscrowState() == State.RageQuitEscrow); // and it's forever in RageQuit state, so tokens unlock is not possible

            assertEq(address(escrow).balance, 2 * transferredEthAmount);
        }
    }

    function _getSingleUnstEth(address vetoer, uint256 amount) internal returns (uint256[] memory unstETHIds) {
        uint256[] memory nftAmounts = new uint256[](1);
        nftAmounts[0] = amount;

        vm.prank(vetoer);
        unstETHIds = _lido.withdrawalQueue.requestWithdrawals(nftAmounts, vetoer);
    }

    function _requestWithdrawals(Escrow escrowInstance) internal {
        uint256 iteration = 0;
        uint256 maxIterations = 100;
        while (!escrowInstance.isWithdrawalsBatchesClosed()) {
            if (iteration > maxIterations) {
                console.log("maxIterations exceeded while requesting withdrawals", iteration);
                break;
            }
            escrowInstance.requestNextWithdrawalsBatch(100);

            iteration++;
        }
    }
}
