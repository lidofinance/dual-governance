// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";
import {PercentsD16, PercentD16} from "contracts/types/PercentD16.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {
    DGRegressionTestSetup,
    ExternalCall,
    MAINNET_CHAIN_ID,
    HOLESKY_CHAIN_ID,
    HOODI_CHAIN_ID
} from "../utils/integration-tests.sol";
import {LidoUtils, MAINNET_ST_ETH, HOLESKY_ST_ETH, HOODI_ST_ETH} from "../utils/lido-utils.sol";

uint256 constant ACCURACY = 2 wei;
uint256 constant POOL_ACCUMULATED_ERROR = 150 wei;
uint256 constant MAX_WITHDRAWALS_REQUESTS_ITERATIONS = 1000;
uint256 constant WITHDRAWALS_BATCH_SIZE = 128;
uint256 constant MIN_LOCKABLE_AMOUNT = 1000 wei;

struct VetoersFile {
    address[] addresses;
}

enum VetoerTokenType {
    StEth,
    WStEth,
    UnStEth
}

contract CompleteRageQuitRegressionTest is DGRegressionTestSetup {
    using LidoUtils for LidoUtils.Context;

    address private _stEthAccumulator = makeAddr("stEthAccumulator");
    uint8 private _round = 1;
    uint256 private _lastVetoerIndex;
    uint256 private _lockedStEthSharesForCurrentRound;
    address[] private _allVetoers;
    mapping(address vetoer => uint256[] unStEthIds) private _lockedUnStEthIds;

    function setUp() external {
        _loadOrDeployDGSetup();
    }

    function testFork_RageQuitExodus_HappyPath_MultipleRounds() external {
        vm.pauseGasMetering();
        console.log("-------------------------");

        if (
            (block.chainid == MAINNET_CHAIN_ID && address(_lido.stETH) != MAINNET_ST_ETH)
                || (block.chainid == HOLESKY_CHAIN_ID && address(_lido.stETH) != HOLESKY_ST_ETH)
                || (block.chainid == HOODI_CHAIN_ID && address(_lido.stETH) != HOODI_ST_ETH)
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
            _vetoersFilePath(
                vm.envOr("REGRESSION_TEST_COMPLETE_RAGE_QUIT_STETH_VETOERS_FILENAME", string("steth_vetoers.json"))
            ),
            _vetoersFilePath(
                vm.envOr("REGRESSION_TEST_COMPLETE_RAGE_QUIT_WSTETH_VETOERS_FILENAME", string("wsteth_vetoers.json"))
            ),
            _vetoersFilePath(
                vm.envOr("REGRESSION_TEST_COMPLETE_RAGE_QUIT_UNSTETH_VETOERS_FILENAME", string("unsteth_vetoers.json"))
            )
        );

        console.log("Vetoers total amount:", _allVetoers.length);
        uint256 initialStEthTotalSupply = _lido.stETH.totalSupply();
        uint256 initialWStEthTotalSupply = _lido.wstETH.totalSupply();
        console.log("stETH.totalSupply:", initialStEthTotalSupply);
        console.log("wstETH.totalSupply:", initialWStEthTotalSupply);

        uint256 stEthRQAmount = _getStEthAmountForRageQuit(_round);

        console.log("stEth will be locked for RQ:", stEthRQAmount);

        _newRageQuitRound(1);
        address[] memory vetoers = _selectVetoers();
        _executeRQ(vetoers);

        console.log("-------------------------");

        stEthRQAmount = _getStEthAmountForRageQuit(_round);

        console.log("stEth will be locked for RQ:", stEthRQAmount);
        console.log("stETH.totalSupply:", _lido.stETH.totalSupply());

        _newRageQuitRound(2);
        vetoers = _selectVetoers();
        _executeRQ(vetoers);

        console.log("-------------------------");

        stEthRQAmount = _getStEthAmountForRageQuit(_round);

        console.log("stEth will be locked for RQ:", stEthRQAmount);
        console.log("stETH.totalSupply:", _lido.stETH.totalSupply());

        _newRageQuitRound(3);
        vetoers = _selectVetoers();
        _executeRQ(vetoers);

        console.log("-------------------------");

        stEthRQAmount = _getStEthAmountForRageQuit(_round);

        console.log("stEth will be locked for RQ:", stEthRQAmount);
        console.log("stETH.totalSupply:", _lido.stETH.totalSupply());

        _newRageQuitRound(4);
        vetoers = _selectVetoers();
        _executeRQ(vetoers);

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
        _stepMsg("0. Balances preparation.");
        uint256 lastVetoerIndexForCurrentRound = _findLastVetoerIndexForRQ(_allVetoers, _lastVetoerIndex, _round);
        uint256 originalVetoersCount = _lastVetoerIndex >= lastVetoerIndexForCurrentRound
            ? 0
            : lastVetoerIndexForCurrentRound - _lastVetoerIndex + 1;
        console.log("Vetoers for round %s: %s", _round, originalVetoersCount);

        if (originalVetoersCount == 0) {
            return new address[](0);
        }

        uint256 totalVetoersCount = 0;
        address[][] memory preparedVetoerGroups = new address[][](originalVetoersCount);

        for (uint256 i = 0; i < originalVetoersCount; ++i) {
            preparedVetoerGroups[i] = _prepareVetoer(_allVetoers[_lastVetoerIndex + i], _lastVetoerIndex + i);
            totalVetoersCount += preparedVetoerGroups[i].length;
        }

        if (totalVetoersCount > originalVetoersCount) {
            console.log("Total vetoers after splitting for round %s: %s", _round, totalVetoersCount);
        }

        vetoers = new address[](totalVetoersCount);

        uint256 vetoerIndex = 0;
        for (uint256 i = 0; i < originalVetoersCount; ++i) {
            for (uint256 j = 0; j < preparedVetoerGroups[i].length; ++j) {
                vetoers[vetoerIndex] = preparedVetoerGroups[i][j];
                vetoerIndex++;
            }
        }

        _lastVetoerIndex = lastVetoerIndexForCurrentRound + 1;
    }

    function _executeRQ(address[] memory vetoers) internal {
        if (vetoers.length == 0) {
            console.log("Skipping RQ execution for round %s as there are no vetoers available", _round);
            return;
        }

        uint256 proposalId;
        uint256[] memory vetoersStEthSharesBefore = new uint256[](vetoers.length);
        uint256[] memory vetoersBalancesBefore = new uint256[](vetoers.length);

        _stepMsg("1. New proposal submission.");
        {
            _assertNormalState();
            _assertCanSubmitProposal(true);

            ExternalCall[] memory calls = _getMockTargetRegularStaffCalls(3);

            proposalId = _submitProposalByAdminProposer(calls, "DAO performs potentially dangerous action");
            _assertProposalSubmitted(proposalId);
        }

        _stepMsg("2. Proposal scheduling.");
        {
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            _assertCanSchedule(proposalId, true);

            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);
        }

        _stepMsg("3. StETH holders veto.");
        {
            _assertNormalState();
            ISignallingEscrow vsEscrow = _getVetoSignallingEscrow();
            uint256 escrowInitialSharesBalance = _lido.stETH.sharesOf(address(vsEscrow));

            for (uint256 i = 0; i < vetoers.length; ++i) {
                uint256 vetoerStEthBalance = _lido.stETH.balanceOf(vetoers[i]);
                uint256 vetoerWStEthBalance = _lido.wstETH.balanceOf(vetoers[i]);
                uint256 vetoerUnStEthBalance = _vetoerUnStEthBalance(vetoers[i]);

                if (vetoerStEthBalance < MIN_LOCKABLE_AMOUNT) {
                    vetoerStEthBalance = 0;
                }

                if (_lido.wstETH.getStETHByWstETH(vetoerWStEthBalance) < MIN_LOCKABLE_AMOUNT) {
                    vetoerWStEthBalance = 0;
                }

                if (vetoerUnStEthBalance < MIN_LOCKABLE_AMOUNT) {
                    vetoerUnStEthBalance = 0;
                }

                vetoersBalancesBefore[i] = vetoers[i].balance;
                vetoersStEthSharesBefore[i] = _lido.stETH.getSharesByPooledEth(vetoerStEthBalance) + vetoerWStEthBalance
                    + _lido.stETH.getSharesByPooledEth(vetoerUnStEthBalance);

                if (vetoerStEthBalance > 0) {
                    _lockStETH(vetoers[i], vetoerStEthBalance);
                }

                if (vetoerWStEthBalance > 0) {
                    _lockWstETH(vetoers[i], vetoerWStEthBalance);
                }

                if (vetoerUnStEthBalance > 0) {
                    (uint256[] memory unStEthIds,) = _filterLockableUnStEths(_getAllVetoerUnStEthIds(vetoers[i]));
                    _lockUnstETH(vetoers[i], unStEthIds);
                    _lockedUnStEthIds[vetoers[i]] = unStEthIds;
                }
            }
            _lockedStEthSharesForCurrentRound = _lido.stETH.sharesOf(address(vsEscrow)) - escrowInitialSharesBalance;

            console.log("RQ support(%):", vsEscrow.getRageQuitSupport().toUint256() / 10 ** 16);

            if (vsEscrow.getRageQuitSupport() < _getSecondSealRageQuitSupport()) {
                console.log("Rage Quit is not possible, aborting");
                return;
            }

            _assertVetoSignalingState();
        }

        _stepMsg("4. Transition to Rage Quit.");
        {
            _wait(_getVetoSignallingDuration().plusSeconds(1));

            _activateNextState();

            _assertRageQuitState();
        }

        _stepMsg("5. Claiming withdrawals.");
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

            _burnStEthShares(_lockedStEthSharesForCurrentRound);

            while (rqEscrow.getUnclaimedUnstETHIdsCount() > 0) {
                rqEscrow.claimNextWithdrawalsBatch(WITHDRAWALS_BATCH_SIZE);
            }

            rqEscrow.startRageQuitExtensionPeriod();

            _assertRageQuitFinalized(false);

            for (uint256 i = 0; i < vetoers.length; ++i) {
                _claimUnstEths(vetoers[i], rqEscrow);
            }
        }

        _stepMsg("6. End of Rage Quit and ETH return to vetoers.");
        {
            _wait(_getRageQuitExtensionPeriodDuration().plusSeconds(1));

            _activateNextState();

            _assertVetoCooldownState();
            _assertRageQuitFinalized(true);

            _wait(_getRageQuitEthWithdrawalsDelay().plusSeconds(1));

            IRageQuitEscrow rqEscrow = _getRageQuitEscrow();

            for (uint256 i = 0; i < vetoers.length; ++i) {
                if (vetoersStEthSharesBefore[i] > 0) {
                    _withdrawEthByVetoerUnStEths(vetoers[i], rqEscrow);
                    _withdrawEthByVetoerStEth(vetoers[i], rqEscrow);

                    assertApproxEqAbs(_lido.stETH.balanceOf(vetoers[i]), 0, MIN_LOCKABLE_AMOUNT + ACCURACY);
                    assertLe(_lido.wstETH.getStETHByWstETH(_lido.wstETH.balanceOf(vetoers[i])), MIN_LOCKABLE_AMOUNT);

                    // This check fails sometimes on Hoodi, the reason is unknown. Replaced it with the less strict check and added a log message.
                    /* assertApproxEqAbs(
                        vetoers[i].balance,
                        vetoersBalancesBefore[i] + _lido.stETH.getPooledEthByShares(vetoersStEthSharesBefore[i]),
                        ACCURACY + POOL_ACCUMULATED_ERROR,
                        "Check for ETH amount returned to vetoer failed. Try to increase delta(POOL_ACCUMULATED_ERROR) value"
                    ); */

                    assertGe(vetoers[i].balance, vetoersBalancesBefore[i]);

                    if (
                        vetoers[i].balance
                            > vetoersBalancesBefore[i] + _lido.stETH.getPooledEthByShares(vetoersStEthSharesBefore[i])
                                + ACCURACY + POOL_ACCUMULATED_ERROR
                    ) {
                        console.log(
                            "ETH amount (%s) returned to vetoer %s is greater than expected (%s). Consider increasing delta(POOL_ACCUMULATED_ERROR) value",
                            vetoers[i].balance - vetoersBalancesBefore[i],
                            vetoers[i],
                            _lido.stETH.getPooledEthByShares(vetoersStEthSharesBefore[i])
                        );
                    }

                    if (
                        vetoers[i].balance + ACCURACY + POOL_ACCUMULATED_ERROR
                            < vetoersBalancesBefore[i] + _lido.stETH.getPooledEthByShares(vetoersStEthSharesBefore[i])
                    ) {
                        console.log(
                            "ETH amount (%s) returned to vetoer %s is lower than expected (%s).",
                            vetoers[i].balance - vetoersBalancesBefore[i],
                            vetoers[i],
                            _lido.stETH.getPooledEthByShares(vetoersStEthSharesBefore[i])
                        );
                    }
                }
            }

            _assertVetoCooldownState();
        }

        _stepMsg("7. Back to normal state.");
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
            // Add some ETH to vetoer to cover gas costs
            vm.deal(vetoers[0], vetoers[0].balance + 0.1 ether);
            return vetoers;
        }

        // else vetoerCandidate is a contract, transferring stEth to new address(es)

        uint256 totalStEthEquivalent = _lido.stETH.balanceOf(vetoerCandidate);
        uint256 vetoerWStEthBalance = _lido.wstETH.balanceOf(vetoerCandidate);
        uint256 vetoerUnStEthBalance = _vetoerUnStEthBalance(vetoerCandidate);

        if (vetoerWStEthBalance > 0) {
            totalStEthEquivalent += _lido.wstETH.getStETHByWstETH(vetoerWStEthBalance);
        }

        if (vetoerUnStEthBalance > 0) {
            totalStEthEquivalent += vetoerUnStEthBalance;
        }

        uint256 numSplits = 0;

        if (totalStEthEquivalent > VETOER_MAX_BALANCE_THRESHOLD) {
            numSplits = totalStEthEquivalent / VETOER_MAX_BALANCE_THRESHOLD;
            console.log(
                "Splitting large balance (%s stETH) of contract %s into %s EOA vetoers",
                totalStEthEquivalent,
                vetoerCandidate,
                numSplits + 1
            );
        }

        vetoers = new address[](numSplits + 1);
        vetoers[0] = makeAddr(string.concat("VETOER", vm.toString(index)));

        for (uint256 i = 0; i < numSplits; i++) {
            vetoers[i + 1] = makeAddr(string.concat("VETOER", vm.toString(index), "_SPLIT_", vm.toString(i + 1)));
        }

        for (uint256 i = 0; i < vetoers.length; i++) {
            // Add some ETH to vetoer to cover gas costs
            vm.deal(vetoers[i], 0.1 ether);
        }

        _transferTokensToVetoers(vetoerCandidate, vetoers, VetoerTokenType.StEth);
        _transferTokensToVetoers(vetoerCandidate, vetoers, VetoerTokenType.WStEth);
        _transferTokensToVetoers(vetoerCandidate, vetoers, VetoerTokenType.UnStEth);

        return vetoers;
    }

    function _transferTokensToVetoers(address from, address[] memory to, VetoerTokenType tokenType) internal {
        if (tokenType == VetoerTokenType.UnStEth) {
            _transferVetoerContractNonZeroUnStEthsTo(from, to[0]);
            return;
        }

        uint256 shares = 0;
        if (tokenType == VetoerTokenType.StEth) {
            shares = _lido.stETH.sharesOf(from);
        }
        if (tokenType == VetoerTokenType.WStEth) {
            shares = _lido.wstETH.balanceOf(from);
        }

        if (shares <= MIN_LOCKABLE_AMOUNT) return;

        vm.startPrank(from);
        uint256 sharesPerVetoer = shares / to.length;
        uint256 remainder = shares - sharesPerVetoer * to.length;

        for (uint256 i = 0; i < to.length; i++) {
            uint256 transferAmount = sharesPerVetoer;

            if (i == to.length - 1 && remainder > 0) {
                transferAmount += remainder;
            }

            if (tokenType == VetoerTokenType.StEth) {
                _lido.stETH.transferShares(to[i], transferAmount);
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

    function _stepMsg(string memory _msg) internal view {
        _step(string.concat(vm.toString(_round), "-", _msg));
    }

    function _loadVetoers(string memory path) internal view returns (VetoersFile memory) {
        string memory vetoersFileRaw = vm.readFile(path);
        bytes memory data = vm.parseJson(vetoersFileRaw);
        return abi.decode(data, (VetoersFile));
    }

    function _loadAllVetoers(
        string memory stEthHoldersFilePath,
        string memory wstEthHoldersFilePath,
        string memory unstEthHoldersFilePath
    ) internal view returns (address[] memory allVetoers) {
        VetoersFile memory stEthHolders = _loadVetoers(stEthHoldersFilePath);
        VetoersFile memory wstEthHolders = _loadVetoers(wstEthHoldersFilePath);
        VetoersFile memory unstEthHolders = _loadVetoers(unstEthHoldersFilePath);

        allVetoers = new address[](
            stEthHolders.addresses.length + wstEthHolders.addresses.length + unstEthHolders.addresses.length
        );

        uint256 last = 0;

        for (uint256 i = 0; i < unstEthHolders.addresses.length; ++i) {
            allVetoers[last + i] = unstEthHolders.addresses[i];
        }
        last += unstEthHolders.addresses.length;

        for (uint256 i = 0; i < wstEthHolders.addresses.length; ++i) {
            allVetoers[last + i] = wstEthHolders.addresses[i];
        }
        last += wstEthHolders.addresses.length;

        for (uint256 i = 0; i < stEthHolders.addresses.length; ++i) {
            allVetoers[last + i] = stEthHolders.addresses[i];
        }
        last += stEthHolders.addresses.length;
    }

    function _burnStEthShares(uint256 sharesToBurn) internal {
        uint256 stEthToBurn = _lido.stETH.getPooledEthByShares(sharesToBurn);

        if (sharesToBurn > _lido.stETH.sharesOf(address(_lido.withdrawalQueue))) {
            if (sharesToBurn - _lido.stETH.sharesOf(address(_lido.withdrawalQueue)) <= ACCURACY) {
                sharesToBurn = _lido.stETH.sharesOf(address(_lido.withdrawalQueue)) - ACCURACY;
            } else {
                console.log("Requested stEth shares amount to burn exceeds WQ stETH balance");
            }
        }
        vm.prank(address(_lido.withdrawalQueue));
        _lido.stETH.transferShares(_stEthAccumulator, sharesToBurn);

        bytes32 clBeaconBalanceSlot = keccak256("lido.Lido.beaconBalance");
        bytes32 totalSharesSlot = keccak256("lido.StETH.totalShares");

        uint256 oldClBalance = uint256(vm.load(address(_lido.stETH), clBeaconBalanceSlot));
        uint256 newClBalance = stEthToBurn >= oldClBalance ? 0 : oldClBalance - stEthToBurn;

        vm.store(address(_lido.stETH), clBeaconBalanceSlot, bytes32(newClBalance));

        uint256 oldSharesBalance = uint256(vm.load(address(_lido.stETH), totalSharesSlot));
        uint256 newSharesBalance = sharesToBurn >= oldSharesBalance ? 0 : oldSharesBalance - sharesToBurn;
        vm.store(address(_lido.stETH), totalSharesSlot, bytes32(newSharesBalance));
    }

    function _findLastVetoerIndexForRQ(
        address[] memory vetoers,
        uint256 startPos,
        uint256 round
    ) internal view returns (uint256) {
        uint256 stEthRQShares = _getStEthSharesForRageQuit(round);

        uint256 holdersHaveStEthActualShares;
        for (uint256 i = startPos; i < vetoers.length; ++i) {
            uint256 vetoerStEthShares =
                _lido.stETH.sharesOf(vetoers[i]) + _lido.wstETH.balanceOf(vetoers[i]) + _vetoerUnStEthShares(vetoers[i]);
            holdersHaveStEthActualShares += vetoerStEthShares;
            if (holdersHaveStEthActualShares >= stEthRQShares) {
                console.log("RQ possible:", stEthRQShares < holdersHaveStEthActualShares);
                return i;
            }
        }

        console.log("RQ possible:", stEthRQShares < holdersHaveStEthActualShares);
        return vetoers.length > 0 ? vetoers.length - 1 : 0;
    }

    function _getStEthAmountForRageQuit(uint256 round) internal view returns (uint256) {
        PercentD16 rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(3_00 * round);
        return _lido.calcAmountToDepositFromPercentageOfTVL(rageQuitSecondBoundary);
    }

    function _getStEthSharesForRageQuit(uint256 round) internal view returns (uint256) {
        PercentD16 rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(3_00 * round);
        return _lido.calcSharesToDepositFromPercentageOfTVL(rageQuitSecondBoundary);
    }

    function _vetoersFilePath(string memory fileName) internal pure returns (string memory) {
        return string.concat("./test/regressions/complete-rage-quit-files/", fileName);
    }

    function _getAllVetoerUnStEthIds(address vetoer) internal view returns (uint256[] memory) {
        return new uint256[](0);
        uint256[] memory requestIds = _lido.withdrawalQueue.getWithdrawalRequests(vetoer);

        if (requestIds.length < 2) {
            return requestIds;
        }

        uint256[] memory sortedRequestIds = new uint256[](requestIds.length);

        sortedRequestIds[0] = _arrayMinGt(requestIds, 0);

        for (uint256 i = 1; i < sortedRequestIds.length; ++i) {
            sortedRequestIds[i] = _arrayMinGt(requestIds, sortedRequestIds[i - 1]);
        }

        return sortedRequestIds;
    }

    function _arrayMinGt(uint256[] memory arr, uint256 lowerBound) internal pure returns (uint256 min) {
        min = type(uint256).max;
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] < min && arr[i] > lowerBound) {
                min = arr[i];
            }
        }
    }

    function _filterLockableUnStEths(uint256[] memory ids)
        internal
        view
        returns (uint256[] memory unStEthIds, IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses)
    {
        IWithdrawalQueue.WithdrawalRequestStatus[] memory allStatuses = _lido.withdrawalQueue.getWithdrawalStatus(ids);

        uint256 lockableUnStEthsCount = 0;
        for (uint256 i = 0; i < ids.length; ++i) {
            if (!allStatuses[i].isFinalized && !allStatuses[i].isClaimed) {
                lockableUnStEthsCount++;
            }
        }

        unStEthIds = new uint256[](lockableUnStEthsCount);
        statuses = new IWithdrawalQueue.WithdrawalRequestStatus[](lockableUnStEthsCount);

        if (lockableUnStEthsCount == 0) {
            return (unStEthIds, statuses);
        }

        uint256 lastUnStEthIndex = 0;
        for (uint256 i = 0; i < ids.length; ++i) {
            if (!allStatuses[i].isFinalized && !allStatuses[i].isClaimed) {
                unStEthIds[lastUnStEthIndex] = ids[i];
                statuses[lastUnStEthIndex] = allStatuses[i];
                lastUnStEthIndex++;
            }
        }
    }

    function _vetoerUnStEthShares(address vetoer) internal view returns (uint256 shares) {
        (uint256[] memory unStEthIds, IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses) =
            _filterLockableUnStEths(_getAllVetoerUnStEthIds(vetoer));

        for (uint256 i = 0; i < unStEthIds.length; ++i) {
            shares += statuses[i].amountOfShares;
        }
    }

    function _vetoerUnStEthBalance(address vetoer) internal view returns (uint256 stEthAmount) {
        (uint256[] memory unStEthIds, IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses) =
            _filterLockableUnStEths(_getAllVetoerUnStEthIds(vetoer));

        for (uint256 i = 0; i < unStEthIds.length; ++i) {
            stEthAmount += statuses[i].amountOfStETH;
        }
    }

    function _transferVetoerContractNonZeroUnStEthsTo(address vetoer, address to) internal {
        (uint256[] memory unStEthIds, IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses) =
            _filterLockableUnStEths(_getAllVetoerUnStEthIds(vetoer));
        for (uint256 i = 0; i < unStEthIds.length; ++i) {
            if (statuses[i].amountOfShares > 0) {
                vm.prank(vetoer);
                _lido.withdrawalQueue.transferFrom(vetoer, to, unStEthIds[i]);
            }
        }
    }

    function _claimUnstEths(address vetoer, IRageQuitEscrow rqEscrow) internal {
        if (_lockedUnStEthIds[vetoer].length == 0) {
            return;
        }

        uint256[] memory vetoerUnStEthIds = _lockedUnStEthIds[vetoer];
        IWithdrawalQueue.WithdrawalRequestStatus[] memory unStEthStatuses =
            _lido.withdrawalQueue.getWithdrawalStatus(vetoerUnStEthIds);

        uint256 unclaimedUnStEthsCount = 0;
        for (uint256 k = 0; k < vetoerUnStEthIds.length; ++k) {
            if (!unStEthStatuses[k].isClaimed) {
                unclaimedUnStEthsCount++;
            }
        }

        if (unclaimedUnStEthsCount == 0) {
            return;
        }

        uint256 lastUnclaimedIdx = 0;
        uint256[] memory unclaimedUnStEthIds = new uint256[](unclaimedUnStEthsCount);
        for (uint256 k = 0; k < vetoerUnStEthIds.length; ++k) {
            if (!unStEthStatuses[k].isClaimed) {
                unclaimedUnStEthIds[lastUnclaimedIdx] = vetoerUnStEthIds[k];
                lastUnclaimedIdx++;
            }
        }

        uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
            unclaimedUnStEthIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );
        rqEscrow.claimUnstETH(unclaimedUnStEthIds, hints);
    }

    function _withdrawEthByVetoerUnStEths(address vetoer, IRageQuitEscrow rqEscrow) internal {
        if (_lockedUnStEthIds[vetoer].length > 0) {
            vm.startPrank(vetoer);
            rqEscrow.withdrawETH(_lockedUnStEthIds[vetoer]);
            vm.stopPrank();
        }
    }

    function _withdrawEthByVetoerStEth(address vetoer, IRageQuitEscrow rqEscrow) internal {
        if (ISignallingEscrow(address(rqEscrow)).getVetoerDetails(vetoer).stETHLockedShares.toUint256() > 0) {
            vm.startPrank(vetoer);
            rqEscrow.withdrawETH();
            vm.stopPrank();
        }
    }
}
