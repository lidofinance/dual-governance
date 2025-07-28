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
import {Random} from "../utils/random.sol";
import {DecimalsFormatting} from "test/utils/formatting.sol";

uint256 constant ACCURACY = 2 wei;
uint256 constant POOL_ACCUMULATED_ERROR = 1000 wei;
uint256 constant MAX_WITHDRAWALS_REQUESTS_ITERATIONS = 1000;
uint256 constant WITHDRAWALS_BATCH_SIZE = 128;
uint256 constant MIN_LOCKABLE_AMOUNT = 1000 wei;

uint256 constant MIN_REBASE_BP = 99_90;
uint256 constant MAX_REBASE_BP = 100_25;

struct VetoersFile {
    address[] addresses;
}

enum VetoerTokenType {
    StEth,
    WStEth,
    UnStEth
}

contract CompleteRageQuitRegressionTest is DGRegressionTestSetup {
    using Random for Random.Context;
    using LidoUtils for LidoUtils.Context;
    using DecimalsFormatting for uint256;
    using DecimalsFormatting for PercentD16;

    uint8 private _round = 1;
    uint256 private _lastVetoerIndex;
    address[] private _allVetoers;
    mapping(address vetoer => uint256[] unStEthIds) private _lockedUnStEthIds;
    mapping(address vetoer => uint256[] unStEthIds) private _allVetoersUnstEthIds;
    mapping(address vetoer => uint256 totalClaimedETH) private _vetoersClaimedETH;
    Random.Context internal _random;
    uint256[] private _rebaseDeltaPercents;

    function setUp() external {
        _loadOrDeployDGSetup();
        uint256 randomSeed = vm.unixTime();
        _random = Random.create(randomSeed);

        console.log("Using random seed:", randomSeed);
    }

    function testFork_RageQuit_HappyPath_SingleRound() external {
        _runRageQuitRounds({rageQuitRounds: 1, desiredStEthDecreaseBP: 0});
    }

    function testFork_RageQuitExodus_HappyPath_MultipleRounds() external {
        if (!vm.envOr("ENABLE_REGRESSION_TEST_COMPLETE_RAGE_QUIT", false)) {
            vm.skip(
                true,
                "To enable this test set the env variable ENABLE_REGRESSION_TEST_COMPLETE_RAGE_QUIT=true and MAINNET_FORK_BLOCK_NUMBER=22732744"
            );
            return;
        }

        _runRageQuitRounds({rageQuitRounds: 6, desiredStEthDecreaseBP: 85_00});
    }

    function _runRageQuitRounds(uint256 rageQuitRounds, uint256 desiredStEthDecreaseBP) internal {
        if (
            (block.chainid == MAINNET_CHAIN_ID && address(_lido.stETH) != MAINNET_ST_ETH)
                || (block.chainid == HOLESKY_CHAIN_ID && address(_lido.stETH) != HOLESKY_ST_ETH)
                || (block.chainid == HOODI_CHAIN_ID && address(_lido.stETH) != HOODI_ST_ETH)
        ) {
            vm.skip(true, "This test is not intended to be run with the custom StETH token implementation");
            return;
        }

        // TODO: the below operation freeze the test passing at the LidoUtils._handleOracleReport()
        // method. Seems like bug in the forge, but need to be investigated properly. Keeping it commented
        // for now.
        // vm.pauseGasMetering();

        uint256[] memory rebaseDeltaPercents = new uint256[](rageQuitRounds);
        for (uint256 i = 0; i < rageQuitRounds; ++i) {
            rebaseDeltaPercents[i] = Random.nextUint256(_random, MIN_REBASE_BP, MAX_REBASE_BP);
        }

        console.log("-------------------------");

        _rebaseDeltaPercents = rebaseDeltaPercents;
        _allVetoers = _loadAllVetoers(
            _vetoersFilePath(
                vm.envOr("REGRESSION_TEST_COMPLETE_RAGE_QUIT_STETH_VETOERS_FILENAME", string("steth_vetoers.json"))
            ),
            _vetoersFilePath(
                vm.envOr("REGRESSION_TEST_COMPLETE_RAGE_QUIT_WSTETH_VETOERS_FILENAME", string("wsteth_vetoers.json"))
            )
        );

        console.log("Vetoers total amount:", _allVetoers.length);
        uint256 vetoersExited = 0;
        uint256 initialStEthTotalSupply = _lido.stETH.totalSupply();
        uint256 initialWStEthTotalSupply = _lido.wstETH.totalSupply();
        console.log("stETH.totalSupply:", initialStEthTotalSupply.formatEther());
        console.log("wstETH.totalSupply:", initialWStEthTotalSupply.formatEther());

        uint256 stEthRQAmount = 0;
        address[] memory vetoers;

        for (; _round <= rageQuitRounds; ++_round) {
            stEthRQAmount = _getStEthAmountForRageQuit(_round);

            console.log("Planning to lock stEth for current RQ round:", stEthRQAmount.formatEther());
            console.log("stETH.totalSupply:", _lido.stETH.totalSupply().formatEther());

            _newRageQuitRound();
            vetoers = _selectVetoers();

            bool rqExecuted = _executeRQ(vetoers);

            if (_round == 1 && !rqExecuted) {
                console.log(
                    "Vetoers amount is not enough to execute a single Rage Quit. Consider updating vetoers addresses in files '%s' and '%s'",
                    vm.envOr("REGRESSION_TEST_COMPLETE_RAGE_QUIT_STETH_VETOERS_FILENAME", string("steth_vetoers.json")),
                    vm.envOr(
                        "REGRESSION_TEST_COMPLETE_RAGE_QUIT_WSTETH_VETOERS_FILENAME", string("wsteth_vetoers.json")
                    )
                );

                revert("Not enough vetoers");
            }

            vetoersExited += vetoers.length;

            console.log("-------------------------");
        }

        PercentD16 stEthTotalSupplyDecrease = PercentsD16.fromBasisPoints(100_00)
            - PercentsD16.fromFraction({numerator: _lido.stETH.totalSupply(), denominator: initialStEthTotalSupply});
        console.log("stETH.totalSupply:", _lido.stETH.totalSupply().formatEther());
        console.log("stETH total supply decreased for %s", stEthTotalSupplyDecrease.format());
        console.log("wstETH.totalSupply:", _lido.wstETH.totalSupply().formatEther());
        console.log(
            "wstETH total supply decreased for %s",
            (
                PercentsD16.fromBasisPoints(100_00)
                    - PercentsD16.fromFraction({
                        numerator: _lido.wstETH.totalSupply(),
                        denominator: initialWStEthTotalSupply
                    })
            ).format()
        );

        console.log("-------------------------");
        console.log("%s vetoers exited during %s Rage Quit rounds", vetoersExited, rageQuitRounds);
        console.log("-------------------------");

        if (
            desiredStEthDecreaseBP != 0
                && stEthTotalSupplyDecrease < PercentsD16.fromBasisPoints(desiredStEthDecreaseBP)
        ) {
            console.log(
                "|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|"
            );
            console.log(
                "| StETH amount locked by vetoers during %s Rage Quit rounds is too low (StETH total supply decreased for %s, expected: %s).",
                rageQuitRounds,
                stEthTotalSupplyDecrease.format(),
                PercentsD16.fromBasisPoints(desiredStEthDecreaseBP).format()
            );
            console.log(
                "| Consider updating vetoers addresses in files '%s' and '%s'",
                vm.envOr("REGRESSION_TEST_COMPLETE_RAGE_QUIT_STETH_VETOERS_FILENAME", string("steth_vetoers.json")),
                vm.envOr("REGRESSION_TEST_COMPLETE_RAGE_QUIT_WSTETH_VETOERS_FILENAME", string("wsteth_vetoers.json"))
            );
            console.log(
                "|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|"
            );

            revert("Desired StETH total supply decrease not achieved");
        }
        // vm.resumeGasMetering();
    }

    function _selectVetoers() internal returns (address[] memory vetoers) {
        _stepMsg("0. Balances preparation.");
        uint256 lastVetoerIndexForCurrentRound = _findLastVetoerIndexForRQ(_allVetoers, _lastVetoerIndex, _round);
        uint256 originalVetoersCount = _lastVetoerIndex > lastVetoerIndexForCurrentRound
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

    function _executeRQ(address[] memory vetoers) internal returns (bool) {
        if (vetoers.length == 0) {
            console.log("Skipping RQ execution for round %s as there are no vetoers available", _round);
            return false;
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
            vm.label(address(vsEscrow), "VetoSignallingEscrow");

            for (uint256 i = 0; i < vetoers.length; ++i) {
                uint256 vetoerStEthBalance = _lido.stETH.balanceOf(vetoers[i]);
                uint256 vetoerWStEthBalance = _lido.wstETH.balanceOf(vetoers[i]);
                (, uint256 vetoerUnStEthBalance) = _getVetoerUnStEthBalances(vetoers[i]);

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

                // Do not account for unstETH shares here as they will be count separately
                vetoersStEthSharesBefore[i] = _lido.stETH.getSharesByPooledEth(vetoerStEthBalance) + vetoerWStEthBalance;

                if (vetoerStEthBalance > 0) {
                    _lockStETH(vetoers[i], vetoerStEthBalance);
                }

                if (vetoerWStEthBalance > 0) {
                    _lockWstETH(vetoers[i], vetoerWStEthBalance);
                }

                if (vetoerUnStEthBalance > 0) {
                    uint256[] memory unStEthIds = _getVetoerLockableUnStEthIds(vetoers[i]);

                    if (unStEthIds.length > 0) {
                        _lockUnstETH(vetoers[i], unStEthIds);
                        _lockedUnStEthIds[vetoers[i]] = unStEthIds;
                    }
                }
            }

            console.log("RQ support(%):", vsEscrow.getRageQuitSupport().toUint256() / 10 ** 16);

            if (vsEscrow.getRageQuitSupport() < _getSecondSealRageQuitSupport()) {
                console.log("Rage Quit is not possible, aborting");
                return false;
            }

            _assertVetoSignalingState();
        }

        _stepMsg("4. Transition to Rage Quit.");
        {
            _wait(_getVetoSignallingDuration().plusSeconds(1));

            _activateNextState();

            _assertRageQuitState();

            PercentD16 rebasePercent = PercentsD16.fromBasisPoints(_rebaseDeltaPercents[_round - 1]);
            console.log("Rebase happened: %s", rebasePercent.format());

            _simulateRebase(rebasePercent);
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

            while (_lido.withdrawalQueue.getLastRequestId() != _lido.withdrawalQueue.getLastFinalizedRequestId()) {
                _finalizeWithdrawalQueue();
            }

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
                if (_lockedUnStEthIds[vetoers[i]].length > 0) {
                    // correctness of the withdrawn unstETH is calculated inside the _withdrawEthByVetoerUnStEths
                    _withdrawEthByVetoerUnStEths(vetoers[i], rqEscrow);
                    delete _lockedUnStEthIds[vetoers[i]];
                }

                if (vetoersStEthSharesBefore[i] > 0) {
                    ISignallingEscrow.SignallingEscrowDetails memory escrowDetails =
                        ISignallingEscrow(address(rqEscrow)).getSignallingEscrowDetails();
                    uint256 vetoerETHBalanceBefore = vetoers[i].balance;
                    _withdrawEthByVetoerStEth(vetoers[i], rqEscrow);

                    assertApproxEqAbs(_lido.stETH.balanceOf(vetoers[i]), 0, MIN_LOCKABLE_AMOUNT + ACCURACY);
                    assertLe(_lido.wstETH.getStETHByWstETH(_lido.wstETH.balanceOf(vetoers[i])), MIN_LOCKABLE_AMOUNT);

                    uint256 expectedVetoerBalance = vetoerETHBalanceBefore
                        + vetoersStEthSharesBefore[i] * escrowDetails.totalStETHClaimedETH.toUint256()
                            / escrowDetails.totalStETHLockedShares.toUint256();

                    assertApproxEqAbs(
                        vetoers[i].balance,
                        expectedVetoerBalance,
                        ACCURACY + POOL_ACCUMULATED_ERROR,
                        "Check for ETH amount returned to vetoer failed. Try to increase delta(POOL_ACCUMULATED_ERROR) value"
                    );
                }
            }

            console.log(">>> RageQuit Escrow ETH balance after withdraw:", address(rqEscrow).balance.formatEther());

            _assertVetoCooldownState();
        }

        _stepMsg("7. Back to normal state.");
        {
            _activateNextState();

            _assertNormalState();
        }

        return true;
    }

    function _prepareVetoer(address vetoerCandidate, uint256 index) internal returns (address[] memory vetoers) {
        if (vetoerCandidate == address(_getVetoSignallingEscrow()) || vetoerCandidate == address(_getRageQuitEscrow()))
        {
            return vetoers;
        }

        // solhint-disable-next-line var-name-mixedcase
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
        (, uint256 vetoerUnStEthBalance) = _getVetoerUnStEthBalances(vetoerCandidate);

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

    function _newRageQuitRound() internal view {
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
        string memory wstEthHoldersFilePath
    ) internal returns (address[] memory allVetoers) {
        VetoersFile memory stEthHolders = _loadVetoers(stEthHoldersFilePath);
        VetoersFile memory wstEthHolders = _loadVetoers(wstEthHoldersFilePath);
        VetoersFile memory unstEthHolders = _loadUnStEthVetoers();

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
        allVetoers = _shuffleVetoersPart(allVetoers, unstEthHolders.addresses.length);
    }

    function _loadUnStEthVetoers() internal returns (VetoersFile memory addrsData) {
        uint256 lastFinalizedId = _lido.withdrawalQueue.getLastFinalizedRequestId();
        uint256 lastRequestId = _lido.withdrawalQueue.getLastRequestId();

        assertGe(lastRequestId, lastFinalizedId);

        if (lastRequestId == lastFinalizedId) {
            return addrsData;
        }

        uint256[] memory allUnstEthIds = new uint256[](lastRequestId - lastFinalizedId);
        for (uint256 i = 0; i < allUnstEthIds.length; ++i) {
            allUnstEthIds[i] = lastFinalizedId + 1 + i;
        }

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalStatuses =
            _lido.withdrawalQueue.getWithdrawalStatus(allUnstEthIds);

        uint256 uniqueOwnersCount = 0;
        address[] memory allOwners = new address[](allUnstEthIds.length);
        for (uint256 i = 0; i < allUnstEthIds.length; ++i) {
            if (_allVetoersUnstEthIds[withdrawalStatuses[i].owner].length == 0) {
                uniqueOwnersCount++;
            }
            _allVetoersUnstEthIds[withdrawalStatuses[i].owner].push(allUnstEthIds[i]);
            allOwners[i] = withdrawalStatuses[i].owner;
        }

        addrsData.addresses = _arrayUniq(allOwners, uniqueOwnersCount);
    }

    function _findLastVetoerIndexForRQ(
        address[] memory vetoers,
        uint256 startPos,
        uint256 round
    ) internal view returns (uint256) {
        uint256 stEthRQShares = _getStEthSharesForRageQuit(round);

        uint256 holdersHaveStEthActualShares;
        for (uint256 i = startPos; i < vetoers.length; ++i) {
            if (vetoers[i] == address(_getVetoSignallingEscrow()) || vetoers[i] == address(_getRageQuitEscrow())) {
                continue;
            }
            (uint256 vetoerUnStEthShares,) = _getVetoerUnStEthBalances(vetoers[i]);
            uint256 vetoerStEthShares =
                _lido.stETH.sharesOf(vetoers[i]) + _lido.wstETH.balanceOf(vetoers[i]) + vetoerUnStEthShares;
            holdersHaveStEthActualShares += vetoerStEthShares;
            if (holdersHaveStEthActualShares >= stEthRQShares) {
                console.log("RQ possible:", stEthRQShares < holdersHaveStEthActualShares);
                return i;
            }
        }

        console.log(
            "RQ possible:",
            _lido.calcSharesToDepositFromPercentageOfTVL(_getSecondSealRageQuitSupport()) < holdersHaveStEthActualShares
        );
        return vetoers.length > 0 ? vetoers.length - 1 : 0;
    }

    function _getStEthAmountForRageQuit(uint256 round) internal view returns (uint256) {
        PercentD16 rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(2_50 * round);
        return _lido.calcAmountToDepositFromPercentageOfTVL(rageQuitSecondBoundary);
    }

    function _getStEthSharesForRageQuit(uint256 round) internal view returns (uint256) {
        PercentD16 rageQuitSecondBoundary = _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(2_50 * round);
        return _lido.calcSharesToDepositFromPercentageOfTVL(rageQuitSecondBoundary);
    }

    function _vetoersFilePath(string memory fileName) internal pure returns (string memory) {
        return string.concat("./test/regressions/complete-rage-quit-files/", fileName);
    }

    function _arrayUniq(
        address[] memory arr,
        uint256 uniqElementsCount
    ) internal pure returns (address[] memory unique) {
        if (arr.length < 2) {
            return arr;
        }
        assertLe(uniqElementsCount, arr.length);

        unique = new address[](uniqElementsCount);
        uint256 lastUniqueIndex = 0;
        for (uint256 i = 0; i < arr.length; ++i) {
            bool found = false;
            for (uint256 k = 0; k < lastUniqueIndex && !found; ++k) {
                if (unique[k] == arr[i]) {
                    found = true;
                }
            }
            if (!found) {
                unique[lastUniqueIndex] = arr[i];
                lastUniqueIndex++;
            }
        }
    }

    function _shuffleVetoersPart(
        address[] memory vetoers,
        uint256 startIndex
    ) internal returns (address[] memory shuffledVetoers) {
        uint256[] memory randomIndicesPermutation = _random.nextPermutation(vetoers.length - startIndex, startIndex);

        shuffledVetoers = new address[](vetoers.length);
        for (uint256 i = 0; i < vetoers.length; ++i) {
            shuffledVetoers[i] = vetoers[i];
        }
        for (uint256 i = startIndex; i < vetoers.length; ++i) {
            shuffledVetoers[i] = vetoers[randomIndicesPermutation[i - startIndex]];
        }
    }

    function _getVetoerLockableUnStEthIds(address vetoer) internal view returns (uint256[] memory unStEthIds) {
        IWithdrawalQueue.WithdrawalRequestStatus[] memory vetoerUnstEthStatuses =
            _lido.withdrawalQueue.getWithdrawalStatus(_allVetoersUnstEthIds[vetoer]);

        uint256 lockableUnStEthsCount = 0;
        for (uint256 i = 0; i < vetoerUnstEthStatuses.length; ++i) {
            if (
                !vetoerUnstEthStatuses[i].isFinalized && !vetoerUnstEthStatuses[i].isClaimed
                    && vetoerUnstEthStatuses[i].owner == vetoer
            ) {
                lockableUnStEthsCount++;
            }
        }

        unStEthIds = new uint256[](lockableUnStEthsCount);

        if (lockableUnStEthsCount == 0) {
            return unStEthIds;
        }

        uint256 lastUnStEthIndex = 0;
        for (uint256 i = 0; i < vetoerUnstEthStatuses.length; ++i) {
            if (
                !vetoerUnstEthStatuses[i].isFinalized && !vetoerUnstEthStatuses[i].isClaimed
                    && vetoerUnstEthStatuses[i].owner == vetoer
            ) {
                unStEthIds[lastUnStEthIndex] = _allVetoersUnstEthIds[vetoer][i];
                lastUnStEthIndex++;
            }
        }
    }

    function _transferVetoerContractNonZeroUnStEthsTo(address vetoer, address to) internal {
        IWithdrawalQueue.WithdrawalRequestStatus[] memory vetoerUnstEthStatuses =
            _lido.withdrawalQueue.getWithdrawalStatus(_allVetoersUnstEthIds[vetoer]);

        for (uint256 i = 0; i < vetoerUnstEthStatuses.length; ++i) {
            if (
                !vetoerUnstEthStatuses[i].isFinalized && !vetoerUnstEthStatuses[i].isClaimed
                    && vetoerUnstEthStatuses[i].owner == vetoer
            ) {
                vm.prank(vetoer);
                _lido.withdrawalQueue.transferFrom(vetoer, to, _allVetoersUnstEthIds[vetoer][i]);
                _allVetoersUnstEthIds[to].push(_allVetoersUnstEthIds[vetoer][i]);
            }
        }
        delete _allVetoersUnstEthIds[vetoer];
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

        uint256[] memory claimableETH = _lido.withdrawalQueue.getClaimableEther(unclaimedUnStEthIds, hints);
        uint256 expectedTotalClaimableETH;
        for (uint256 i = 0; i < claimableETH.length; ++i) {
            expectedTotalClaimableETH += claimableETH[i];
        }

        uint256 escrowBalanceBefore = address(rqEscrow).balance;
        rqEscrow.claimUnstETH(unclaimedUnStEthIds, hints);
        uint256 escrowBalanceAfter = address(rqEscrow).balance;

        assertEq(escrowBalanceAfter - escrowBalanceBefore, expectedTotalClaimableETH);

        _vetoersClaimedETH[vetoer] = expectedTotalClaimableETH;
    }

    function _withdrawEthByVetoerUnStEths(address vetoer, IRageQuitEscrow rqEscrow) internal {
        if (_lockedUnStEthIds[vetoer].length > 0) {
            uint256 vetoerETHBefore = vetoer.balance;

            vm.startPrank(vetoer);
            rqEscrow.withdrawETH(_lockedUnStEthIds[vetoer]);
            vm.stopPrank();

            uint256 vetoerETHAfter = vetoer.balance;
            assertEq(vetoerETHAfter - vetoerETHBefore, _vetoersClaimedETH[vetoer]);
        }
    }

    function _getVetoerUnStEthBalances(address vetoer) internal view returns (uint256 shares, uint256 stEthAmount) {
        uint256[] memory ids = _allVetoersUnstEthIds[vetoer];
        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalStatuses =
            _lido.withdrawalQueue.getWithdrawalStatus(ids);

        for (uint256 i = 0; i < withdrawalStatuses.length; ++i) {
            if (
                !withdrawalStatuses[i].isFinalized && !withdrawalStatuses[i].isClaimed
                    && withdrawalStatuses[i].owner == vetoer
            ) {
                shares += withdrawalStatuses[i].amountOfShares;
                stEthAmount += withdrawalStatuses[i].amountOfStETH;
            }
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
