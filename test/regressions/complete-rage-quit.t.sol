// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";
import {PercentsD16, PercentD16} from "contracts/types/PercentD16.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";
import {DGRegressionTestSetup, ExternalCall, MAINNET_CHAIN_ID, HOLESKY_CHAIN_ID} from "../utils/integration-tests.sol";
import {LidoUtils, MAINNET_ST_ETH, HOLESKY_ST_ETH} from "../utils/lido-utils.sol";

uint256 constant ACCURACY = 2 wei;
uint256 constant GAS_COST_PER_VETOER = 10000 wei;
uint256 constant MAX_WITHDRAWALS_REQUESTS_ITERATIONS = 1000;
uint256 constant WITHDRAWALS_BATCH_SIZE = 128;
uint256 constant MIN_LOCKABLE_AMOUNT = 1000 wei;

struct VetoersFile {
    address[] addresses;
}

contract CompleteRageQuitRegressionTest is DGRegressionTestSetup {
    using LidoUtils for LidoUtils.Context;

    address private _stEthAccumulator = makeAddr("stEthAccumulator");
    uint8 private _round = 1;
    uint256 private _lastVetoerIndex;
    uint256 private _wqStEthSharesBalanceBeforeVeto;
    address[] private _allVetoers;

    function setUp() external {
        _loadOrDeployDGSetup();
    }

    function testFork_RageQuit4Rounds() external {
        console.log("-------------------------");

        if (
            (block.chainid == MAINNET_CHAIN_ID && address(_lido.stETH) != MAINNET_ST_ETH)
                || (block.chainid == HOLESKY_CHAIN_ID && address(_lido.stETH) != HOLESKY_ST_ETH)
        ) {
            vm.skip(true, "This test is not intended to be run with the custom StETH token implementation");
            return;
        }

        if (!vm.envOr("ENABLE_REGRESSION_TEST_COMPLETE_RAGE_QUIT", false)) {
            vm.skip(
                true,
                "To enable this test set the env variable ENABLE_REGRESSION_TEST_COMPLETE_RAGE_QUIT=true and FORK_BLOCK_NUMBER=21888569"
            );
            return;
        }

        _allVetoers = _loadAllVetoers(
            "./test/regressions/complete-rage-quit-files/steth_vetoers.json",
            "./test/regressions/complete-rage-quit-files/wsteth_vetoers.json"
        );

        console.log("Vetoers total amount:", _allVetoers.length);
        uint256 initialStEthTotalSupply = _lido.stETH.totalSupply();
        uint256 initialWStEthTotalSupply = _lido.wstETH.totalSupply();
        console.log("stETH.totalSupply:", initialStEthTotalSupply); // 9412932 836416502570056992
        console.log("wstETH.totalSupply:", initialWStEthTotalSupply); // 3385963 793830217485442500

        PercentD16 rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00);
        uint256 stEthRQAmount = _lido.calcAmountToDepositFromPercentageOfTVL(rageQuitSecondBoundary);

        console.log("Need to lock stEth for RQ:", stEthRQAmount); // 1792939 587888857632391808

        _newRageQuitRound(1);
        address[] memory vetoers = _selectVetoers();
        _executeRQ(vetoers);

        rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00);
        stEthRQAmount = _lido.calcAmountToDepositFromPercentageOfTVL(rageQuitSecondBoundary);

        console.log("Need to lock stEth for RQ:", stEthRQAmount); // 1451834 210703472798914832
        console.log("stETH.totalSupply:", _lido.stETH.totalSupply()); // 7622129 606193232146664563

        _newRageQuitRound(2);
        vetoers = _selectVetoers();
        _executeRQ(vetoers);

        rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00);
        stEthRQAmount = _lido.calcAmountToDepositFromPercentageOfTVL(rageQuitSecondBoundary);

        console.log("Need to lock stEth for RQ:", stEthRQAmount); // 1174996 087470854335619031
        console.log("stETH.totalSupply:", _lido.stETH.totalSupply()); // 6168729 459221985223445357

        _newRageQuitRound(3);
        vetoers = _selectVetoers();
        _executeRQ(vetoers);

        rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00);
        stEthRQAmount = _lido.calcAmountToDepositFromPercentageOfTVL(rageQuitSecondBoundary);

        console.log("Need to lock stEth for RQ:", stEthRQAmount); //  894328 020726050817318346
        console.log("stETH.totalSupply:", _lido.stETH.totalSupply()); // 4695222 108811766761576182

        _newRageQuitRound(4);
        vetoers = _selectVetoers();
        _executeRQ(vetoers);

        console.log("-------------------------");

        console.log("stETH.totalSupply:", _lido.stETH.totalSupply()); // 3 196 223 799735673133154851; Exited 66,04434198% of StETH
        console.log(
            "stETH total supply decreased for %s%", 100 - _lido.stETH.totalSupply() * 100 / initialStEthTotalSupply
        );
        console.log("wstETH.totalSupply:", _lido.wstETH.totalSupply()); // 120 979 393309171244779927; Exited 96,42704306% of WStETH
        console.log(
            "wstETH total supply decreased for %s%", 100 - _lido.wstETH.totalSupply() * 100 / initialWStEthTotalSupply
        );
    }

    function _selectVetoers() internal returns (address[] memory vetoers) {
        _step(_stepMsg("0. Balances preparation."));
        uint256 lastVetoerIndexForCurrentRound = _findLastVetoerIndexForRQ(_allVetoers, _lastVetoerIndex);
        uint256 vetoersCount = lastVetoerIndexForCurrentRound - _lastVetoerIndex;
        console.log("Vetoers for round %s: %s", _round, vetoersCount);

        vetoers = new address[](vetoersCount);

        uint256 j;
        for (uint256 i = _lastVetoerIndex; i < lastVetoerIndexForCurrentRound; ++i) {
            vetoers[j] = _prepareVetoer(_allVetoers[i], i);
            ++j;
        }
        _lastVetoerIndex = lastVetoerIndexForCurrentRound;
    }

    function _executeRQ(address[] memory vetoers) internal {
        uint256 proposalId;
        uint256[] memory vetoersStEthBalancesBefore = new uint256[](vetoers.length);
        uint256[] memory vetoersBalancesBefore = new uint256[](vetoers.length);

        _step(_stepMsg("1. New proposal submission."));
        {
            _assertNormalState();
            _assertCanSubmitProposal(true);

            ExternalCall[] memory calls = _getMockTargetRegularStaffCalls(3);

            proposalId = _submitProposalByAdminProposer(calls, "DAO performs potentially dangerous action");
            _assertProposalSubmitted(proposalId);
        }

        _step(_stepMsg("2. Proposal scheduling."));
        {
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            _assertCanSchedule(proposalId, true);

            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);
        }

        _step(_stepMsg("3. StETH holders veto."));
        {
            _assertNormalState();
            _wqStEthSharesBalanceBeforeVeto = _lido.stETH.sharesOf(address(_lido.withdrawalQueue));

            for (uint256 i = 0; i < vetoers.length; ++i) {
                uint256 vetoerStEthBalance = _lido.stETH.balanceOf(vetoers[i]);
                uint256 vetoerWStEthBalance = _lido.wstETH.balanceOf(vetoers[i]);

                if (vetoerStEthBalance < MIN_LOCKABLE_AMOUNT) {
                    vetoerStEthBalance = 0;
                }

                if (vetoerWStEthBalance < MIN_LOCKABLE_AMOUNT) {
                    vetoerWStEthBalance = 0;
                }

                vetoersBalancesBefore[i] = vetoers[i].balance;
                vetoersStEthBalancesBefore[i] = vetoerStEthBalance + _lido.wstETH.getStETHByWstETH(vetoerWStEthBalance);

                if (vetoerStEthBalance > 0) {
                    _lockStETH(vetoers[i], vetoerStEthBalance);
                }

                if (vetoerWStEthBalance > 0) {
                    _lockWstETH(vetoers[i], vetoerWStEthBalance);
                }
            }

            ISignallingEscrow vsEscrow = _getVetoSignallingEscrow();
            console.log("RQ support(%):", vsEscrow.getRageQuitSupport().toUint256() / 10 ** 16);

            _assertVetoSignalingState();
        }

        _step(_stepMsg("4. Transition to Rage Quit."));
        {
            _wait(_getVetoSignallingDuration().plusSeconds(1));

            _activateNextState();

            _assertRageQuitState();
        }

        _step(_stepMsg("5. Claiming withdrawals."));
        {
            IRageQuitEscrow rqEscrow = _getRageQuitEscrow();

            uint256 iteration = 0;
            while (!rqEscrow.isWithdrawalsBatchesClosed()) {
                if (iteration > MAX_WITHDRAWALS_REQUESTS_ITERATIONS) {
                    console.log(
                        "Max allowed withdrawals requests iterations (%s) exceeded", MAX_WITHDRAWALS_REQUESTS_ITERATIONS
                    );
                    break;
                }

                rqEscrow.requestNextWithdrawalsBatch(
                    _dgDeployConfig.dualGovernance.sanityCheckParams.minWithdrawalsBatchSize
                );
                iteration++;
            }

            _finalizeWithdrawalQueue();

            _burnStEth(_wqStEthSharesBalanceBeforeVeto);

            while (rqEscrow.getUnclaimedUnstETHIdsCount() > 0) {
                rqEscrow.claimNextWithdrawalsBatch(WITHDRAWALS_BATCH_SIZE);
            }

            rqEscrow.startRageQuitExtensionPeriod();

            _assertRageQuitFinalized(false);
        }

        _step(_stepMsg("6. End of Rage Quit and ETH return to vetoers."));
        {
            _wait(_getRageQuitExtensionPeriodDuration().plusSeconds(1));

            _activateNextState();

            _assertVetoCooldownState();
            _assertRageQuitFinalized(true);

            _wait(_getRageQuitEthWithdrawalsDelay().plusSeconds(1));

            IRageQuitEscrow rqEscrow = _getRageQuitEscrow();

            for (uint256 i = 0; i < vetoers.length; ++i) {
                if (vetoersStEthBalancesBefore[i] > 0) {
                    vm.startPrank(vetoers[i]);
                    rqEscrow.withdrawETH();
                    vm.stopPrank();

                    assertApproxEqAbs(_lido.stETH.balanceOf(vetoers[i]), 0, ACCURACY);
                    assertLe(_lido.wstETH.balanceOf(vetoers[i]), MIN_LOCKABLE_AMOUNT);

                    assertApproxEqAbs(
                        vetoers[i].balance,
                        vetoersBalancesBefore[i] + vetoersStEthBalancesBefore[i],
                        ACCURACY + GAS_COST_PER_VETOER
                    );
                }
            }

            _assertVetoCooldownState();
        }

        _step(_stepMsg("7. Back to normal state."));
        {
            _activateNextState();

            _assertNormalState();
        }
    }

    function _prepareVetoer(address vetoerCandidate, uint256 index) internal returns (address vetoer) {
        if (vetoerCandidate.code.length > 0) {
            // vetoerCandidate is a contract, transferring stEth to new address
            vetoer = makeAddr(string.concat("VETOER", vm.toString(index)));

            uint256 vetoerStEthBalance = _lido.stETH.balanceOf(vetoerCandidate);
            uint256 vetoerWStEthBalance = _lido.wstETH.balanceOf(vetoerCandidate);

            vm.startPrank(vetoerCandidate);
            if (vetoerStEthBalance > 1000 wei) {
                _lido.stETH.transfer(vetoer, vetoerStEthBalance);
            }
            if (vetoerWStEthBalance > 1000 wei) {
                _lido.wstETH.transfer(vetoer, vetoerWStEthBalance);
            }
            vm.stopPrank();
        } else {
            vetoer = vetoerCandidate;
            vm.label(vetoer, string.concat("VETOER", vm.toString(index)));
        }

        // Add some ETH to vetoer to cover gas costs
        vm.deal(vetoer, vetoer.balance + 0.1 ether);
    }

    function _newRageQuitRound(uint8 round) internal {
        _round = round;
        console.log("-------------------------");
        console.log("Rage Quit round", _round);
        console.log("-------------------------");
    }

    function _stepMsg(string memory _msg) internal view returns (string memory) {
        return string.concat(vm.toString(_round), "-", _msg);
    }

    function _loadVetoers(string memory path) internal view returns (VetoersFile memory) {
        string memory vetoersFileRaw = vm.readFile(path);
        bytes memory data = vm.parseJson(vetoersFileRaw);
        return abi.decode(data, (VetoersFile));
    }

    function _loadAllVetoers(
        string memory stEthHoldersFilePath,
        string memory wstEthHoldersFilePath
    ) internal view returns (address[] memory allVetoers) {
        VetoersFile memory stEthHolders = _loadVetoers(stEthHoldersFilePath);
        VetoersFile memory wstEthHolders = _loadVetoers(wstEthHoldersFilePath);

        allVetoers = new address[](stEthHolders.addresses.length + wstEthHolders.addresses.length);

        for (uint256 i = 0; i < wstEthHolders.addresses.length; ++i) {
            allVetoers[i] = wstEthHolders.addresses[i];
        }

        for (uint256 i = 0; i < stEthHolders.addresses.length; ++i) {
            allVetoers[wstEthHolders.addresses.length + i] = stEthHolders.addresses[i];
        }
    }

    function _burnStEth(uint256 withdrawalQueueStEthSharesBeforeVeto) internal {
        uint256 wqStEthSharesBalanceAfterFinalization = _lido.stETH.sharesOf(address(_lido.withdrawalQueue));
        uint256 stEthSharesToBurn = wqStEthSharesBalanceAfterFinalization - withdrawalQueueStEthSharesBeforeVeto;

        vm.prank(address(_lido.withdrawalQueue));
        _lido.stETH.transferShares(_stEthAccumulator, stEthSharesToBurn);

        bytes32 clBeaconBalanceSlot = keccak256("lido.Lido.beaconBalance");

        uint256 oldClBalance = uint256(vm.load(address(_lido.stETH), clBeaconBalanceSlot));
        uint256 newClBalance = oldClBalance - stEthSharesToBurn;

        vm.store(address(_lido.stETH), clBeaconBalanceSlot, bytes32(newClBalance));
    }

    function _findLastVetoerIndexForRQ(address[] memory vetoers, uint256 startPos) internal view returns (uint256) {
        PercentD16 rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00);
        uint256 stEthRQAmount = _lido.calcAmountToDepositFromPercentageOfTVL(rageQuitSecondBoundary);

        uint256 holdersHaveStEthActualBalance;
        for (uint256 i = startPos; i < vetoers.length; ++i) {
            holdersHaveStEthActualBalance += _lido.stETH.balanceOf(vetoers[i]) + _lido.wstETH.balanceOf(vetoers[i]);
            if (holdersHaveStEthActualBalance >= stEthRQAmount) {
                console.log("RQ possible:", stEthRQAmount < holdersHaveStEthActualBalance);
                return i;
            }
        }

        console.log("RQ possible:", stEthRQAmount < holdersHaveStEthActualBalance);
        return vetoers.length;
    }
}
