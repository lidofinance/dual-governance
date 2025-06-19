// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Random} from "../utils/random.sol";
import {LidoUtils} from "../utils/lido-utils.sol";
import {DGRegressionTestSetup, ISignallingEscrow, DGState} from "../utils/integration-tests.sol";
import {ETHValue} from "contracts/types/ETHValue.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {SharesValue} from "contracts/types/SharesValue.sol";
import {PercentsD16, PercentD16, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";
import {IWithdrawalQueue} from "test/utils/interfaces/IWithdrawalQueue.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";
import {Escrow} from "contracts/Escrow.sol";

import {DecimalsFormatting} from "test/utils/formatting.sol";
import {UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";

enum SimulationActionType {
    SubmitStETH,
    SubmitWstETH,
    //
    WithdrawStETH,
    WithdrawWstETH,
    //
    ClaimUnstETH,
    //
    LockStETH,
    LockWstETH,
    LockUnstETH,
    //
    MarkUnstETHFinalized,
    //
    UnlockStETH,
    UnlockWstETH,
    UnlockUnstETH,
    //
    AccidentalETHTransfer,
    AccidentalStETHTransfer,
    AccidentalWstETHTransfer,
    AccidentalUnstETHTransfer,
    //
    WithdrawStETHRealHolder,
    WithdrawWstETHRealHolder,
    ClaimUnstETHRealHolder,
    //
    LockStETHRealHolder,
    LockWstETHRealHolder
}

struct AccountDetails {
    mapping(address escrow => uint256 balance) stETHSharesBalanceLockedInEscrow;
    mapping(address escrow => uint256 balance) wstETHBalanceLockedInEscrow;
    mapping(address escrow => uint256[] ids) unstETHIdsLockedInEscrow;
    uint256[] unstETHIdsRequested;
    uint256 stETHSubmitted;
    uint256 wstETHSubmitted;
    uint256 sharesBalanceBefore;
    uint256 stETHBalanceBefore;
    uint256 ethBalanceBefore;
}

library Uint256ArrayBuilder {
    struct Context {
        uint256 size;
        uint256[] items;
    }

    function create(uint256 capacity) internal pure returns (Context memory res) {
        res.items = new uint256[](capacity);
    }

    function addItem(Context memory self, uint256 item) internal pure {
        self.items[self.size++] = item;
    }

    function getResult(Context memory self) internal pure returns (uint256[] memory res) {
        res = new uint256[](self.size);

        for (uint256 i = 0; i < self.size; ++i) {
            res[i] = self.items[i];
        }
    }

    function getSorted(Context memory self) internal pure returns (uint256[] memory res) {
        res = new uint256[](self.size);

        for (uint256 i = 0; i < self.size; ++i) {
            res[i] = self.items[i];
        }

        return _sort(res);
    }

    function _sort(uint256[] memory arr) private pure returns (uint256[] memory) {
        if (arr.length == 0) {
            return arr;
        }

        uint256 n = arr.length;

        for (uint256 i = 0; i < n - 1; i++) {
            for (uint256 j = 0; j < n - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    // Swap arr[j] and arr[j+1]
                    (arr[j], arr[j + 1]) = (arr[j + 1], arr[j]);
                }
            }
        }

        return arr;
    }
}

library SimulationActionsSet {
    struct Context {
        bool[] flags;
    }

    uint256 private constant _ACTION_TYPES_COUNT = uint256(uint8(type(SimulationActionType).max)) + 1;

    function create() internal pure returns (Context memory res) {
        res.flags = new bool[](_ACTION_TYPES_COUNT);
    }

    function add(Context memory self, SimulationActionType actionType) internal pure {
        self.flags[uint8(actionType)] = true;
    }

    function has(Context memory self, SimulationActionType actionType) internal pure returns (bool) {
        return self.flags[uint8(actionType)];
    }

    function isEmpty(Context memory self) internal pure returns (bool) {
        for (uint256 i = 0; i < _ACTION_TYPES_COUNT; ++i) {
            if (self.flags[i]) {
                return false;
            }
        }
        return true;
    }
}

uint256 constant WITHDRAWAL_QUEUE_REQUEST_MAX_AMOUNT = 1000 ether;

uint256 constant MIN_ST_ETH_WITHDRAW_AMOUNT = 1000 wei;
uint256 constant MAX_ST_ETH_WITHDRAW_AMOUNT = 30_000 ether;

uint256 constant MIN_WST_ETH_WITHDRAW_AMOUNT = 1000 wei;
uint256 constant MAX_WST_ETH_WITHDRAW_AMOUNT = 30_000 ether;

// TODO: 3 times more than real slot duration to speed up test. Must not affect correctness of the test
uint256 constant SLOT_DURATION = 3 * 1 hours;
uint256 constant SIMULATION_ACCOUNTS = 512;
uint256 constant SIMULATION_DURATION = 365 days;

uint256 constant MIN_ST_ETH_SUBMIT_AMOUNT = 0.1 ether;
uint256 constant MAX_ST_ETH_SUBMIT_AMOUNT = 750 ether;

uint256 constant MIN_WST_ETH_SUBMIT_AMOUNT = 0.1 ether;
uint256 constant MAX_WST_ETH_SUBMIT_AMOUNT = 500 ether;

uint256 constant MIN_ACCIDENTAL_TRANSFER_AMOUNT = 0.1 ether;
uint256 constant MAX_ACCIDENTAL_TRANSFER_AMOUNT = 1_000 ether;

uint256 constant MIN_ACCIDENTAL_UNSTETH_TRANSFER_AMOUNT = 1;
uint256 constant MAX_ACCIDENTAL_UNSTETH_TRANSFER_AMOUNT = 1_000 ether;

uint256 constant ORACLE_REPORT_FREQUENCY = 24 hours;

contract EscrowSolvencyTest is DGRegressionTestSetup {
    using Random for Random.Context;
    using DecimalsFormatting for uint256;
    using LidoUtils for LidoUtils.Context;
    using Uint256ArrayBuilder for Uint256ArrayBuilder.Context;
    using SimulationActionsSet for SimulationActionsSet.Context;

    PercentD16 immutable LOCK_ST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(100_00);
    PercentD16 immutable LOCK_WST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(2_75);
    PercentD16 immutable LOCK_UNST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(2_00);

    PercentD16 immutable UNLOCK_ST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(1_00);
    PercentD16 immutable UNLOCK_WST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(75);
    PercentD16 immutable UNLOCK_UNST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(50);

    PercentD16 immutable MARK_UNST_ETH_FINALIZED_PROBABILITY = PercentsD16.fromBasisPoints(1_25);

    PercentD16 immutable SUBMIT_STETH_PROBABILITY = PercentsD16.fromBasisPoints(3_00);
    PercentD16 immutable SUBMIT_WSTETH_PROBABILITY = PercentsD16.fromBasisPoints(3_00);

    PercentD16 immutable WITHDRAW_STETH_PROBABILITY = PercentsD16.fromBasisPoints(50);
    PercentD16 immutable WITHDRAW_WSTETH_PROBABILITY = PercentsD16.fromBasisPoints(50);
    PercentD16 immutable CLAIM_UNSTETH_PROBABILITY = PercentsD16.fromBasisPoints(50);

    PercentD16 immutable ACCIDENTAL_ETH_TRANSFER_PROBABILITY = PercentsD16.fromBasisPoints(10);
    PercentD16 immutable ACCIDENTAL_STETH_TRANSFER_PROBABILITY = PercentsD16.fromBasisPoints(10);
    PercentD16 immutable ACCIDENTAL_WSTETH_TRANSFER_PROBABILITY = PercentsD16.fromBasisPoints(10);
    PercentD16 immutable ACCIDENTAL_UNSTETH_TRANSFER_PROBABILITY = PercentsD16.fromBasisPoints(10);

    PercentD16 immutable WITHDRAW_STETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(50);
    PercentD16 immutable WITHDRAW_WSTETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(50);
    PercentD16 immutable CLAIM_UNSTETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(50);

    PercentD16 immutable LOCK_STETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(50);
    PercentD16 immutable LOCK_WSTETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(50);

    PercentD16 immutable NEGATIVE_REBASE_PROBABILITY = PercentsD16.fromBasisPoints(5);

    uint256 internal _totalLockedStETH = 0;
    uint256 internal _totalLockedWstETH = 0;
    uint256 internal _totalLockedUnstETH = 0;

    uint256 internal _totalUnlockedStETHShares = 0;
    uint256 internal _totalUnlockedWstETH = 0;
    uint256 internal _totalUnlockedUnstETHCount = 0;

    uint256 internal _totalSubmittedStETH = 0;
    uint256 internal _totalSubmittedWstETH = 0;

    uint256 internal _totalWithdrawnStETH = 0;
    uint256 internal _totalWithdrawnWstETH = 0;

    uint256 internal _totalAccidentalETHTransferAmount = 0;
    uint256 internal _totalAccidentalStETHTransferAmount = 0;
    uint256 internal _totalAccidentalWstETHTransferAmount = 0;
    uint256 internal _totalAccidentalUnstETHTransferAmount = 0;

    uint256 internal _totalNegativeRebaseCoount = 0;

    Escrow[] internal _rageQuitEscrows;
    mapping(Escrow escrow => Escrow.SignallingEscrowDetails details) internal _escrowDetails;

    mapping(address account => AccountDetails details) internal _accountsDetails;
    address[] internal _wstETHRealHolders;
    address[] internal _stETHRealHolders;
    address[] internal _allRealHolders;

    address[] internal _simulationAccounts;

    address[] internal _allAccounts;

    Random.Context internal _random;
    mapping(SimulationActionType actionType => uint256 emittedCount) internal _actionsCounters;

    uint256 internal _lastOracleReportTimestamp;
    uint256 internal _lastWithdrawalsFinalizationTimestamp;
    uint256 internal _nextFrameStart;

    address internal immutable MOCK_VETOER = makeAddr("MOCK_VETOER");

    function setUp() external {
        _loadOrDeployDGSetup();
        _random = Random.create(block.timestamp);
        _nextFrameStart = _lido.getReportTimeElapsed().nextFrameStart;

        _setupAccounts();

        // TODO: remove when test is finished. Currently preserved for debug purposes

        // _setupStETHBalance(MOCK_VETOER, PercentsD16.fromBasisPoints(20_00));

        // _lockStETH(MOCK_VETOER, _getSecondSealRageQuitSupport());
        // _wait(_getVetoSignallingMaxDuration());
        // _activateNextState();
        // _wait(_getVetoSignallingDeactivationMaxDuration());
        // _activateNextState();
        // _assertRageQuitState();
    }

    function _getDGStateName(DGState dgState) internal pure returns (string memory) {
        if (dgState == DGState.Normal) {
            return "Normal";
        } else if (dgState == DGState.VetoSignalling) {
            return "VetoSignalling";
        } else if (dgState == DGState.VetoSignalling) {
            return "VetoSignalling";
        } else if (dgState == DGState.VetoSignallingDeactivation) {
            return "VetoSignallingDeactivation";
        } else if (dgState == DGState.VetoCooldown) {
            return "VetoCooldown";
        } else if (dgState == DGState.RageQuit) {
            return "RageQuit";
        } else {
            revert("Invalid DG state");
        }
    }

    function testFork_SolvencySimulation() external {
        {
            // Note: simulation test may take significant time to pass
            // TODO: add this check after list of real holders will be updated to block after DG deployment
            // || vm.envOr("FORK_BLOCK_NUMBER", uint256(0)) != 21888569
            if (!vm.envOr("RUN_SOLVENCY_SIMULATION_TEST", false)) {
                vm.skip(
                    true,
                    "To enable this test set the env variable RUN_SOLVENCY_SIMULATION_TEST=true and FORK_BLOCK_NUMBER=21888569"
                );
                return;
            }
        }

        uint256 nextRageQuitOperationDelay = 0;
        uint256 lastRageQuitOperationTimestamp = 0;
        uint256 shareRateBefore = _lido.stETH.getPooledEthByShares(10 ** 18);
        uint256 iterations = 0;
        Escrow vetoSignallingEscrow =
            Escrow(payable(address(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow())));
        uint256 minWithdrawalsBatchSize = vetoSignallingEscrow.MIN_WITHDRAWALS_BATCH_SIZE();
        _escrowDetails[vetoSignallingEscrow] = vetoSignallingEscrow.getSignallingEscrowDetails();

        {
            uint256 simulationEndTimestamp = block.timestamp + SIMULATION_DURATION;
            DGState currentDGState = _dgDeployedContracts.dualGovernance.getPersistedState();

            console.log("Initial share rate: %s", _lido.stETH.getPooledEthByShares(10 ** 18).formatEther());
            console.log("Initial stETH Total Supply: %s", _lido.stETH.totalSupply().formatEther());
            console.log(
                "before simulation block number: %d, before simulation timestamp: %d", block.number, block.timestamp
            );
            console.log("Initial DG state: %s", _getDGStateName(currentDGState));

            while (block.timestamp < simulationEndTimestamp) {
                SimulationActionsSet.Context memory actions = _getRandomUniqueActionsSet();

                if (actions.has(SimulationActionType.SubmitStETH)) {
                    _submitStETHByRandomAccount();
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.SubmitWstETH)) {
                    _submitWstETHByRandomAccount();
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.WithdrawStETH)) {
                    _withdrawStETHByRandomAccount(_simulationAccounts);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.WithdrawWstETH)) {
                    _withdrawWstETHByRandomAccount(_simulationAccounts);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.LockStETH)) {
                    _lockStETHInSignallingEscrowByRandomAccount(_simulationAccounts);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.LockWstETH)) {
                    _lockWstETHInSignallingEscrowByRandomAccount(_simulationAccounts);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.LockUnstETH)) {
                    _lockUnstETHByRandomAccount();
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.MarkUnstETHFinalized)) {
                    _markRandomUnstETHFinalized();
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.ClaimUnstETH)) {
                    _claimUnstETHByRandomAccount();
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.UnlockStETH)) {
                    _unlockStETHByRandomAccount();
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.UnlockWstETH)) {
                    _unlockWstETHByRandomAccount();
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.UnlockUnstETH)) {
                    _unlockUnstETHByRandomAccount();
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.AccidentalETHTransfer)) {
                    _accidentalETHTransfer(_allAccounts);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.AccidentalStETHTransfer)) {
                    _accidentalStETHTransfer(_allAccounts);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.AccidentalWstETHTransfer)) {
                    _accidentalWstETHTransfer(_allAccounts);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.AccidentalUnstETHTransfer)) {
                    _accidentalUnstETHTransfer(_allAccounts);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.WithdrawStETHRealHolder)) {
                    _withdrawStETHByRandomAccount(_stETHRealHolders);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.WithdrawWstETHRealHolder)) {
                    _withdrawWstETHByRandomAccount(_wstETHRealHolders);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.LockStETHRealHolder)) {
                    _lockStETHInSignallingEscrowByRandomAccount(_stETHRealHolders);
                    _mineBlock();
                }

                if (actions.has(SimulationActionType.LockWstETHRealHolder)) {
                    _lockWstETHInSignallingEscrowByRandomAccount(_wstETHRealHolders);
                    _mineBlock();
                }

                if (actions.isEmpty()) {
                    _mineBlock();
                }

                // Oracle report and rebase
                if (_lastOracleReportTimestamp + ORACLE_REPORT_FREQUENCY < block.timestamp) {
                    _lastOracleReportTimestamp = block.timestamp;

                    uint256 requestIdToFinalize = _random.nextUint256(
                        _lido.withdrawalQueue.getLastFinalizedRequestId() + 1,
                        _lido.withdrawalQueue.getLastRequestId() + 1
                    );

                    uint256 rebaseAmount;
                    if (_getRandomProbability() < NEGATIVE_REBASE_PROBABILITY) {
                        rebaseAmount = _random.nextUint256(HUNDRED_PERCENT_D16 - 8_000 gwei, HUNDRED_PERCENT_D16);
                        _totalNegativeRebaseCoount++;
                    } else {
                        rebaseAmount = _random.nextUint256(HUNDRED_PERCENT_D16, HUNDRED_PERCENT_D16 + 80_000 gwei);
                    }

                    _lido.performRebase(PercentsD16.from(rebaseAmount), requestIdToFinalize);
                }

                // Activate next state if needed
                DGState effectiveDGState = _dgDeployedContracts.dualGovernance.getEffectiveState();
                if (currentDGState != effectiveDGState) {
                    if (currentDGState == DGState.RageQuit && effectiveDGState != DGState.RageQuit) {
                        console.log(">>> Exiting RageQuit state");
                    }
                    console.log(
                        ">>> DG State changed from %s to %s",
                        _getDGStateName(currentDGState),
                        _getDGStateName(effectiveDGState)
                    );
                    _activateNextState();
                    if (currentDGState != DGState.RageQuit && effectiveDGState == DGState.RageQuit) {
                        _rageQuitEscrows.push(
                            Escrow(payable(address(_dgDeployedContracts.dualGovernance.getRageQuitEscrow())))
                        );

                        Escrow newSignallingEscrow =
                            Escrow(payable(address(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow())));
                        _escrowDetails[newSignallingEscrow] = newSignallingEscrow.getSignallingEscrowDetails();
                    }
                    currentDGState = effectiveDGState;
                }

                if (
                    currentDGState == DGState.RageQuit
                        && block.timestamp >= lastRageQuitOperationTimestamp + nextRageQuitOperationDelay
                ) {
                    nextRageQuitOperationDelay = _random.nextUint256(12 hours, 36 hours);
                    lastRageQuitOperationTimestamp = block.timestamp;
                    Escrow rageQuitEscrow =
                        Escrow(payable(address(_dgDeployedContracts.dualGovernance.getRageQuitEscrow())));
                    bool isWithdrawalsBatchesClosed = rageQuitEscrow.isWithdrawalsBatchesClosed();
                    if (!isWithdrawalsBatchesClosed) {
                        uint256 requestBatchSize = _random.nextUint256(minWithdrawalsBatchSize, 128);
                        uint256 lastUnstETHIdBefore = _lido.withdrawalQueue.getLastRequestId();
                        rageQuitEscrow.requestNextWithdrawalsBatch(requestBatchSize);
                        uint256 lastUnstETHIdAfter = _lido.withdrawalQueue.getLastRequestId();
                        console.log(
                            ">>> Requesting %s next withdrawals batch: [%d, %d]",
                            lastUnstETHIdAfter - lastUnstETHIdBefore,
                            lastUnstETHIdBefore + 1,
                            lastUnstETHIdAfter
                        );
                    }
                    uint256 unclaimedUnstETHIds = rageQuitEscrow.getUnclaimedUnstETHIdsCount();

                    for (uint256 i = 0; i < _allAccounts.length; ++i) {
                        address account = _allAccounts[i];
                        uint256[] memory lockedUnstETHIds = rageQuitEscrow.getVetoerUnstETHIds(account);

                        Uint256ArrayBuilder.Context memory unstETHIdsToClaimBuilder =
                            Uint256ArrayBuilder.create(lockedUnstETHIds.length);
                        if (lockedUnstETHIds.length > 0) {
                            IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
                                _lido.withdrawalQueue.getWithdrawalStatus(lockedUnstETHIds);
                            for (uint256 j = 0; j < statuses.length; ++j) {
                                if (statuses[j].isFinalized && !statuses[j].isClaimed) {
                                    unstETHIdsToClaimBuilder.addItem(lockedUnstETHIds[j]);
                                }
                            }
                        }
                        if (unstETHIdsToClaimBuilder.size > 0) {
                            uint256[] memory unstETHIdsToClaim = unstETHIdsToClaimBuilder.getSorted();
                            uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
                                unstETHIdsToClaim, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
                            );
                            address claimer = _getRandomSimulationAccount();
                            vm.prank(claimer);
                            rageQuitEscrow.claimUnstETH(unstETHIdsToClaim, hints);
                            console.log(
                                ">>> Account's %s claimed %s unstETH NFTs by account %s",
                                account,
                                unstETHIdsToClaim.length,
                                claimer
                            );
                        }
                    }

                    if (unclaimedUnstETHIds > 0) {
                        uint256 claimType = _random.nextUint256();
                        uint256 unstETHIdsCount = _random.nextUint256(1, 128);
                        uint256[] memory unstETHIds = rageQuitEscrow.getNextWithdrawalBatch(unstETHIdsCount);
                        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
                            _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);

                        bool isAllBatchRequestsFinalized = true;
                        for (uint256 i = 0; i < statuses.length; ++i) {
                            if (!statuses[i].isFinalized) {
                                isAllBatchRequestsFinalized = false;
                                // console.log("Not all requests for batch request is finalized yet. Waiting...");
                                break;
                            }
                        }

                        if (isAllBatchRequestsFinalized) {
                            console.log(
                                ">>> Claiming next withdrawals batch [%d, %d]",
                                unstETHIds[0],
                                unstETHIds[unstETHIds.length - 1]
                            );

                            string memory claimedRanges = "";
                            uint256 startUnstETHId = unstETHIds[0];
                            for (uint256 i = 1; i < unstETHIds.length; ++i) {
                                uint256 prevUnstETHId = unstETHIds[i - 1];
                                uint256 currentUnstETHId = unstETHIds[i];
                                if (currentUnstETHId != prevUnstETHId + 1) {
                                    claimedRanges = string.concat(
                                        claimedRanges, vm.toString(startUnstETHId), "-", vm.toString(prevUnstETHId), ","
                                    );
                                    startUnstETHId = currentUnstETHId;
                                }
                                if (i == unstETHIds.length - 1) {
                                    claimedRanges = string.concat(
                                        claimedRanges,
                                        vm.toString(startUnstETHId),
                                        "-",
                                        vm.toString(currentUnstETHId),
                                        ","
                                    );
                                }
                            }

                            console.log(">>> Claiming batch ranges ids: [%s]", claimedRanges);

                            if (claimType % 2 == 0) {
                                rageQuitEscrow.claimNextWithdrawalsBatch(unstETHIdsCount);
                            } else {
                                uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
                                    unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
                                );
                                rageQuitEscrow.claimNextWithdrawalsBatch(unstETHIds[0], hints);
                                // TODO: add checks that was withdrawn "correct" amount of ETH
                            }
                        }
                    }

                    if (isWithdrawalsBatchesClosed && unclaimedUnstETHIds == 0) {
                        Escrow.RageQuitEscrowDetails memory details = rageQuitEscrow.getRageQuitEscrowDetails();
                        if (!details.isRageQuitExtensionPeriodStarted) {
                            console.log(">>> Start rage quit extension period");
                            rageQuitEscrow.startRageQuitExtensionPeriod();
                        }
                    }
                }

                // Handle RageQuit Escrow ETH withdrawals
                for (uint256 i = 0; i < _rageQuitEscrows.length; ++i) {
                    Escrow escrow = _rageQuitEscrows[i];
                    Escrow.RageQuitEscrowDetails memory escrowDetails = escrow.getRageQuitEscrowDetails();
                    if (
                        escrowDetails.isRageQuitExtensionPeriodStarted
                            && block.timestamp
                                > escrowDetails.rageQuitExtensionPeriodStartedAt.toSeconds()
                                    + escrowDetails.rageQuitExtensionPeriodDuration.toSeconds()
                                    + escrowDetails.rageQuitEthWithdrawalsDelay.toSeconds()
                    ) {
                        for (uint256 j = 0; j < _allAccounts.length; ++j) {
                            address account = _allAccounts[j];
                            vm.startPrank(account);
                            if (escrow.getVetoerDetails(account).unstETHIdsCount > 0) {
                                uint256[] memory unstETHIds = escrow.getVetoerUnstETHIds(account);

                                Escrow.LockedUnstETHDetails[] memory unstETHDetails =
                                    escrow.getLockedUnstETHDetails(unstETHIds);

                                Uint256ArrayBuilder.Context memory unclaimedUnstETHIdsBuilder =
                                    Uint256ArrayBuilder.create(unstETHIds.length);

                                uint256 unfinalizedUnstETHCount = 0;
                                for (uint256 k = 0; k < unstETHIds.length; ++k) {
                                    console.log(
                                        "UnstETH with id %d has status %d",
                                        unstETHIds[k],
                                        uint8(unstETHDetails[k].status)
                                    );
                                    if (
                                        unstETHDetails[k].status == UnstETHRecordStatus.Locked
                                            || unstETHDetails[k].status == UnstETHRecordStatus.Finalized
                                    ) {
                                        unclaimedUnstETHIdsBuilder.addItem(unstETHIds[k]);
                                    }
                                    if (unstETHDetails[k].status != UnstETHRecordStatus.Withdrawn) {
                                        unfinalizedUnstETHCount += 1;
                                    }
                                }

                                uint256[] memory unclaimedUnstETHIds = unclaimedUnstETHIdsBuilder.getSorted();

                                if (unclaimedUnstETHIds.length > 0) {
                                    uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
                                        unclaimedUnstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
                                    );
                                    escrow.claimUnstETH(unstETHIds, hints);
                                }
                                if (unfinalizedUnstETHCount > 0) {
                                    escrow.withdrawETH(unstETHIds);
                                }
                            }
                            escrow.withdrawETH();
                            vm.stopPrank();
                        }
                    }
                }
                iterations++;
            }
            console.log("Simulation finished after %d iterations", iterations);

            console.log(
                "After simulation block number: %d, after simulation timestamp: %d", block.number, block.timestamp
            );
            console.log("After simulation stETH Total Supply: %s", _lido.stETH.totalSupply().formatEther());
            console.log("After simulation share rate: %s", _lido.stETH.getPooledEthByShares(10 ** 18).formatEther());
            console.log("Negative rebase count: %d", _totalNegativeRebaseCoount);

            console.log("Actions Count:");
            console.log(
                "  - Submit stETH count: %s, total submitted amount: %s",
                _actionsCounters[SimulationActionType.SubmitStETH],
                _totalSubmittedStETH.formatEther()
            );
            console.log(
                "  - Submit wstETH count: %s, total submitted amount: %s",
                _actionsCounters[SimulationActionType.SubmitWstETH],
                _totalSubmittedWstETH.formatEther()
            );
            console.log(
                "  - Withdraw stETH count: %s, total withdrawn amount: %s",
                _actionsCounters[SimulationActionType.WithdrawStETH],
                _totalWithdrawnStETH.formatEther()
            );
            console.log(
                "  - Withdraw wstETH count: %s, total withdrawn amount: %s",
                _actionsCounters[SimulationActionType.WithdrawWstETH],
                _totalWithdrawnWstETH.formatEther()
            );
            console.log(
                "  - Lock stETH count: %s, total locked stETH: %s",
                _actionsCounters[SimulationActionType.LockStETH],
                _totalLockedStETH.formatEther()
            );
            console.log(
                "  - Lock wstETH count: %s, total locked wstETH: %s",
                _actionsCounters[SimulationActionType.LockWstETH],
                _totalLockedWstETH.formatEther()
            );
            console.log(
                "  - Lock unstETH actions count: %d, total locked unstETH: %d",
                _actionsCounters[SimulationActionType.LockUnstETH],
                _totalLockedUnstETH
            );
            console.log(
                "  - Unlock stETH count: %s, total unlocked stETH: %s",
                _actionsCounters[SimulationActionType.UnlockStETH],
                _totalUnlockedStETHShares.formatEther()
            );
            console.log(
                "  - Unlock wstETH count: %s, total unlocked wstETH: %s",
                _actionsCounters[SimulationActionType.UnlockWstETH],
                _totalUnlockedWstETH.formatEther()
            );
            console.log(
                "  - Unlock unstETH actions count: %d, total unlocked unstETH count: %d",
                _actionsCounters[SimulationActionType.UnlockUnstETH],
                _totalUnlockedUnstETHCount
            );
            console.log(
                "  - Accidental ETH transfer actions count: %d, total transferred ETH count: %s",
                _actionsCounters[SimulationActionType.AccidentalETHTransfer],
                _totalAccidentalETHTransferAmount.formatEther()
            );
            console.log(
                "  - Accidental stETH transfer actions count: %d, total transferred stETH amount: %s",
                _actionsCounters[SimulationActionType.AccidentalStETHTransfer],
                _totalAccidentalStETHTransferAmount.formatEther()
            );
            console.log(
                "  - Accidental wstETH transfer actions count: %d, total transferred wstETH amount: %s",
                _actionsCounters[SimulationActionType.AccidentalWstETHTransfer],
                _totalAccidentalWstETHTransferAmount.formatEther()
            );
            console.log(
                "  - Accidental unstETH transfer actions count: %d, total transferred unstETH count: %s",
                _actionsCounters[SimulationActionType.AccidentalUnstETHTransfer],
                _totalAccidentalUnstETHTransferAmount.formatEther()
            );
            console.log(
                "  - Withdraw stETH real holder actions count: %d",
                _actionsCounters[SimulationActionType.WithdrawStETHRealHolder]
            );
            console.log(
                "  - Withdraw wstETH real holder actions count: %d",
                _actionsCounters[SimulationActionType.WithdrawWstETHRealHolder]
            );
            console.log(
                "  - Claim unstETH real holder actions count: %d",
                _actionsCounters[SimulationActionType.ClaimUnstETHRealHolder]
            );
            console.log(
                "  - Lock stETH real holder actions count: %d",
                _actionsCounters[SimulationActionType.LockStETHRealHolder]
            );
            console.log(
                "  - Lock wstETH real holder actions count: %d",
                _actionsCounters[SimulationActionType.LockWstETHRealHolder]
            );

            console.log(
                "  - Mark unstETH finalized count: %d", _actionsCounters[SimulationActionType.MarkUnstETHFinalized]
            );
            console.log("  - Claim unstETH count: %d", _actionsCounters[SimulationActionType.ClaimUnstETH]);

            ISignallingEscrow signallingEscrow =
                ISignallingEscrow(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow());
            console.log("RageQuits count: %d", _rageQuitEscrows.length);
            for (uint256 i = 0; i < _rageQuitEscrows.length; ++i) {
                console.log(
                    "RageQuit escrow %s. isRageQuit finalized: %s",
                    address(_rageQuitEscrows[i]),
                    _rageQuitEscrows[i].isRageQuitFinalized()
                );
                console.log(
                    "  - ETH balance: %s",
                    address(_rageQuitEscrows[i]),
                    address(_rageQuitEscrows[i]).balance.formatEther()
                );
            }

            console.log("Signalling Escrow Stats:");
            console.log("  - DG State: %s", _getDGStateName(_dgDeployedContracts.dualGovernance.getEffectiveState()));
            console.log("  - Rage Quit Support: %s", signallingEscrow.getRageQuitSupport().toUint256().format(16));
            console.log("  - stETH Balance: %s", _lido.stETH.balanceOf(address(signallingEscrow)).formatEther());
        }

        // Check that accounts balances changed as expected
        uint256 shareRateAfter = _lido.stETH.getPooledEthByShares(10 ** 18);

        for (uint256 i = 0; i < _allAccounts.length; ++i) {
            address account = _allAccounts[i];

            uint256 sharesLocked;
            for (uint256 j = 0; j < _rageQuitEscrows.length; ++j) {
                Escrow escrow = _rageQuitEscrows[j];
                Escrow.VetoerDetails memory vetoerDetails = escrow.getVetoerDetails(account);
                sharesLocked += vetoerDetails.stETHLockedShares.toUint256();
            }

            sharesLocked += _getVetoSignallingEscrow().getVetoerDetails(account).stETHLockedShares.toUint256();

            IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalStatuses =
                _lido.withdrawalQueue.getWithdrawalStatus(_accountsDetails[account].unstETHIdsRequested);

            for (uint256 j = 0; j < withdrawalStatuses.length; ++j) {
                if (!withdrawalStatuses[j].isClaimed) {
                    sharesLocked += withdrawalStatuses[j].amountOfShares;
                }
            }

            uint256 ethBalanceAfter = account.balance;
            uint256 stETHBalanceAfter = _lido.stETH.balanceOf(account);
            uint256 wstETHBalanceAfter = _lido.wstETH.balanceOf(account);

            uint256 holderBalanceBefore =
                _accountsDetails[account].ethBalanceBefore + _accountsDetails[account].stETHBalanceBefore;
            uint256 holderBalanceAfter = ethBalanceAfter + stETHBalanceAfter
                + _lido.stETH.getPooledEthByShares(wstETHBalanceAfter + sharesLocked);
            uint256 balanceEstimated = (holderBalanceBefore) * shareRateAfter / shareRateBefore;

            assert(holderBalanceAfter >= holderBalanceBefore);
            assert(holderBalanceAfter <= balanceEstimated);
        }

        // check accidental transfers
    }

    function _getRandomSimulationAccount() internal returns (address) {
        return _simulationAccounts[_random.nextUint256(SIMULATION_ACCOUNTS)];
    }

    function _getSimulationAccount(uint256 index) internal returns (address) {
        string memory accountName = string(bytes.concat("SIMULATION_ACC_", bytes(Strings.toString(index))));
        return makeAddr(accountName);
    }

    function _submitStETHByRandomAccount() internal {
        console.log(">>> Submitting stETH by random account");
        address account = _getRandomSimulationAccount();

        uint256 balance = account.balance;

        if (balance < MIN_ST_ETH_SUBMIT_AMOUNT) {
            return;
        }

        uint256 submitAmount =
            _random.nextUint256(MIN_ST_ETH_SUBMIT_AMOUNT, Math.min(balance, MAX_ST_ETH_SUBMIT_AMOUNT));

        vm.prank(account);
        _lido.stETH.submit{value: submitAmount}(address(0));

        _totalSubmittedStETH += submitAmount;

        _accountsDetails[account].stETHSubmitted += submitAmount;
    }

    function _submitWstETHByRandomAccount() internal {
        console.log(">>> Submitting wstETH by random account");
        address account = _getRandomSimulationAccount();
        uint256 balance = account.balance;

        if (balance < MIN_WST_ETH_SUBMIT_AMOUNT) {
            return;
        }

        uint256 submitAmount =
            _random.nextUint256(MIN_WST_ETH_SUBMIT_AMOUNT, Math.min(balance, MAX_WST_ETH_SUBMIT_AMOUNT));

        vm.startPrank(account);
        _lido.stETH.submit{value: submitAmount}(address(0));
        _lido.stETH.approve(address(_lido.wstETH), submitAmount);
        uint256 wstEthMinted = _lido.wstETH.wrap(submitAmount);
        vm.stopPrank();
        _totalSubmittedWstETH += wstEthMinted;

        _accountsDetails[account].wstETHSubmitted += wstEthMinted;
    }

    function _withdrawStETHByRandomAccount(address[] storage accounts) internal {
        console.log(">>> Withdrawing stETH by random account");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.stETH.balanceOf(account);
            if (balance < MIN_ST_ETH_WITHDRAW_AMOUNT) {
                continue;
            }

            //TODO: check
            uint256 batchSize = Math.min(balance, MAX_ST_ETH_WITHDRAW_AMOUNT) / WITHDRAWAL_QUEUE_REQUEST_MAX_AMOUNT;
            uint256 lastRequestAmount =
                Math.min(balance, MAX_ST_ETH_WITHDRAW_AMOUNT) % WITHDRAWAL_QUEUE_REQUEST_MAX_AMOUNT;
            if (lastRequestAmount > MIN_ST_ETH_WITHDRAW_AMOUNT) {
                batchSize += 1;
            }

            uint256 requestedAmount = 0;

            uint256[] memory withdrawalAmounts = new uint256[](batchSize);

            for (uint256 j = 0; j < batchSize; ++j) {
                if (j == batchSize - 1 && lastRequestAmount > MIN_ST_ETH_WITHDRAW_AMOUNT) {
                    withdrawalAmounts[j] = lastRequestAmount;
                } else {
                    withdrawalAmounts[j] = WITHDRAWAL_QUEUE_REQUEST_MAX_AMOUNT;
                }
                requestedAmount += withdrawalAmounts[j];
            }
            vm.startPrank(account);
            _lido.stETH.approve(address(_lido.withdrawalQueue), requestedAmount);
            uint256[] memory requestIds = _lido.withdrawalQueue.requestWithdrawals(withdrawalAmounts, account);
            vm.stopPrank();

            for (uint256 j = 0; j < requestIds.length; ++j) {
                _accountsDetails[account].unstETHIdsRequested.push(requestIds[j]);
            }
            _totalWithdrawnStETH += requestedAmount;
            console.log("Account %s withdrawn %s stETH.", account, requestedAmount.formatEther());
            console.log("Request ids: %s-%s", requestIds[0], requestIds[requestIds.length - 1]);

            return;
        }
    }

    function _withdrawWstETHByRandomAccount(address[] storage accounts) internal {
        console.log(">>> Withdrawing wstETH by random account");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.wstETH.balanceOf(account);
            if (balance < MIN_WST_ETH_WITHDRAW_AMOUNT) {
                continue;
            }

            uint256 wstETHRequestMaxAmount = _lido.stETH.getSharesByPooledEth(WITHDRAWAL_QUEUE_REQUEST_MAX_AMOUNT);
            uint256 batchSize = Math.min(balance, MAX_WST_ETH_WITHDRAW_AMOUNT) / wstETHRequestMaxAmount;
            uint256 lastRequestAmount = Math.min(balance, MAX_WST_ETH_WITHDRAW_AMOUNT) % wstETHRequestMaxAmount;
            if (lastRequestAmount > MIN_WST_ETH_WITHDRAW_AMOUNT) {
                batchSize += 1;
            }

            uint256 requestedAmount = 0;

            uint256[] memory withdrawalAmounts = new uint256[](batchSize);

            for (uint256 j = 0; j < batchSize; ++j) {
                if (j == batchSize - 1 && lastRequestAmount > MIN_WST_ETH_WITHDRAW_AMOUNT) {
                    withdrawalAmounts[j] = lastRequestAmount;
                } else {
                    withdrawalAmounts[j] = wstETHRequestMaxAmount;
                }
                requestedAmount += withdrawalAmounts[j];
            }
            vm.startPrank(account);
            _lido.wstETH.approve(address(_lido.withdrawalQueue), requestedAmount);
            uint256[] memory requestIds = _lido.withdrawalQueue.requestWithdrawalsWstETH(withdrawalAmounts, account);
            vm.stopPrank();

            for (uint256 j = 0; j < requestIds.length; ++j) {
                _accountsDetails[account].unstETHIdsRequested.push(requestIds[j]);
            }

            _totalWithdrawnWstETH += requestedAmount;
            console.log("Account %s withdrawn %s wstETH.", account, requestedAmount.formatEther());
            console.log("Request ids: %s-%s", requestIds[0], requestIds[requestIds.length - 1]);

            return;
        }
    }

    function _lockStETHInSignallingEscrowByRandomAccount(address[] storage accounts) internal {
        console.log(">>> Locking stETH in signalling escrow by random account");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.stETH.balanceOf(account);

            if (balance < MIN_ST_ETH_SUBMIT_AMOUNT) {
                continue;
            }

            uint256 lockAmount = Math.min(balance, MAX_ST_ETH_SUBMIT_AMOUNT);

            console.log(
                "Account %s locking %s stETH in signalling escrow",
                account,
                lockAmount.formatEther(),
                balance.formatEther()
            );

            _lockStETH(account, lockAmount);
            _totalLockedStETH += lockAmount;

            _accountsDetails[account].stETHSharesBalanceLockedInEscrow[_getCurrentEscrowAddress()] +=
                _lido.stETH.getSharesByPooledEth(lockAmount);

            return;
        }
    }

    function _lockWstETHInSignallingEscrowByRandomAccount(address[] storage accounts) internal {
        console.log(">>> Locking wstETH in signalling escrow by random account");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.wstETH.balanceOf(account);

            if (balance < MIN_ST_ETH_SUBMIT_AMOUNT) {
                continue;
            }

            uint256 lockAmount = Math.min(balance, MAX_ST_ETH_SUBMIT_AMOUNT);

            _lockWstETH(account, lockAmount);
            _totalLockedWstETH += lockAmount;

            _accountsDetails[account].wstETHBalanceLockedInEscrow[_getCurrentEscrowAddress()] += lockAmount;

            return;
        }
    }

    function _lockUnstETHByRandomAccount() internal {
        console.log(">>> Locking unstETH by random account");
        uint256 lastFinalizedRequestId = _lido.withdrawalQueue.getLastFinalizedRequestId();
        uint256 maxRequestsToLock = _random.nextUint256(1, 64);
        Uint256ArrayBuilder.Context memory requestsArrayBuilder = Uint256ArrayBuilder.create(maxRequestsToLock);

        for (uint256 i = 0; i < SIMULATION_ACCOUNTS; ++i) {
            address account = _getSimulationAccount(i);
            uint256 unstETHIdsCount = _lido.withdrawalQueue.balanceOf(account);

            if (unstETHIdsCount == 0) {
                continue;
            }

            uint256 countOfAddedRequestIds = 0;
            uint256[] memory requestIds = _lido.withdrawalQueue.getWithdrawalRequests(account);
            uint256[] memory randomRequestIndices = _random.nextPermutation(unstETHIdsCount);

            for (uint256 j = 0; j < unstETHIdsCount; ++j) {
                uint256 requestId = requestIds[randomRequestIndices[j]];

                if (requestId <= lastFinalizedRequestId) {
                    continue;
                }

                requestsArrayBuilder.addItem(requestId);
                countOfAddedRequestIds += 1;

                if (countOfAddedRequestIds >= maxRequestsToLock) {
                    break;
                }
            }

            if (requestsArrayBuilder.size > 0) {
                _lockUnstETH(account, requestsArrayBuilder.getResult());
                _totalLockedUnstETH += requestsArrayBuilder.size;

                for (uint256 j = 0; j < requestsArrayBuilder.size; ++j) {
                    _accountsDetails[account].unstETHIdsLockedInEscrow[_getCurrentEscrowAddress()].push(
                        requestsArrayBuilder.getResult()[j]
                    );
                }

                return;
            }
        }
    }

    function _claimUnstETHByRandomAccount() internal {
        _claimUnstETHByAnyOfAccounts(_simulationAccounts);
    }

    function _claimUnstETHByAnyOfRealHolder() internal {
        _claimUnstETHByAnyOfAccounts(_allRealHolders);
    }

    function _claimUnstETHByAnyOfAccounts(address[] memory accounts) internal {
        console.log(">>> Claiming unstETH by random account");
        uint256 maxRequestsToClaim = _random.nextUint256(1, 64);
        Uint256ArrayBuilder.Context memory requestsArrayBuilder = Uint256ArrayBuilder.create(maxRequestsToClaim);

        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 unstETHIdsCount = _lido.withdrawalQueue.balanceOf(account);

            if (unstETHIdsCount == 0) {
                continue;
            }

            uint256 countOfAddedRequestIds = 0;
            uint256[] memory requestIds = _lido.withdrawalQueue.getWithdrawalRequests(account);

            IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
                _lido.withdrawalQueue.getWithdrawalStatus(requestIds);

            uint256[] memory randomRequestIndices = _random.nextPermutation(unstETHIdsCount);

            for (uint256 j = 0; j < unstETHIdsCount; ++j) {
                uint256 requestId = requestIds[randomRequestIndices[j]];
                IWithdrawalQueue.WithdrawalRequestStatus memory status = statuses[randomRequestIndices[j]];

                if (status.isClaimed || !status.isFinalized) {
                    continue;
                }

                requestsArrayBuilder.addItem(requestId);
                countOfAddedRequestIds += 1;

                if (countOfAddedRequestIds >= maxRequestsToClaim) {
                    break;
                }
            }

            uint256[] memory requestIdsToClaim = requestsArrayBuilder.getSorted();

            if (requestIdsToClaim.length > 0) {
                uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
                    requestIdsToClaim, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
                );
                vm.prank(account);
                _lido.withdrawalQueue.claimWithdrawals(requestIdsToClaim, hints);

                return;
            }
        }
    }

    function _markRandomUnstETHFinalized() internal {
        console.log(">>> Marking random unstETH finalized");
        uint256[] memory requestIds = _lido.withdrawalQueue.getWithdrawalRequests(address(_getVetoSignallingEscrow()));
        if (requestIds.length == 0) {
            return;
        }

        uint256 randomRequestIdIndex = _random.nextUint256(0, requestIds.length);
        uint256 requestsCountToFinalize = Math.min(requestIds.length, _random.nextUint256(1, 128));
        Uint256ArrayBuilder.Context memory requestsArrayBuilder = Uint256ArrayBuilder.create(requestsCountToFinalize);

        for (uint256 i = 0; i < requestsCountToFinalize; ++i) {
            uint256 index = (randomRequestIdIndex + i) % requestIds.length;
            requestsArrayBuilder.addItem(requestIds[index]);
        }

        uint256[] memory requestIdsToFinalize = requestsArrayBuilder.getSorted();
        uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
            requestIdsToFinalize, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );

        _getVetoSignallingEscrow().markUnstETHFinalized(requestIdsToFinalize, hints);
    }

    function _unlockStETHByRandomAccount() internal {
        console.log(">>> Unlocking stETH by random account");
        address account = _getRandomSimulationAccount();
        ISignallingEscrow escrow = ISignallingEscrow(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow());
        Escrow.VetoerDetails memory details = escrow.getVetoerDetails(account);
        if (
            details.stETHLockedShares.toUint256() > 0
                && Timestamps.now() > escrow.getMinAssetsLockDuration().addTo(details.lastAssetsLockTimestamp)
        ) {
            _unlockStETH(account);
            _totalUnlockedStETHShares += details.stETHLockedShares.toUint256();
            assertApproxEqAbs(
                _accountsDetails[account].stETHSharesBalanceLockedInEscrow[_getCurrentEscrowAddress()]
                    + _accountsDetails[account].wstETHBalanceLockedInEscrow[_getCurrentEscrowAddress()],
                details.stETHLockedShares.toUint256(),
                2
            );

            _accountsDetails[account].stETHSharesBalanceLockedInEscrow[_getCurrentEscrowAddress()] = 0;
            _accountsDetails[account].wstETHBalanceLockedInEscrow[_getCurrentEscrowAddress()] = 0;
        }
    }

    function _unlockWstETHByRandomAccount() internal {
        console.log(">>> Unlocking wstETH by random account");
        address account = _getRandomSimulationAccount();
        ISignallingEscrow escrow = ISignallingEscrow(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow());
        Escrow.VetoerDetails memory details = escrow.getVetoerDetails(account);
        if (
            details.stETHLockedShares.toUint256() > 0
                && Timestamps.now() > escrow.getMinAssetsLockDuration().addTo(details.lastAssetsLockTimestamp)
        ) {
            _unlockWstETH(account);
            _totalUnlockedWstETH += details.stETHLockedShares.toUint256();

            assertApproxEqAbs(
                _accountsDetails[account].stETHSharesBalanceLockedInEscrow[_getCurrentEscrowAddress()]
                    + _accountsDetails[account].wstETHBalanceLockedInEscrow[_getCurrentEscrowAddress()],
                details.stETHLockedShares.toUint256(),
                2
            );

            _accountsDetails[account].stETHSharesBalanceLockedInEscrow[_getCurrentEscrowAddress()] = 0;
            _accountsDetails[account].wstETHBalanceLockedInEscrow[_getCurrentEscrowAddress()] = 0;
        }
    }

    function _unlockUnstETHByRandomAccount() internal {
        console.log(">>> Unlocking unstETH by random account");
        address account = _getRandomSimulationAccount();
        ISignallingEscrow escrow = ISignallingEscrow(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow());
        Escrow.VetoerDetails memory details = escrow.getVetoerDetails(account);
        if (
            details.unstETHIdsCount > 0
                && Timestamps.now() > escrow.getMinAssetsLockDuration().addTo(details.lastAssetsLockTimestamp)
        ) {
            uint256 randomUnstETHIdsCountToWithdraw = _random.nextUint256(1, details.unstETHIdsCount);
            uint256[] memory lockedUnstETHIds = escrow.getVetoerUnstETHIds(account);
            uint256[] memory randomIndices = _random.nextPermutation(randomUnstETHIdsCountToWithdraw);
            Uint256ArrayBuilder.Context memory unstETHIdsBuilder =
                Uint256ArrayBuilder.create(randomUnstETHIdsCountToWithdraw);
            for (uint256 i = 0; i < randomUnstETHIdsCountToWithdraw; ++i) {
                unstETHIdsBuilder.addItem(lockedUnstETHIds[randomIndices[i]]);
            }
            _unlockUnstETH(account, unstETHIdsBuilder.getSorted());
            _totalUnlockedUnstETHCount += details.unstETHIdsCount;
        }
    }

    function _accidentalETHTransfer(address[] memory accounts) internal {
        console.log(">>> Accidental ETH transfer");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);
        address payable escrow = _getCurrentEscrowAddress();

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = account.balance;
            if (balance < MIN_ACCIDENTAL_TRANSFER_AMOUNT) {
                continue;
            }

            uint256 balanceBefore = escrow.balance;
            uint256 transferAmount =
                _random.nextUint256(MIN_ACCIDENTAL_TRANSFER_AMOUNT, Math.min(MAX_ACCIDENTAL_TRANSFER_AMOUNT, balance));
            vm.prank(account);
            new SelfDestructSender{value: transferAmount}(escrow);

            assertEq(escrow.balance, balanceBefore + transferAmount, "Escrow balance mismatch after transfer");
            _totalAccidentalETHTransferAmount += transferAmount;

            return;
        }
    }

    function _accidentalStETHTransfer(address[] memory accounts) internal {
        console.log(">>> Accidental stETH transfer");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);
        address payable escrow = _getCurrentEscrowAddress();

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.stETH.balanceOf(account);
            if (balance < MIN_ACCIDENTAL_TRANSFER_AMOUNT) {
                continue;
            }

            uint256 transferAmount = _random.nextUint256(MIN_ACCIDENTAL_TRANSFER_AMOUNT, MAX_ACCIDENTAL_TRANSFER_AMOUNT);
            vm.prank(account);
            _lido.stETH.transfer(escrow, transferAmount);

            _totalAccidentalStETHTransferAmount += transferAmount;

            return;
        }
    }

    function _accidentalWstETHTransfer(address[] memory accounts) internal {
        console.log(">>> Accidental wstETH transfer");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);
        address payable escrow = _getCurrentEscrowAddress();

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.wstETH.balanceOf(account);
            if (balance < MIN_ACCIDENTAL_TRANSFER_AMOUNT) {
                continue;
            }

            uint256 transferAmount = _random.nextUint256(MIN_ACCIDENTAL_TRANSFER_AMOUNT, MAX_ACCIDENTAL_TRANSFER_AMOUNT);
            vm.prank(account);
            _lido.wstETH.transfer(escrow, transferAmount);

            _totalAccidentalStETHTransferAmount += transferAmount;

            return;
        }
    }

    function _accidentalUnstETHTransfer(address[] memory accounts) internal {
        console.log(">>> Accidental unstETH transfer");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);
        address payable escrow = _getCurrentEscrowAddress();

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.stETH.balanceOf(account);
            if (balance < MIN_ACCIDENTAL_TRANSFER_AMOUNT) {
                continue;
            }

            vm.startPrank(account);
            uint256[] memory requestAmounts = new uint256[](1);
            requestAmounts[0] = _random.nextUint256(MIN_ACCIDENTAL_TRANSFER_AMOUNT, MAX_ACCIDENTAL_TRANSFER_AMOUNT);
            _lido.stETH.approve(address(_lido.withdrawalQueue), requestAmounts[0]);
            _lido.withdrawalQueue.requestWithdrawals(requestAmounts, escrow);
            vm.stopPrank();

            _totalAccidentalUnstETHTransferAmount += requestAmounts[0];

            return;
        }
    }

    function _mineBlock() internal {
        vm.warp(block.timestamp + SLOT_DURATION);
        vm.roll(block.number + 1);
    }

    function _getRandomUniqueActionsSet() internal returns (SimulationActionsSet.Context memory result) {
        result = SimulationActionsSet.create();

        if (_getRandomProbability() <= WITHDRAW_STETH_PROBABILITY) {
            result.add(SimulationActionType.WithdrawStETH);
            _actionsCounters[SimulationActionType.WithdrawStETH] += 1;
        }

        if (_getRandomProbability() <= WITHDRAW_WSTETH_PROBABILITY) {
            result.add(SimulationActionType.WithdrawWstETH);
            _actionsCounters[SimulationActionType.WithdrawWstETH] += 1;
        }

        if (_getRandomProbability() <= SUBMIT_STETH_PROBABILITY) {
            result.add(SimulationActionType.SubmitStETH);
            _actionsCounters[SimulationActionType.SubmitStETH] += 1;
        }

        if (_getRandomProbability() <= SUBMIT_WSTETH_PROBABILITY) {
            result.add(SimulationActionType.SubmitWstETH);
            _actionsCounters[SimulationActionType.SubmitWstETH] += 1;
        }

        if (_getRandomProbability() <= LOCK_ST_ETH_PROBABILITY) {
            result.add(SimulationActionType.LockStETH);
            _actionsCounters[SimulationActionType.LockStETH] += 1;
        }

        if (_getRandomProbability() <= LOCK_WST_ETH_PROBABILITY) {
            result.add(SimulationActionType.LockWstETH);
            _actionsCounters[SimulationActionType.LockWstETH] += 1;
        }

        if (_getRandomProbability() <= LOCK_UNST_ETH_PROBABILITY) {
            result.add(SimulationActionType.LockUnstETH);
            _actionsCounters[SimulationActionType.LockUnstETH] += 1;
        }

        if (_getRandomProbability() <= MARK_UNST_ETH_FINALIZED_PROBABILITY) {
            result.add(SimulationActionType.MarkUnstETHFinalized);
            _actionsCounters[SimulationActionType.MarkUnstETHFinalized] += 1;
        }

        if (_getRandomProbability() <= CLAIM_UNSTETH_PROBABILITY) {
            result.add(SimulationActionType.ClaimUnstETH);
            _actionsCounters[SimulationActionType.ClaimUnstETH] += 1;
        }

        if (_getRandomProbability() <= UNLOCK_ST_ETH_PROBABILITY) {
            result.add(SimulationActionType.UnlockStETH);
            _actionsCounters[SimulationActionType.UnlockStETH] += 1;
        }

        if (_getRandomProbability() <= UNLOCK_WST_ETH_PROBABILITY) {
            result.add(SimulationActionType.UnlockWstETH);
            _actionsCounters[SimulationActionType.UnlockWstETH] += 1;
        }

        if (_getRandomProbability() <= UNLOCK_UNST_ETH_PROBABILITY) {
            result.add(SimulationActionType.UnlockUnstETH);
            _actionsCounters[SimulationActionType.UnlockUnstETH] += 1;
        }

        if (_getRandomProbability() <= ACCIDENTAL_ETH_TRANSFER_PROBABILITY) {
            result.add(SimulationActionType.AccidentalETHTransfer);
            _actionsCounters[SimulationActionType.AccidentalETHTransfer] += 1;
        }

        if (_getRandomProbability() <= ACCIDENTAL_STETH_TRANSFER_PROBABILITY) {
            result.add(SimulationActionType.AccidentalStETHTransfer);
            _actionsCounters[SimulationActionType.AccidentalStETHTransfer] += 1;
        }

        if (_getRandomProbability() <= ACCIDENTAL_WSTETH_TRANSFER_PROBABILITY) {
            result.add(SimulationActionType.AccidentalWstETHTransfer);
            _actionsCounters[SimulationActionType.AccidentalWstETHTransfer] += 1;
        }

        if (_getRandomProbability() <= ACCIDENTAL_UNSTETH_TRANSFER_PROBABILITY) {
            result.add(SimulationActionType.AccidentalUnstETHTransfer);
            _actionsCounters[SimulationActionType.AccidentalUnstETHTransfer] += 1;
        }

        if (_getRandomProbability() <= WITHDRAW_STETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.WithdrawStETHRealHolder);
            _actionsCounters[SimulationActionType.WithdrawStETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= WITHDRAW_WSTETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.WithdrawWstETHRealHolder);
            _actionsCounters[SimulationActionType.WithdrawWstETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= CLAIM_UNSTETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.ClaimUnstETHRealHolder);
            _actionsCounters[SimulationActionType.ClaimUnstETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= LOCK_STETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.LockStETHRealHolder);
            _actionsCounters[SimulationActionType.LockStETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= LOCK_WSTETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.LockWstETHRealHolder);
            _actionsCounters[SimulationActionType.LockWstETHRealHolder] += 1;
        }
    }

    function _getRandomProbability() internal returns (PercentD16) {
        return PercentsD16.from(_random.nextUint256(HUNDRED_PERCENT_D16));
    }

    function _loadHoldersFromFile(string memory path) internal view returns (address[] memory) {
        string memory vetoersFileRaw = vm.readFile(path);
        bytes memory data = vm.parseJson(vetoersFileRaw);
        return abi.decode(data, (address[]));
    }

    function _loadHolders() internal {
        _stETHRealHolders = _loadHoldersFromFile("./test/regressions/complete-rage-quit-files/steth_vetoers.json");
        _wstETHRealHolders = _loadHoldersFromFile("./test/regressions/complete-rage-quit-files/wsteth_vetoers.json");
        for (uint256 i = 0; i < _stETHRealHolders.length; ++i) {
            _allRealHolders.push(_stETHRealHolders[i]);
            _allAccounts.push(_stETHRealHolders[i]);
        }
        for (uint256 i = 0; i < _wstETHRealHolders.length; ++i) {
            _allRealHolders.push(_wstETHRealHolders[i]);
            _allAccounts.push(_wstETHRealHolders[i]);
        }

        console.log(
            "Loaded %s stETH holders, %s wstETH holders from files", _stETHRealHolders.length, _wstETHRealHolders.length
        );
    }

    function _setupSimulationAccounts() internal {
        for (uint256 i = 0; i < SIMULATION_ACCOUNTS; ++i) {
            _simulationAccounts.push(_getSimulationAccount(i));
            _allAccounts.push(_simulationAccounts[i]);
            vm.deal(_simulationAccounts[i], _random.nextUint256(10_000 ether));
        }
    }

    function _setupAccounts() internal {
        _loadHolders();
        _setupSimulationAccounts();

        for (uint256 i = 0; i < _allAccounts.length; ++i) {
            _accountsDetails[_allAccounts[i]].ethBalanceBefore = _allAccounts[i].balance;
            _accountsDetails[_allAccounts[i]].stETHBalanceBefore = _lido.stETH.balanceOf(_allAccounts[i])
                + _lido.stETH.getPooledEthByShares(_lido.wstETH.balanceOf(_allAccounts[i]));
            _accountsDetails[_allAccounts[i]].sharesBalanceBefore = _lido.wstETH.balanceOf(_allAccounts[i])
                + _lido.stETH.getSharesByPooledEth(_lido.stETH.balanceOf(_allAccounts[i]));
        }
    }

    function _getCurrentEscrowAddress() internal view returns (address payable) {
        return payable(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow());
    }
}

contract SelfDestructSender {
    constructor(address payable recipient) payable {
        selfdestruct(recipient);
    }
}
