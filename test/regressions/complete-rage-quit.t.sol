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
uint256 constant POOL_ACCUMULATED_ERROR = 150 wei;
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
    uint256 private _lastVetoerIndexForPreviousRound;
    uint256 private _lockedStEthForCurrentRound;
    address[] private _allVetoers;

    function setUp() external {
        _loadOrDeployDGSetup();
    }

    function testFork_RageQuitExodus_HappyPath_MultipleRounds() external {
        vm.pauseGasMetering();
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
        console.log("stETH.totalSupply:", initialStEthTotalSupply);
        console.log("wstETH.totalSupply:", initialWStEthTotalSupply);

        uint256 stEthRQAmount = _getStEthAmountForRageQuit(_round);

        console.log("stEth will be locked for RQ:", stEthRQAmount);

        address[] memory vetoers;
        uint8 roundNumber = 1;
        bool hasMoreVetoers = true;

        while (hasMoreVetoers && roundNumber <= 10) {
            _newRageQuitRound(roundNumber);
            vetoers = _selectVetoers();

            if (vetoers.length == 0) {
                console.log("No more vetoers available. Ending test after %s rounds.", roundNumber - 1);
                hasMoreVetoers = false;
                break;
            }

            _executeRQ(vetoers);

            console.log("-------------------------");
            stEthRQAmount = _getStEthAmountForRageQuit(_round);
            console.log("stEth will be locked for RQ:", stEthRQAmount);
            console.log("stETH.totalSupply:", _lido.stETH.totalSupply());

            roundNumber++;
        }

        console.log("-------------------------");

        console.log("stETH.totalSupply:", _lido.stETH.totalSupply());
        console.log(
            "stETH total supply decreased for %s%", 100 - _lido.stETH.totalSupply() * 100 / initialStEthTotalSupply
        );
        console.log("wstETH.totalSupply:", _lido.wstETH.totalSupply());
        console.log(
            "wstETH total supply decreased for %s%", 100 - _lido.wstETH.totalSupply() * 100 / initialWStEthTotalSupply
        );
        vm.resumeGasMetering();
    }

    function _selectVetoers() internal returns (address[] memory vetoers) {
        _step(_stepMsg("0. Balances preparation."));

        uint256 lastIndex = _findLastVetoerIndexForRound(_allVetoers, _lastVetoerIndexForPreviousRound, _round);
        uint256 firstIndex = _lastVetoerIndexForPreviousRound;

        uint256 originalVetoersCount = (lastIndex >= firstIndex) ? (lastIndex - firstIndex + 1) : 0;
        console.log("Original vetoers for round %s: %s", _round, originalVetoersCount);

        if (originalVetoersCount == 0) {
            return new address[](0);
        }

        uint256 totalVetoersCount = 0;
        address[][] memory preparedVetoerGroups = new address[][](originalVetoersCount);

        for (uint256 i = 0; i < originalVetoersCount; ++i) {
            preparedVetoerGroups[i] = _prepareVetoer(_allVetoers[firstIndex + i], firstIndex + i);
            totalVetoersCount += preparedVetoerGroups[i].length;
        }

        console.log("Total vetoers after splitting for round %s: %s", _round, totalVetoersCount);

        vetoers = new address[](totalVetoersCount);

        uint256 vetoerIndex = 0;
        for (uint256 i = 0; i < originalVetoersCount; ++i) {
            for (uint256 j = 0; j < preparedVetoerGroups[i].length; ++j) {
                vetoers[vetoerIndex] = preparedVetoerGroups[i][j];
                vetoerIndex++;
            }
        }

        _lastVetoerIndexForPreviousRound = lastIndex + 1;
    }

    function _executeRQ(address[] memory vetoers) internal {
        if (vetoers.length == 0) {
            console.log("Skipping RQ execution for round %s as there are no vetoers available", _round);
            return;
        }

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
            ISignallingEscrow vsEscrow = _getVetoSignallingEscrow();
            uint256 escrowInitialBalance = _lido.stETH.balanceOf(address(vsEscrow));

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
            _lockedStEthForCurrentRound = _lido.stETH.balanceOf(address(vsEscrow)) - escrowInitialBalance;

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

            _burnStEth(_lockedStEthForCurrentRound);

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

                    assertApproxEqAbs(_lido.stETH.balanceOf(vetoers[i]), 0, 2 * ACCURACY);
                    assertLe(_lido.wstETH.balanceOf(vetoers[i]), MIN_LOCKABLE_AMOUNT);

                    assertApproxEqAbs(
                        vetoers[i].balance,
                        vetoersBalancesBefore[i] + vetoersStEthBalancesBefore[i],
                        ACCURACY + POOL_ACCUMULATED_ERROR,
                        "Check for ETH amount returned to vetoer failed. Try to increase delta(POOL_ACCUMULATED_ERROR) value"
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

    function _prepareVetoer(address vetoerCandidate, uint256 index) internal returns (address[] memory vetoers) {
        uint256 VETOER_MAX_BALANCE_THRESHOLD = (_lido.stETH.totalSupply() * 5) / 100;

        if (vetoerCandidate.code.length == 0) {
            vetoers = new address[](1);
            vetoers[0] = vetoerCandidate;
            vm.label(vetoers[0], string.concat("VETOER", vm.toString(index)));
            vm.deal(vetoers[0], vetoers[0].balance + 0.1 ether);
            return vetoers;
        }

        uint256 vetoerStEthBalance = _lido.stETH.balanceOf(vetoerCandidate);
        uint256 vetoerWStEthBalance = _lido.wstETH.balanceOf(vetoerCandidate);
        uint256 totalStEthEquivalent = vetoerStEthBalance;

        if (vetoerWStEthBalance > 0) {
            totalStEthEquivalent += _lido.wstETH.getStETHByWstETH(vetoerWStEthBalance);
        }

        uint256 numSplits = 0;

        if (totalStEthEquivalent > VETOER_MAX_BALANCE_THRESHOLD) {
            numSplits = totalStEthEquivalent / VETOER_MAX_BALANCE_THRESHOLD;
            console.log("Splitting large balance (%s stETH) into %s vetoers", totalStEthEquivalent, numSplits + 1);
        }

        vetoers = new address[](numSplits + 1);
        vetoers[0] = makeAddr(string.concat("VETOER", vm.toString(index)));

        for (uint256 i = 0; i < numSplits; i++) {
            vetoers[i + 1] = makeAddr(string.concat("VETOER", vm.toString(index), "_SPLIT_", vm.toString(i + 1)));
        }

        for (uint256 i = 0; i < vetoers.length; i++) {
            vm.deal(vetoers[i], 0.1 ether);
        }

        _transferTokensToVetoers(vetoerCandidate, vetoers, vetoerStEthBalance, true);
        _transferTokensToVetoers(vetoerCandidate, vetoers, vetoerWStEthBalance, false);

        return vetoers;
    }

    function _transferTokensToVetoers(address from, address[] memory to, uint256 amount, bool isStEth) internal {
        if (amount <= MIN_LOCKABLE_AMOUNT) return;

        vm.startPrank(from);
        uint256 amountPerVetoer = amount / to.length;
        uint256 remainder = amount - amountPerVetoer * to.length;

        for (uint256 i = 0; i < to.length; i++) {
            uint256 transferAmount = amountPerVetoer;

            if (i == to.length - 1 && remainder > 0) {
                transferAmount += remainder;
            }

            if (isStEth) {
                _lido.stETH.transfer(to[i], transferAmount);
            } else {
                _lido.wstETH.transfer(to[i], transferAmount);
            }
        }

        vm.stopPrank();
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

    function _burnStEth(uint256 stEthToBurn) internal {
        uint256 sharesToBurn = _lido.stETH.getSharesByPooledEth(stEthToBurn);

        vm.prank(address(_lido.withdrawalQueue));
        _lido.stETH.transfer(_stEthAccumulator, stEthToBurn);

        bytes32 clBeaconBalanceSlot = keccak256("lido.Lido.beaconBalance");
        bytes32 totalSharesSlot = keccak256("lido.StETH.totalShares");

        uint256 oldClBalance = uint256(vm.load(address(_lido.stETH), clBeaconBalanceSlot));
        uint256 newClBalance = oldClBalance - stEthToBurn;

        vm.store(address(_lido.stETH), clBeaconBalanceSlot, bytes32(newClBalance));

        uint256 oldSharesBalance = uint256(vm.load(address(_lido.stETH), totalSharesSlot));
        uint256 newSharesBalance = oldSharesBalance - sharesToBurn;
        vm.store(address(_lido.stETH), totalSharesSlot, bytes32(newSharesBalance));
    }

    function _findLastVetoerIndexForRound(
        address[] memory vetoers,
        uint256 startPos,
        uint256 round
    ) internal view returns (uint256) {
        uint256 stEthRQAmount = _getStEthAmountForRageQuit(round);

        uint256 holdersHaveStEthActualBalance;
        for (uint256 i = startPos; i < vetoers.length; ++i) {
            uint256 vetoerStEthBalance =
                _lido.stETH.balanceOf(vetoers[i]) + _lido.wstETH.getStETHByWstETH(_lido.wstETH.balanceOf(vetoers[i]));
            holdersHaveStEthActualBalance += vetoerStEthBalance;
            if (holdersHaveStEthActualBalance >= stEthRQAmount) {
                console.log("RQ possible:", stEthRQAmount < holdersHaveStEthActualBalance);
                return i;
            }
        }

        console.log("RQ possible:", stEthRQAmount < holdersHaveStEthActualBalance);
        return vetoers.length > 0 ? vetoers.length - 1 : 0;
    }

    function _getStEthAmountForRageQuit(uint256 round) internal view returns (uint256) {
        PercentD16 rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(3_00 * round);
        return _lido.calcAmountToDepositFromPercentageOfTVL(rageQuitSecondBoundary);
    }
}
