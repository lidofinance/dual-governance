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
    LockWstETHRealHolder,
    LockUnstETHRealHolder,
    //
    UnlockStETHRealHolder,
    UnlockWstETHRealHolder,
    UnlockUnstETHRealHolder
}

struct VetoersFile {
    address[] addresses;
}

struct AccountDetails {
    uint256 ethBalanceBefore;
    uint256 sharesBalanceBefore;
    uint256 stETHBalanceBefore;
    uint256 unstETHBalanceBefore;
    uint256 stETHSubmitted;
    uint256 wstETHSubmitted;
    uint256[] unstETHIdsRequested;
    mapping(address escrow => uint256 balance) sharesLockedInEscrow;
    mapping(address escrow => uint256 accumulatedEscrowSharesError) accumulatedEscrowSharesErrors;
    mapping(address escrow => uint256[] ids) unstETHIdsLockedInEscrow;
    uint256 accidentalETHTransferAmount;
    uint256 accidentalStETHTransferAmount;
    uint256 accidentalWstETHTransferAmount;
    uint256 accidentalUnstETHTransferAmount;
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

// 75 times more than real slot duration to speed up test. Must not affect correctness of the test
uint256 constant SLOT_DURATION = 15 minutes;
uint256 constant SIMULATION_ACCOUNTS = 512;
uint256 constant SIMULATION_DURATION = 180 days;

uint256 constant MIN_ST_ETH_SUBMIT_AMOUNT = 0.1 ether;
uint256 constant MAX_ST_ETH_SUBMIT_AMOUNT = 10_000 ether;

uint256 constant MIN_ST_ETH_LOCK_AMOUNT = 1000 wei;
uint256 constant MAX_ST_ETH_LOCK_AMOUNT = 20_000 ether;

uint256 constant MIN_ST_ETH_WITHDRAW_AMOUNT = 0.1 ether;
uint256 constant MAX_ST_ETH_WITHDRAW_AMOUNT = 50_000 ether;

uint256 constant MIN_WST_ETH_SUBMIT_AMOUNT = 0.1 ether;
uint256 constant MAX_WST_ETH_SUBMIT_AMOUNT = 10_000 ether;

uint256 constant MIN_WST_ETH_LOCK_AMOUNT = 1000 wei;
uint256 constant MAX_WST_ETH_LOCK_AMOUNT = 20_000 ether;

uint256 constant MIN_WST_ETH_WITHDRAW_AMOUNT = 0.1 ether;
uint256 constant MAX_WST_ETH_WITHDRAW_AMOUNT = 50_000 ether;

uint256 constant MIN_ACCIDENTAL_TRANSFER_AMOUNT = 0.1 ether;
uint256 constant MAX_ACCIDENTAL_TRANSFER_AMOUNT = 1_000 ether;

uint256 constant MIN_ACCIDENTAL_UNSTETH_TRANSFER_AMOUNT = 1;
uint256 constant MAX_ACCIDENTAL_UNSTETH_TRANSFER_AMOUNT = 1_000 ether;

uint256 constant ORACLE_REPORT_FREQUENCY = 24 hours;

contract EscrowSolvencyTest is DGRegressionTestSetup {
    using Random for Random.Context;
    using DecimalsFormatting for uint256;
    using DecimalsFormatting for PercentD16;
    using LidoUtils for LidoUtils.Context;
    using Uint256ArrayBuilder for Uint256ArrayBuilder.Context;
    using SimulationActionsSet for SimulationActionsSet.Context;
    using Debug for Debug.Context;

    PercentD16 immutable LOCK_ST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(100_00);
    PercentD16 immutable LOCK_WST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(100_00);
    PercentD16 immutable LOCK_UNST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(100_00);

    PercentD16 immutable UNLOCK_ST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(5_00);
    PercentD16 immutable UNLOCK_WST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(5_00);
    PercentD16 immutable UNLOCK_UNST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(5_00);

    PercentD16 immutable MARK_UNST_ETH_FINALIZED_PROBABILITY = PercentsD16.fromBasisPoints(7_00);

    PercentD16 immutable SUBMIT_STETH_PROBABILITY = PercentsD16.fromBasisPoints(10_00);
    PercentD16 immutable SUBMIT_WSTETH_PROBABILITY = PercentsD16.fromBasisPoints(10_00);

    PercentD16 immutable WITHDRAW_STETH_PROBABILITY = PercentsD16.fromBasisPoints(25_00);
    PercentD16 immutable WITHDRAW_WSTETH_PROBABILITY = PercentsD16.fromBasisPoints(25_00);
    PercentD16 immutable CLAIM_UNSTETH_PROBABILITY = PercentsD16.fromBasisPoints(50_00);

    PercentD16 immutable ACCIDENTAL_ETH_TRANSFER_PROBABILITY = PercentsD16.fromBasisPoints(10);
    PercentD16 immutable ACCIDENTAL_STETH_TRANSFER_PROBABILITY = PercentsD16.fromBasisPoints(10);
    PercentD16 immutable ACCIDENTAL_WSTETH_TRANSFER_PROBABILITY = PercentsD16.fromBasisPoints(10);
    PercentD16 immutable ACCIDENTAL_UNSTETH_TRANSFER_PROBABILITY = PercentsD16.fromBasisPoints(10);

    PercentD16 immutable WITHDRAW_STETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(50_00);
    PercentD16 immutable WITHDRAW_WSTETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(50_00);
    PercentD16 immutable CLAIM_UNSTETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(50_00);

    PercentD16 immutable LOCK_STETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(75_00);
    PercentD16 immutable LOCK_WSTETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(75_00);
    PercentD16 immutable LOCK_UNSTETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(75_00);

    PercentD16 immutable UNLOCK_STETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(1_00);
    PercentD16 immutable UNLOCK_WSTETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(1_00);
    PercentD16 immutable UNLOCK_UNSTETH_REAL_HOLDER_PROBABILITY = PercentsD16.fromBasisPoints(1_00);

    PercentD16 immutable NEGATIVE_REBASE_PROBABILITY = PercentsD16.fromBasisPoints(3_00);
    uint256 constant MAX_NEGATIVE_REBASES_COUNT = 1;

    uint256 internal _negativeRebaseAccumulated = HUNDRED_PERCENT_D16;
    uint256 internal _positiveRebaseAccumulated = HUNDRED_PERCENT_D16;

    uint256 internal _totalLockedStETH = 0;
    uint256 internal _totalLockedWstETH = 0;

    uint256 internal _totalLockedStETHByRealAccounts = 0;
    uint256 internal _totalLockedStETHBySimulationAccounts = 0;

    uint256 internal _totalLockedWstETHByRealAccounts = 0;
    uint256 internal _totalLockedWstETHBySimulationAccounts = 0;

    uint256 internal _totalUnlockedStETHBySimulationAccounts = 0;
    uint256 internal _totalUnlockedWstETHBySimulationAccounts = 0;
    uint256 internal _totalUnlockedUnstETHBySimulationAccountsCount = 0;
    uint256 internal _totalUnlockedUnstETHBySimulationAccountsAmount = 0;

    uint256 internal _totalUnlockedStETHByRealAccounts = 0;
    uint256 internal _totalUnlockedWstETHByRealAccounts = 0;
    uint256 internal _totalUnlockedUnstETHByRealAccountsCount = 0;
    uint256 internal _totalUnlockedUnstETHByRealAccountsAmount = 0;

    uint256 internal _totalClaimedUnstETHByRealAccountsCount = 0;
    uint256 internal _totalClaimedUnstETHBySimulationAccountsCount = 0;
    uint256 internal _totalClaimedUnstETHByRealAccountsAmount = 0;
    uint256 internal _totalClaimedUnstETHBySimulationAccountsAmount = 0;

    uint256 internal _totalMarkedUnstETHFinalizedCount = 0;
    uint256 internal _totalMarkedUnstETHFinalizedAmount = 0;

    uint256 internal _totalLockedUnstETHByRealAccountsCount = 0;
    uint256 internal _totalLockedUnstETHBySimulationAccountsCount = 0;
    uint256 internal _totalLockedUnstETHByRealAccountsAmount = 0;
    uint256 internal _totalLockedUnstETHBySimulationAccountsAmount = 0;

    uint256 internal _totalSubmittedStETH = 0;
    uint256 internal _totalSubmittedWstETH = 0;

    uint256 internal _totalWithdrawnStETH = 0;
    uint256 internal _totalWithdrawnWstETH = 0;

    uint256 internal _totalWithdrawnStETHByRealAccounts = 0;
    uint256 internal _totalWithdrawnStETHBySimulationAccounts = 0;

    uint256 internal _totalWithdrawnWstETHByRealAccounts = 0;
    uint256 internal _totalWithdrawnWstETHBySimulationAccounts = 0;

    uint256 internal _totalAccidentalETHTransferAmount = 0;
    uint256 internal _totalAccidentalStETHTransferAmount = 0;
    uint256 internal _totalAccidentalWstETHTransferAmount = 0;
    uint256 internal _totalAccidentalUnstETHTransferAmount = 0;

    uint256 internal _totalNegativeRebaseCount = 0;
    uint256 internal _initialShareRate = 0;

    Escrow internal _vetoSignallingEscrow;
    Escrow[] internal _rageQuitEscrows;
    mapping(address escrow => uint256 accidentalETHTransferAmount) internal _accidentalETHTransfersByEscrow;
    mapping(address escrow => uint256 _accidentalWstETHTransferAmount) internal _accidentalWstETHTransfersByEscrow;
    mapping(address escrow => uint256 _accidentalStETHTransferAmount) internal _accidentalStETHTransfersByEscrow;
    mapping(address escrow => uint256 _accidentalUnstETHTransferCount) internal _accidentalUnstETHTransfersByEscrow;

    uint256 internal _initialVetoSignallingEscrowLockedShares;
    uint256 internal _initialVetoSignallingEscrowLockedUnstETHCount;

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

    Debug.Context internal _debug;

    uint256 internal _finalizationPhaseIterations = 0;
    mapping(address escrow => bool isFullyFinalized) internal _isRageQuitFullyWithdrawn;
    bool internal LIMIT_FINALIZATION_PHASE;

    function setUp() external {
        _loadOrDeployDGSetup();
        _random = Random.create(block.timestamp);
        _nextFrameStart = _lido.getReportTimeElapsed().nextFrameStart;

        _setupAccounts();
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
            if (!vm.envOr("RUN_SOLVENCY_SIMULATION_TEST", false)) {
                vm.skip(true, "To enable this test set the env variable RUN_SOLVENCY_SIMULATION_TEST=true");
                return;
            }

            if (vm.envOr("LIMIT_FINALIZATION_PHASE", false)) {
                LIMIT_FINALIZATION_PHASE = true;
                console.log(">>> Finalization phase is limited to 10_000 iterations");
            }

            if (vm.envOr("DEBUG", false)) {
                _debug.debuggingEnabled = true;
            }
        }

        uint256 nextRageQuitOperationDelay = 0;
        uint256 lastRageQuitOperationTimestamp = 0;
        uint256 iterations = 0;
        _vetoSignallingEscrow = Escrow(payable(_getCurrentEscrowAddress()));

        {
            uint256 simulationEndTimestamp = block.timestamp + SIMULATION_DURATION;
            DGState currentDGState = _dgDeployedContracts.dualGovernance.getPersistedState();
            _initialVetoSignallingEscrowLockedShares =
                _vetoSignallingEscrow.getSignallingEscrowDetails().totalStETHLockedShares.toUint256();
            // TODO: check locked unstETH shares in the escrow
            // _initialVetoSignallingEscrowLockedUnstETHCount =
            //     _vetoSignallingEscrow.getSignallingEscrowDetails().totalUnstETHLockedShares.toUint256();
            _initialShareRate = _lido.stETH.getPooledEthByShares(10 ** 18);
            console.log("Initial share rate: %s", _initialShareRate.formatEther());
            console.log("Initial stETH Total Supply: %s", _lido.stETH.totalSupply().formatEther());
            console.log(
                "before simulation block number: %d, before simulation timestamp: %d", block.number, block.timestamp
            );
            console.log("Initial DG state: %s", _getDGStateName(currentDGState));

            while (block.timestamp < simulationEndTimestamp) {
                SimulationActionsSet.Context memory actions = _getRandomUniqueActionsSet();

                _processSimulationActions(actions);

                if (_lastOracleReportTimestamp + ORACLE_REPORT_FREQUENCY < block.timestamp) {
                    _lastOracleReportTimestamp = block.timestamp;
                    _reportAndRebase();
                }

                if (block.timestamp >= lastRageQuitOperationTimestamp + nextRageQuitOperationDelay) {
                    nextRageQuitOperationDelay = _random.nextUint256(15 minutes, 36 hours);
                    lastRageQuitOperationTimestamp = block.timestamp;
                    _processRageQuitEscrowsWithdrawals();
                }
                iterations++;
            }
            _checkAccountsBalances();

            bool isAllRageQuitEscrowsWithdrawalsProcessed = false;
            uint256 maxFinalizationIterations = type(uint256).max;

            if (LIMIT_FINALIZATION_PHASE) {
                maxFinalizationIterations = 10_000; // 15 minutes * 10_000 iterations = 150_000 minutes = 104 days
            }

            while (
                !isAllRageQuitEscrowsWithdrawalsProcessed && _finalizationPhaseIterations < maxFinalizationIterations
            ) {
                _mineBlock();

                if (_lastOracleReportTimestamp + ORACLE_REPORT_FREQUENCY < block.timestamp) {
                    _lastOracleReportTimestamp = block.timestamp;
                    _reportAndRebase();
                }

                if (block.timestamp >= lastRageQuitOperationTimestamp + nextRageQuitOperationDelay) {
                    nextRageQuitOperationDelay = _random.nextUint256(15 minutes, 36 hours);
                    lastRageQuitOperationTimestamp = block.timestamp;

                    isAllRageQuitEscrowsWithdrawalsProcessed = true;
                    for (uint256 i = 0; i < _rageQuitEscrows.length; ++i) {
                        if (_isRageQuitFullyWithdrawn[address(_rageQuitEscrows[i])]) {
                            continue;
                        }
                        _processRageQuitEscrowsWithdrawals(_rageQuitEscrows[i]);
                        if (!_checkIfRageQuitEscrowWithdrawalsProcessed(_rageQuitEscrows[i])) {
                            isAllRageQuitEscrowsWithdrawalsProcessed = false;
                            continue;
                        }
                        _isRageQuitFullyWithdrawn[address(_rageQuitEscrows[i])] = true;
                    }
                }
                _finalizationPhaseIterations++;
            }

            // Check if all rage quit escrows are fully withdrawn and force process them if not
            for (uint256 i = 0; i < _rageQuitEscrows.length; ++i) {
                Escrow rageQuitEscrow = _rageQuitEscrows[i];
                if (!_isRageQuitFullyWithdrawn[address(rageQuitEscrow)]) {
                    _forceProcessRageQuitEscrowsWithdrawals(_rageQuitEscrows[i]);
                }
            }

            _printSimulationStats(iterations);
            _checkAccountsBalances();
        }

        for (uint256 i = 0; i < _rageQuitEscrows.length; ++i) {
            Escrow rageQuitEscrow = _rageQuitEscrows[i];
            assertTrue(
                _checkIfRageQuitEscrowWithdrawalsProcessed(rageQuitEscrow),
                "Rage quit escrow withdrawals were not processed"
            );

            if (i == 0) {
                assertApproxEqAbs(
                    address(rageQuitEscrow).balance,
                    _accidentalETHTransfersByEscrow[address(rageQuitEscrow)] + _initialVetoSignallingEscrowLockedShares,
                    0.001 ether
                );
            } else {
                assertApproxEqAbs(
                    address(rageQuitEscrow).balance,
                    _accidentalETHTransfersByEscrow[address(rageQuitEscrow)],
                    0.001 ether
                );
            }

            assertEq(
                _lido.wstETH.balanceOf(address(rageQuitEscrow)),
                _accidentalWstETHTransfersByEscrow[address(rageQuitEscrow)]
            );
        }

        _checkAccountsRageQuitEscrowBalancesEmpty();
    }

    function _activateNextStateIfNeeded() internal {
        DGState currentDGState = _dgDeployedContracts.dualGovernance.getPersistedState();
        DGState effectiveDGState = _dgDeployedContracts.dualGovernance.getEffectiveState();

        if (currentDGState != effectiveDGState) {
            if (currentDGState == DGState.RageQuit && effectiveDGState != DGState.RageQuit) {
                console.log(">>> Exiting RageQuit state");
            }
            console.log(
                ">>> DG State changed from %s to %s", _getDGStateName(currentDGState), _getDGStateName(effectiveDGState)
            );
            _activateNextState();
            if (currentDGState != DGState.RageQuit && effectiveDGState == DGState.RageQuit) {
                _rageQuitEscrows.push(Escrow(payable(address(_dgDeployedContracts.dualGovernance.getRageQuitEscrow()))));

                _vetoSignallingEscrow =
                    Escrow(payable(address(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow())));
            }
            currentDGState = effectiveDGState;
        }
    }

    function _reportAndRebase() internal {
        uint256 requestIdToFinalize = _random.nextUint256(
            _lido.withdrawalQueue.getLastFinalizedRequestId() + 1, _lido.withdrawalQueue.getLastRequestId() + 1
        );

        _reportAndRebase(requestIdToFinalize);
    }

    function _reportAndRebase(uint256 requestIdToFinalize) internal {
        uint256 rebaseAmount;
        if (
            _getRandomProbability() < NEGATIVE_REBASE_PROBABILITY
                && _totalNegativeRebaseCount < MAX_NEGATIVE_REBASES_COUNT
        ) {
            rebaseAmount = HUNDRED_PERCENT_D16 - 8_000 gwei;
            _totalNegativeRebaseCount++;
            _negativeRebaseAccumulated = _negativeRebaseAccumulated * rebaseAmount / HUNDRED_PERCENT_D16;
        } else {
            rebaseAmount = _random.nextUint256(HUNDRED_PERCENT_D16, HUNDRED_PERCENT_D16 + 80_000 gwei);
            _positiveRebaseAccumulated = _positiveRebaseAccumulated * rebaseAmount / HUNDRED_PERCENT_D16;
        }

        _lido.performRebase(PercentsD16.from(rebaseAmount), requestIdToFinalize);
    }

    function _calculateTotalAccountBalanceInETH(
        address account,
        uint256 ethLockedUnclaimed,
        uint256 sharesLockedInEscrows
    ) internal view returns (uint256 balanceInETH) {
        balanceInETH = account.balance + _lido.stETH.balanceOf(account)
            + _lido.stETH.getPooledEthByShares(
                _lido.wstETH.balanceOf(account) + sharesLockedInEscrows
                    + _accountsDetails[account].accidentalWstETHTransferAmount
            ) + ethLockedUnclaimed + _accountsDetails[account].accidentalETHTransferAmount
            + _accountsDetails[account].accidentalStETHTransferAmount
            + _accountsDetails[account].accidentalUnstETHTransferAmount;
    }

    function _checkAccountsRageQuitEscrowBalancesEmpty() internal view {
        _debug.debug(">>> Checking accounts rage quit escrow balances empty");
        for (uint256 i = 0; i < _allAccounts.length; ++i) {
            address account = _allAccounts[i];

            uint256 ethLockedUnclaimed = 0;
            uint256 sharesLockedInEscrows = 0;

            // Check locked shares in all rage quit escrows
            for (uint256 j = 0; j < _rageQuitEscrows.length; ++j) {
                (uint256 sharesLocked, uint256 unstETHUnclaimed) =
                    _calculateLockedSharesAndUnstETHInEscrow(_rageQuitEscrows[j], account);

                ethLockedUnclaimed += unstETHUnclaimed;
                sharesLockedInEscrows += sharesLocked;
            }

            assertEq(ethLockedUnclaimed, 0);
            assertEq(sharesLockedInEscrows, 0);
        }
    }

    function _checkAccountsBalances() internal view {
        _debug.debug(">>> Checking accounts balances");
        for (uint256 i = 0; i < _allAccounts.length; ++i) {
            address account = _allAccounts[i];

            uint256 ethLockedUnclaimed = 0;
            uint256 sharesLockedInEscrows = 0;

            IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalStatuses =
                _lido.withdrawalQueue.getWithdrawalStatus(_accountsDetails[account].unstETHIdsRequested);

            // Check unclaimed withdrawal requests
            for (uint256 j = 0; j < withdrawalStatuses.length; ++j) {
                if (!withdrawalStatuses[j].isClaimed && withdrawalStatuses[j].owner == account) {
                    ethLockedUnclaimed += withdrawalStatuses[j].amountOfStETH;
                }
            }

            // Check locked shares in all rage quit escrows
            for (uint256 j = 0; j < _rageQuitEscrows.length; ++j) {
                (uint256 sharesLocked, uint256 unstETHUnclaimed) =
                    _calculateLockedSharesAndUnstETHInEscrow(_rageQuitEscrows[j], account);

                ethLockedUnclaimed += unstETHUnclaimed;
                sharesLockedInEscrows += sharesLocked;
            }

            // Check locked shares in veto signalling escrow
            {
                (uint256 sharesLocked, uint256 unstETHUnclaimed) =
                    _calculateLockedSharesAndUnstETHInEscrow(_vetoSignallingEscrow, account);

                ethLockedUnclaimed += unstETHUnclaimed;
                sharesLockedInEscrows += sharesLocked;
            }
            {
                uint256 holderBalanceBefore = _accountsDetails[account].ethBalanceBefore
                    + _accountsDetails[account].stETHBalanceBefore + _accountsDetails[account].unstETHBalanceBefore;
                uint256 minBalanceEstimation = holderBalanceBefore * _negativeRebaseAccumulated / HUNDRED_PERCENT_D16;
                // TODO: Wsteth lock/unlock may cause shares error on each cycle
                if (minBalanceEstimation < 100 wei) {
                    minBalanceEstimation = 0;
                } else {
                    minBalanceEstimation -= 100 wei;
                }

                uint256 holderBalanceAfter =
                    _calculateTotalAccountBalanceInETH(account, ethLockedUnclaimed, sharesLockedInEscrows);

                uint256 maxBalanceEstimation = holderBalanceBefore * _positiveRebaseAccumulated / HUNDRED_PERCENT_D16;

                assertTrue(holderBalanceAfter >= minBalanceEstimation);
                assertTrue(holderBalanceAfter <= maxBalanceEstimation);
            }
        }
    }

    function _processRageQuitEscrowsWithdrawals() internal {
        uint256 randomRageQuitEscrowIndex = _random.nextUint256(_rageQuitEscrows.length);

        for (uint256 i = 0; i < _rageQuitEscrows.length; ++i) {
            Escrow rageQuitEscrow = _rageQuitEscrows[(randomRageQuitEscrowIndex + i) % _rageQuitEscrows.length];

            _processRageQuitEscrowsWithdrawals(rageQuitEscrow);
        }
    }

    function _forceProcessRageQuitEscrowsWithdrawals(Escrow rageQuitEscrow) internal {
        _debug.debug(">>> Force processing rage quit escrow withdrawals for %s", address(rageQuitEscrow));
        _activateNextStateIfNeeded();

        Escrow.RageQuitEscrowDetails memory details = rageQuitEscrow.getRageQuitEscrowDetails();

        while (!rageQuitEscrow.isWithdrawalsBatchesClosed()) {
            uint256 lastUnstETHIdBefore = _lido.withdrawalQueue.getLastRequestId();
            rageQuitEscrow.requestNextWithdrawalsBatch(128);
            uint256 lastUnstETHIdAfter = _lido.withdrawalQueue.getLastRequestId();
            _debug.debug(
                ">>> Requesting %s next withdrawals batch: [%d, %d]",
                lastUnstETHIdAfter - lastUnstETHIdBefore,
                lastUnstETHIdBefore + 1,
                lastUnstETHIdAfter
            );
        }

        while (rageQuitEscrow.getUnclaimedUnstETHIdsCount() > 0) {
            uint256[] memory unstETHIds = rageQuitEscrow.getNextWithdrawalBatch(128);
            uint256 lastUnstETHId = unstETHIds[unstETHIds.length - 1];

            _reportAndRebase(lastUnstETHId);

            rageQuitEscrow.claimNextWithdrawalsBatch(128);
        }

        rageQuitEscrow.startRageQuitExtensionPeriod();

        vm.warp(
            block.timestamp + details.rageQuitExtensionPeriodStartedAt.toSeconds()
                + details.rageQuitExtensionPeriodDuration.toSeconds() + details.rageQuitEthWithdrawalsDelay.toSeconds() + 1
        );

        for (uint256 j = 0; j < _allAccounts.length; ++j) {
            address account = _allAccounts[j];

            if (rageQuitEscrow.getVetoerDetails(account).stETHLockedShares.toUint256() == 0) {
                continue;
            }

            _withdrawEscrowETH(rageQuitEscrow, account);
        }

        for (uint256 j = 0; j < _allAccounts.length; ++j) {
            address account = _allAccounts[j];

            if (rageQuitEscrow.getVetoerDetails(account).unstETHIdsCount == 0) {
                continue;
            }

            uint256[] memory unstETHIds = rageQuitEscrow.getVetoerUnstETHIds(account);

            Uint256ArrayBuilder.Context memory requestsToClaimArrayBuilder =
                Uint256ArrayBuilder.create(unstETHIds.length);
            for (uint256 k = 0; k < unstETHIds.length; ++k) {
                requestsToClaimArrayBuilder.addItem(unstETHIds[k]);
            }

            unstETHIds = requestsToClaimArrayBuilder.getSorted();
            if (unstETHIds.length > 0) {
                _claimEscrowUnstETH(rageQuitEscrow, account, unstETHIds);
                _withdrawEscrowUnsETH(rageQuitEscrow, account, unstETHIds);
            }
        }
    }

    function _processRageQuitEscrowsWithdrawals(Escrow rageQuitEscrow) internal {
        _debug.debug(">>> Processing rage quit escrow withdrawals for %s", address(rageQuitEscrow));
        _activateNextStateIfNeeded();

        Escrow.RageQuitEscrowDetails memory details = rageQuitEscrow.getRageQuitEscrowDetails();

        bool isWithdrawalsBatchesClosed = rageQuitEscrow.isWithdrawalsBatchesClosed();
        if (!isWithdrawalsBatchesClosed) {
            uint256 requestBatchSize = _random.nextUint256(_vetoSignallingEscrow.MIN_WITHDRAWALS_BATCH_SIZE(), 128);
            uint256 lastUnstETHIdBefore = _lido.withdrawalQueue.getLastRequestId();
            rageQuitEscrow.requestNextWithdrawalsBatch(requestBatchSize);
            uint256 lastUnstETHIdAfter = _lido.withdrawalQueue.getLastRequestId();
            _debug.debug(
                ">>> Requesting %s next withdrawals batch: [%d, %d]",
                lastUnstETHIdAfter - lastUnstETHIdBefore,
                lastUnstETHIdBefore + 1,
                lastUnstETHIdAfter
            );
        }

        uint256 unclaimedUnstETHIds = rageQuitEscrow.getUnclaimedUnstETHIdsCount();

        if (unclaimedUnstETHIds > 0) {
            uint256 claimType = _random.nextUint256();
            uint256 unstETHIdsCount = _random.nextUint256(1, 128);
            uint256[] memory unstETHIds = rageQuitEscrow.getNextWithdrawalBatch(unstETHIdsCount);
            IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
                _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);

            bool isAllBatchRequestsFinalized = true;
            for (uint256 j = 0; j < statuses.length; ++j) {
                if (!statuses[j].isFinalized) {
                    isAllBatchRequestsFinalized = false;
                    _debug.debug("Not all requests for batch request is finalized yet. Waiting...");
                    break;
                }
            }

            if (isAllBatchRequestsFinalized) {
                if (claimType % 2 == 0) {
                    rageQuitEscrow.claimNextWithdrawalsBatch(unstETHIdsCount);
                } else {
                    uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
                        unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
                    );

                    uint256[] memory wrClaimableEth = _lido.withdrawalQueue.getClaimableEther(unstETHIds, hints);
                    uint256 escrowEthBalance = address(rageQuitEscrow).balance;

                    rageQuitEscrow.claimNextWithdrawalsBatch(unstETHIds[0], hints);

                    uint256 totalClaimableEth = 0;
                    for (uint256 j = 0; j < wrClaimableEth.length; ++j) {
                        totalClaimableEth += wrClaimableEth[j];
                    }
                    assertApproxEqAbs(address(rageQuitEscrow).balance, escrowEthBalance + totalClaimableEth, 2);
                }
            }
        }

        if (isWithdrawalsBatchesClosed && unclaimedUnstETHIds == 0) {
            details = rageQuitEscrow.getRageQuitEscrowDetails();
            if (!details.isRageQuitExtensionPeriodStarted) {
                console.log(">>> Start rage quit extension period");
                rageQuitEscrow.startRageQuitExtensionPeriod();
            }
        }
        {
            uint256 claimerCount = _random.nextUint256(1, 5);
            uint256 accountIndexOffset = _random.nextUint256(_allAccounts.length);
            for (uint256 j = 0; j < _allAccounts.length; ++j) {
                address account = _allAccounts[(accountIndexOffset + j) % _allAccounts.length];

                uint256[] memory lockedUnstETHIds = rageQuitEscrow.getVetoerUnstETHIds(account);

                if (lockedUnstETHIds.length == 0) {
                    continue;
                }

                (uint256 unstETHCountClaimed,) = _claimEscrowUnstETH(rageQuitEscrow, account, lockedUnstETHIds);

                if (claimerCount > 0 && unstETHCountClaimed > 0) {
                    claimerCount--;
                } else {
                    break;
                }
            }
        }

        {
            Escrow.RageQuitEscrowDetails memory escrowDetails = rageQuitEscrow.getRageQuitEscrowDetails();
            if (
                escrowDetails.isRageQuitExtensionPeriodStarted
                    && block.timestamp
                        > escrowDetails.rageQuitExtensionPeriodStartedAt.toSeconds()
                            + escrowDetails.rageQuitExtensionPeriodDuration.toSeconds()
                            + escrowDetails.rageQuitEthWithdrawalsDelay.toSeconds()
            ) {
                uint256 accountsCount = _random.nextUint256(10, 50);

                // Randomly select accounts to withdraw ETH from the escrow
                uint256 accountIndexOffset = _random.nextUint256(_allAccounts.length);
                for (uint256 j = 0; j < _allAccounts.length; ++j) {
                    address account = _allAccounts[(accountIndexOffset + j) % _allAccounts.length];

                    if (rageQuitEscrow.getVetoerDetails(account).stETHLockedShares.toUint256() == 0) {
                        continue;
                    }

                    if (accountsCount > 0) {
                        accountsCount--;
                    } else {
                        break;
                    }

                    _withdrawEscrowETH(rageQuitEscrow, account);
                }

                //Randomly select accounts to withdraw unstETH NFTs from the escrow
                accountsCount = _random.nextUint256(10, 50);
                accountIndexOffset = _random.nextUint256(_allAccounts.length);
                for (uint256 j = 0; j < _allAccounts.length; ++j) {
                    address account = _allAccounts[(accountIndexOffset + j) % _allAccounts.length];

                    if (rageQuitEscrow.getVetoerDetails(account).unstETHIdsCount == 0) {
                        continue;
                    }

                    if (accountsCount > 0) {
                        accountsCount--;
                    } else {
                        break;
                    }

                    uint256[] memory unstETHIds = rageQuitEscrow.getVetoerUnstETHIds(account);

                    Uint256ArrayBuilder.Context memory requestsToClaimArrayBuilder =
                        Uint256ArrayBuilder.create(unstETHIds.length);
                    for (uint256 k = 0; k < unstETHIds.length; ++k) {
                        requestsToClaimArrayBuilder.addItem(unstETHIds[k]);
                    }

                    unstETHIds = requestsToClaimArrayBuilder.getSorted();
                    if (unstETHIds.length > 0) {
                        _claimEscrowUnstETH(rageQuitEscrow, account, unstETHIds);
                        _withdrawEscrowUnsETH(rageQuitEscrow, account, unstETHIds);
                    }
                }
            }
        }
    }

    function _checkIfRageQuitEscrowWithdrawalsProcessed(Escrow rageQuitEscrow) internal view returns (bool) {
        _debug.debug(">>> Checking if rage quit escrow withdrawals are processed for %s", address(rageQuitEscrow));
        uint256 rageQuitBalanceAccuracy = 0.00001 ether;

        Escrow.RageQuitEscrowDetails memory details = rageQuitEscrow.getRageQuitEscrowDetails();

        if (!details.isRageQuitExtensionPeriodStarted) {
            return false;
        }

        if (
            block.timestamp
                <= details.rageQuitExtensionPeriodStartedAt.toSeconds()
                    + details.rageQuitExtensionPeriodDuration.toSeconds() + details.rageQuitEthWithdrawalsDelay.toSeconds()
        ) {
            return false;
        }

        if (
            (
                _rageQuitEscrows[0] == rageQuitEscrow
                    && address(rageQuitEscrow).balance
                        > _lido.stETH.getPooledEthByShares(_initialVetoSignallingEscrowLockedShares)
                            + _accidentalETHTransfersByEscrow[address(rageQuitEscrow)] + rageQuitBalanceAccuracy
            )
                || (
                    _rageQuitEscrows[0] != rageQuitEscrow
                        && address(rageQuitEscrow).balance
                            > _accidentalETHTransfersByEscrow[address(rageQuitEscrow)] + rageQuitBalanceAccuracy
                )
        ) {
            return false;
        }

        for (uint256 i = 0; i < _allAccounts.length; ++i) {
            address account = _allAccounts[i];

            uint256[] memory unstETHIds = rageQuitEscrow.getVetoerUnstETHIds(account);
            if (unstETHIds.length > 0) {
                Escrow.LockedUnstETHDetails[] memory unstETHDetails = rageQuitEscrow.getLockedUnstETHDetails(unstETHIds);
                for (uint256 j = 0; j < unstETHDetails.length; ++j) {
                    if (unstETHDetails[j].status != UnstETHRecordStatus.Withdrawn) {
                        return false;
                    }
                }
            }
        }

        return true;
    }

    function _claimEscrowUnstETH(
        Escrow escrow,
        address claimer,
        uint256[] memory unstETHIds
    ) internal returns (uint256 unstETHCountClaimed, uint256 unstETHAmountClaimed) {
        uint256 totalUnstETHAmount = 0;
        uint256 withdrawalQueueBalanceBefore = address(_lido.withdrawalQueue).balance;
        uint256 escrowBalanceBefore = address(escrow).balance;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalStatuses =
            _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);

        Uint256ArrayBuilder.Context memory requestsToClaimArrayBuilder = Uint256ArrayBuilder.create(unstETHIds.length);
        for (uint256 k = 0; k < unstETHIds.length; ++k) {
            assertEq(withdrawalStatuses[k].owner, address(escrow));
            if (withdrawalStatuses[k].isFinalized && !withdrawalStatuses[k].isClaimed) {
                requestsToClaimArrayBuilder.addItem(unstETHIds[k]);
            }
        }
        uint256[] memory requestIdsToClaim = requestsToClaimArrayBuilder.getSorted();

        if (requestIdsToClaim.length > 0) {
            uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
                requestIdsToClaim, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
            );
            uint256[] memory claimableAmounts =
                IWithdrawalQueue(_lido.withdrawalQueue).getClaimableEther(requestIdsToClaim, hints);

            for (uint256 i = 0; i < claimableAmounts.length; ++i) {
                totalUnstETHAmount += claimableAmounts[i];
            }
            vm.prank(claimer);
            escrow.claimUnstETH(requestIdsToClaim, hints);
        }

        assertEq(address(_lido.withdrawalQueue).balance, withdrawalQueueBalanceBefore - totalUnstETHAmount);
        assertEq(address(escrow).balance, escrowBalanceBefore + totalUnstETHAmount);

        unstETHCountClaimed = requestIdsToClaim.length;
        unstETHAmountClaimed = totalUnstETHAmount;

        _debug.debug(
            "Account %s claimed %s unstETH NFTs with total amount %s",
            claimer,
            unstETHCountClaimed,
            unstETHAmountClaimed.formatEther()
        );
    }

    function _withdrawEscrowUnsETH(Escrow escrow, address account, uint256[] memory unstETHIds) internal {
        uint256 totalUnstETHAmount = 0;
        uint256 accountBalanceBefore = account.balance;
        uint256 escrowBalanceBefore = address(escrow).balance;

        Escrow.LockedUnstETHDetails[] memory unstETHDetails = escrow.getLockedUnstETHDetails(unstETHIds);

        Uint256ArrayBuilder.Context memory requestsArrayBuilder = Uint256ArrayBuilder.create(unstETHIds.length);
        for (uint256 k = 0; k < unstETHDetails.length; ++k) {
            if (unstETHDetails[k].status == UnstETHRecordStatus.Claimed) {
                requestsArrayBuilder.addItem(unstETHIds[k]);
                totalUnstETHAmount += unstETHDetails[k].claimableAmount.toUint256();
            }
        }

        uint256[] memory requestIdsToWithdraw = requestsArrayBuilder.getResult();
        if (requestIdsToWithdraw.length > 0) {
            bytes memory accountCode = account.code;
            if (accountCode.length > 0) {
                vm.etch(account, bytes(""));
            }

            vm.prank(account);
            escrow.withdrawETH(requestIdsToWithdraw);

            if (accountCode.length > 0) {
                vm.etch(account, accountCode);
            }
        }

        assertEq(address(escrow).balance, escrowBalanceBefore - totalUnstETHAmount);
        assertEq(account.balance, accountBalanceBefore + totalUnstETHAmount);

        _debug.debug(
            "Account %s withdrew %s unstETH NFTs with total amount %s",
            account,
            requestIdsToWithdraw.length,
            totalUnstETHAmount.formatEther()
        );
    }

    function _withdrawEscrowETH(Escrow escrow, address account) internal {
        Escrow.VetoerDetails memory details = escrow.getVetoerDetails(account);
        Escrow.SignallingEscrowDetails memory escrowDetails = escrow.getSignallingEscrowDetails();
        uint256 amount = escrowDetails.totalStETHClaimedETH.toUint256() * details.stETHLockedShares.toUint256()
            / escrowDetails.totalStETHLockedShares.toUint256();

        uint256 accountBalanceBefore = account.balance;
        uint256 escrowBalanceBefore = address(escrow).balance;

        bytes memory accountCode = account.code;
        if (accountCode.length > 0) {
            vm.etch(account, bytes(""));
        }

        vm.prank(account);
        escrow.withdrawETH();

        if (accountCode.length > 0) {
            vm.etch(account, accountCode);
        }

        assertEq(address(escrow).balance, escrowBalanceBefore - amount);
        assertEq(account.balance, accountBalanceBefore + amount);

        _debug.debug("Account %s withdrew %s ETH from escrow", account, amount.formatEther());
    }

    function _calculateLockedSharesAndUnstETHInEscrow(
        Escrow escrow,
        address account
    ) internal view returns (uint256 sharesLocked, uint256 unstETHUnclaimed) {
        Escrow.VetoerDetails memory vetoerDetails = escrow.getVetoerDetails(account);
        sharesLocked = vetoerDetails.stETHLockedShares.toUint256();

        uint256[] memory unstETHIds = escrow.getVetoerUnstETHIds(account);

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalStatuses =
            _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);
        Escrow.LockedUnstETHDetails[] memory unstETHDetails = escrow.getLockedUnstETHDetails(unstETHIds);

        for (uint256 i = 0; i < unstETHDetails.length; ++i) {
            if (unstETHDetails[i].status != UnstETHRecordStatus.Withdrawn) {
                unstETHUnclaimed += withdrawalStatuses[i].amountOfStETH;
            }
        }
    }

    function _getSimulationAccount(uint256 index) internal returns (address) {
        string memory accountName = string(bytes.concat("SIMULATION_ACC_", bytes(Strings.toString(index))));
        return makeAddr(accountName);
    }

    function _submitStETHByRandomAccount(address[] storage accounts) internal {
        _debug.debug(">>> Submitting stETH by random account");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = account.balance;

            if (balance < MIN_ST_ETH_SUBMIT_AMOUNT) {
                continue;
            }

            uint256 submitAmount =
                _random.nextUint256(MIN_ST_ETH_SUBMIT_AMOUNT, Math.min(balance, MAX_ST_ETH_SUBMIT_AMOUNT));

            uint256 stEthBalanceBefore = _lido.stETH.balanceOf(account);

            vm.prank(account);
            _lido.stETH.submit{value: submitAmount}(address(0));

            _totalSubmittedStETH += submitAmount;
            _accountsDetails[account].stETHSubmitted += submitAmount;

            assertApproxEqAbs(_lido.stETH.balanceOf(account), stEthBalanceBefore + submitAmount, 2 gwei);
            assertEq(account.balance, balance - submitAmount);

            _debug.debug("Account %s submitted %s stETH.", account, submitAmount.formatEther(), balance.formatEther());
            return;
        }
    }

    function _submitWstETHByRandomAccount(address[] storage accounts) internal {
        _debug.debug(">>> Submitting wstETH by random account");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = account.balance;
            uint256 stEthBalance = _lido.stETH.balanceOf(account);
            uint256 wstEthBalance = _lido.wstETH.balanceOf(account);

            if (balance < MIN_WST_ETH_SUBMIT_AMOUNT) {
                continue;
            }

            uint256 submitAmount =
                _random.nextUint256(MIN_WST_ETH_SUBMIT_AMOUNT, Math.min(balance, MAX_WST_ETH_SUBMIT_AMOUNT));

            vm.startPrank(account);
            _lido.stETH.submit{value: submitAmount}(address(0));
            _lido.stETH.approve(address(_lido.wstETH), submitAmount);
            uint256 wstEthMinted = _lido.wstETH.wrap(submitAmount);
            vm.stopPrank();

            assertEq(wstEthMinted, _lido.stETH.getSharesByPooledEth(submitAmount));

            _totalSubmittedWstETH += wstEthMinted;
            _accountsDetails[account].wstETHSubmitted += wstEthMinted;

            assertApproxEqAbs(_lido.stETH.balanceOf(account), stEthBalance, 2 gwei);
            assertApproxEqAbs(_lido.wstETH.balanceOf(account), wstEthBalance + wstEthMinted, 2 gwei);
            assertEq(account.balance, balance - submitAmount);

            _debug.debug("Account %s submitted %s wstETH.", account, wstEthMinted.formatEther(), balance.formatEther());
            return;
        }
    }

    function _withdrawStETHByRandomSimulationAccount() internal {
        _debug.debug(">>> Withdrawing stETH by simulation account");
        _totalWithdrawnStETHBySimulationAccounts += _withdrawStETHByRandomAccount(_simulationAccounts);
    }

    function _withdrawStETHByRandomRealAccount() internal {
        _debug.debug(">>> Withdrawing stETH by real account");
        _totalWithdrawnStETHByRealAccounts += _withdrawStETHByRandomAccount(_stETHRealHolders);
    }

    function _withdrawStETHByRandomAccount(address[] storage accounts) internal returns (uint256 requestedAmount) {
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.stETH.balanceOf(account);

            if (balance < MIN_ST_ETH_WITHDRAW_AMOUNT) {
                continue;
            }

            uint256 withdrawAmount =
                _random.nextUint256(MIN_ST_ETH_WITHDRAW_AMOUNT, Math.min(balance, MAX_ST_ETH_WITHDRAW_AMOUNT));
            uint256 batchSize = withdrawAmount / WITHDRAWAL_QUEUE_REQUEST_MAX_AMOUNT;
            uint256 lastRequestAmount = withdrawAmount % WITHDRAWAL_QUEUE_REQUEST_MAX_AMOUNT;
            if (lastRequestAmount > MIN_ST_ETH_WITHDRAW_AMOUNT) {
                batchSize += 1;
            }

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

            _debug.debug("Account %s withdrawn %s stETH.", account, requestedAmount.formatEther());
            _debug.debug("Request ids: %s-%s", requestIds[0], requestIds[requestIds.length - 1]);

            return requestedAmount;
        }
    }

    function _withdrawWstETHByRandomSimulationAccount() internal {
        _debug.debug(">>> Withdrawing wstETH by simulation account");
        _totalWithdrawnWstETHBySimulationAccounts += _withdrawWstETHByRandomAccount(_simulationAccounts);
    }

    function _withdrawWstETHByRandomRealAccount() internal {
        _debug.debug(">>> Withdrawing wstETH by real account");
        _totalWithdrawnWstETHByRealAccounts += _withdrawWstETHByRandomAccount(_wstETHRealHolders);
    }

    function _withdrawWstETHByRandomAccount(address[] storage accounts) internal returns (uint256 requestedAmount) {
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.wstETH.balanceOf(account);
            if (balance < MIN_WST_ETH_WITHDRAW_AMOUNT) {
                continue;
            }

            uint256 wstETHRequestMaxAmount = _lido.stETH.getSharesByPooledEth(WITHDRAWAL_QUEUE_REQUEST_MAX_AMOUNT);

            uint256 withdrawAmount =
                _random.nextUint256(MIN_WST_ETH_WITHDRAW_AMOUNT, Math.min(balance, wstETHRequestMaxAmount));
            uint256 batchSize = withdrawAmount / wstETHRequestMaxAmount;
            uint256 lastRequestAmount = withdrawAmount % wstETHRequestMaxAmount;
            if (lastRequestAmount > MIN_WST_ETH_WITHDRAW_AMOUNT) {
                batchSize += 1;
            }

            uint256[] memory withdrawalAmounts = new uint256[](batchSize);

            for (uint256 j = 0; j < batchSize; ++j) {
                if (j == batchSize - 1 && lastRequestAmount > MIN_WST_ETH_WITHDRAW_AMOUNT) {
                    withdrawalAmounts[j] = lastRequestAmount;
                } else {
                    withdrawalAmounts[j] = wstETHRequestMaxAmount;
                }
                requestedAmount += withdrawalAmounts[j];
            }
            uint256[] memory requestIds;
            vm.startPrank(account);
            {
                _lido.wstETH.approve(address(_lido.withdrawalQueue), requestedAmount);
                requestIds = _lido.withdrawalQueue.requestWithdrawalsWstETH(withdrawalAmounts, account);
            }
            vm.stopPrank();

            for (uint256 j = 0; j < requestIds.length; ++j) {
                _accountsDetails[account].unstETHIdsRequested.push(requestIds[j]);
            }

            _totalWithdrawnWstETH += requestedAmount;
            _debug.debug("Account %s withdrawn %s wstETH.", account, requestedAmount.formatEther());
            _debug.debug("Request ids: %s-%s", requestIds[0], requestIds[requestIds.length - 1]);

            return requestedAmount;
        }
    }

    function _lockStETHByRandomSimulationAccount() internal {
        _debug.debug(">>> Locking stETH in signalling escrow by simulation account");
        _totalLockedStETHBySimulationAccounts += _lockStETHByRandomAccount(_simulationAccounts);
    }

    function _lockStETHByRandomRealAccount() internal {
        _debug.debug(">>> Locking stETH in signalling escrow by real account");
        _totalLockedStETHByRealAccounts += _lockStETHByRandomAccount(_stETHRealHolders);
    }

    function _lockStETHByRandomAccount(address[] storage accounts) internal returns (uint256 lockAmount) {
        _activateNextStateIfNeeded();
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.stETH.balanceOf(account);

            if (balance < MIN_ST_ETH_SUBMIT_AMOUNT) {
                continue;
            }

            lockAmount = _random.nextUint256(MIN_ST_ETH_LOCK_AMOUNT, Math.min(balance, MAX_ST_ETH_LOCK_AMOUNT));

            _lockStETH(account, lockAmount);
            _totalLockedStETH += lockAmount;

            _accountsDetails[account].sharesLockedInEscrow[_getCurrentEscrowAddress()] +=
                _lido.stETH.getSharesByPooledEth(lockAmount);

            _debug.debug("Account %s locked %s stETH in signalling escrow", account, lockAmount.formatEther());
            return lockAmount;
        }
    }

    function _lockWstETHByRandomSimulationAccount() internal {
        _debug.debug(">>> Locking wstETH in signalling escrow by simulation account");
        _totalLockedWstETHBySimulationAccounts += _lockWstETHByRandomAccount(_simulationAccounts);
    }

    function _lockWstETHByRandomRealAccount() internal {
        _debug.debug(">>> Locking wstETH in signalling escrow by real account");
        _totalLockedWstETHByRealAccounts += _lockWstETHByRandomAccount(_wstETHRealHolders);
    }

    function _lockWstETHByRandomAccount(address[] storage accounts) internal returns (uint256 lockAmount) {
        _activateNextStateIfNeeded();
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.wstETH.balanceOf(account);

            if (balance < MIN_WST_ETH_SUBMIT_AMOUNT) {
                continue;
            }

            lockAmount = _random.nextUint256(MIN_WST_ETH_LOCK_AMOUNT, Math.min(balance, MAX_WST_ETH_LOCK_AMOUNT));

            _lockWstETH(account, lockAmount);
            _totalLockedWstETH += lockAmount;

            _accountsDetails[account].sharesLockedInEscrow[_getCurrentEscrowAddress()] += lockAmount;
            _accountsDetails[account].accumulatedEscrowSharesErrors[_getCurrentEscrowAddress()]++;

            _debug.debug(
                "Account %s locked %s wstETH in signalling escrow",
                account,
                lockAmount.formatEther(),
                balance.formatEther()
            );
            return lockAmount;
        }
    }

    function _lockUnstETHByRandomSimulationAccount() internal {
        _debug.debug(">>> Locking unstETH by simulation account");
        (uint256 unstETHAmount, uint256 unstETHCount) = _lockUnstETHByRandomAccount(_simulationAccounts);
        _totalLockedUnstETHBySimulationAccountsAmount += unstETHAmount;
        _totalLockedUnstETHBySimulationAccountsCount += unstETHCount;
    }

    function _lockUnstETHByRandomRealAccount() internal {
        _debug.debug(">>> Locking unstETH by real account");
        (uint256 unstETHAmount, uint256 unstETHCount) = _lockUnstETHByRandomAccount(_allRealHolders);
        _totalLockedUnstETHByRealAccountsAmount += unstETHAmount;
        _totalLockedUnstETHByRealAccountsCount += unstETHCount;
    }

    function _lockUnstETHByRandomAccount(address[] memory accounts)
        internal
        returns (uint256 totalLockedAmount, uint256 totalLockedCount)
    {
        _activateNextStateIfNeeded();
        uint256 lastFinalizedRequestId = _lido.withdrawalQueue.getLastFinalizedRequestId();
        uint256 maxRequestsToLock = _random.nextUint256(1, 64);
        Uint256ArrayBuilder.Context memory requestsArrayBuilder = Uint256ArrayBuilder.create(maxRequestsToLock);

        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

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
                Escrow.SignallingEscrowDetails memory escrowDetailsBefore =
                    _getVetoSignallingEscrow().getSignallingEscrowDetails();

                _lockUnstETH(account, requestsArrayBuilder.getResult());

                Escrow.SignallingEscrowDetails memory escrowDetailsAfter =
                    _getVetoSignallingEscrow().getSignallingEscrowDetails();

                totalLockedCount += requestsArrayBuilder.size;

                totalLockedAmount += _lido.stETH.getPooledEthByShares(
                    (
                        escrowDetailsAfter.totalUnstETHUnfinalizedShares
                            - escrowDetailsBefore.totalUnstETHUnfinalizedShares
                    ).toUint256()
                );

                for (uint256 j = 0; j < requestsArrayBuilder.size; ++j) {
                    _accountsDetails[account].unstETHIdsLockedInEscrow[_getCurrentEscrowAddress()].push(
                        requestsArrayBuilder.getResult()[j]
                    );
                }
                _debug.debug("Account %s locked %d unstETH in signalling escrow", account, requestsArrayBuilder.size);
                return (totalLockedAmount, totalLockedCount);
            }
        }
    }

    function _claimUnstETHByRandomSimulationAccount() internal {
        _debug.debug(">>> Claiming unstETH by simulation account");
        _totalClaimedUnstETHBySimulationAccountsAmount += _claimUnstETHByRandomAccount(_simulationAccounts);
        _totalClaimedUnstETHBySimulationAccountsCount++;
    }

    function _claimUnstETHByRandomRealAccount() internal {
        _debug.debug(">>> Claiming unstETH by real account");
        _totalClaimedUnstETHByRealAccountsAmount += _claimUnstETHByRandomAccount(_allRealHolders);
        _totalClaimedUnstETHByRealAccountsCount++;
    }

    function _claimUnstETHByRandomAccount(address[] memory accounts) internal returns (uint256 totalClaimedAmount) {
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

                bytes memory accountCode = account.code;
                if (accountCode.length > 0) {
                    vm.etch(account, bytes(""));
                }

                uint256 balanceBefore = account.balance;

                vm.prank(account);
                _lido.withdrawalQueue.claimWithdrawals(requestIdsToClaim, hints);

                if (accountCode.length > 0) {
                    vm.etch(account, accountCode);
                }

                _debug.debug("Account %s claimed %d unstETH NFTs", account, requestIdsToClaim.length);
                totalClaimedAmount = account.balance - balanceBefore;
                return totalClaimedAmount;
            }
        }
    }

    function _markRandomUnstETHFinalized() internal {
        _debug.debug(">>> Marking random unstETH finalized");
        _activateNextStateIfNeeded();
        uint256[] memory requestIds = _lido.withdrawalQueue.getWithdrawalRequests(address(_getVetoSignallingEscrow()));
        if (requestIds.length == 0) {
            return;
        }

        uint256 randomRequestIdIndex = _random.nextUint256(0, requestIds.length);
        uint256 requestsCountToFinalize = Math.min(requestIds.length, _random.nextUint256(1, 128));
        Uint256ArrayBuilder.Context memory requestsArrayBuilder = Uint256ArrayBuilder.create(requestsCountToFinalize);

        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            _lido.withdrawalQueue.getWithdrawalStatus(requestIds);

        for (uint256 i = 0; i < requestsCountToFinalize; ++i) {
            uint256 index = (randomRequestIdIndex + i) % requestIds.length;
            if (statuses[index].isFinalized) {
                requestsArrayBuilder.addItem(requestIds[index]);
                _totalMarkedUnstETHFinalizedAmount += statuses[index].amountOfStETH;
            }
        }

        if (requestsArrayBuilder.size == 0) {
            return;
        }

        uint256[] memory requestIdsToFinalize = requestsArrayBuilder.getSorted();
        uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
            requestIdsToFinalize, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );

        _totalMarkedUnstETHFinalizedCount += requestIdsToFinalize.length;

        _getVetoSignallingEscrow().markUnstETHFinalized(requestIdsToFinalize, hints);

        _debug.debug(
            "Marked %d unstETH NFTs with ids: %s-%s as finalized",
            requestIdsToFinalize.length,
            requestIdsToFinalize[0],
            requestIdsToFinalize[requestIdsToFinalize.length - 1]
        );
    }

    function _unlockStETHByRandomSimulationAccount() internal {
        _debug.debug(">>> Unlocking stETH by simulation accounts");
        _totalUnlockedStETHBySimulationAccounts += _unlockStETHByRandomAccount(_simulationAccounts);
    }

    function _unlockStETHByRandomRealAccount() internal {
        _debug.debug(">>> Unlocking stETH by real accounts");
        _totalUnlockedStETHByRealAccounts += _unlockStETHByRandomAccount(_allRealHolders);
    }

    function _unlockStETHByRandomAccount(address[] memory accounts) internal returns (uint256 unlockedStETH) {
        _activateNextStateIfNeeded();
        ISignallingEscrow escrow = _getVetoSignallingEscrow();

        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];
            Escrow.VetoerDetails memory details = escrow.getVetoerDetails(account);
            if (
                details.stETHLockedShares.toUint256() == 0
                    || Timestamps.now() <= escrow.getMinAssetsLockDuration().addTo(details.lastAssetsLockTimestamp)
            ) {
                continue;
            }
            assertApproxEqAbs(
                _accountsDetails[account].sharesLockedInEscrow[_getCurrentEscrowAddress()],
                details.stETHLockedShares.toUint256(),
                _accountsDetails[account].accumulatedEscrowSharesErrors[_getCurrentEscrowAddress()]
            );

            _unlockStETH(account);
            unlockedStETH += _lido.stETH.getPooledEthByShares(details.stETHLockedShares.toUint256());

            _accountsDetails[account].sharesLockedInEscrow[_getCurrentEscrowAddress()] = 0;
            _accountsDetails[account].accumulatedEscrowSharesErrors[_getCurrentEscrowAddress()] = 0;

            _debug.debug(
                "Account %s unlocked %s stETH from signalling escrow",
                account,
                _lido.stETH.getPooledEthByShares(details.stETHLockedShares.toUint256()).formatEther()
            );
            return unlockedStETH;
        }
    }

    function _unlockWstETHByRandomSimulationAccount() internal {
        _debug.debug(">>> Unlocking wstETH by simulation accounts");
        _totalUnlockedWstETHBySimulationAccounts += _unlockWstETHByRandomAccount(_simulationAccounts);
    }

    function _unlockWstETHByRandomRealAccount() internal {
        _debug.debug(">>> Unlocking wstETH by real accounts");
        _totalUnlockedWstETHByRealAccounts += _unlockWstETHByRandomAccount(_wstETHRealHolders);
    }

    function _unlockWstETHByRandomAccount(address[] memory accounts) internal returns (uint256 unlockedWstETH) {
        _activateNextStateIfNeeded();
        ISignallingEscrow escrow = _getVetoSignallingEscrow();

        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            Escrow.VetoerDetails memory details = escrow.getVetoerDetails(account);
            if (
                details.stETHLockedShares.toUint256() == 0
                    || Timestamps.now() <= escrow.getMinAssetsLockDuration().addTo(details.lastAssetsLockTimestamp)
            ) {
                continue;
            }

            assertApproxEqAbs(
                _accountsDetails[account].sharesLockedInEscrow[_getCurrentEscrowAddress()],
                details.stETHLockedShares.toUint256(),
                _accountsDetails[account].accumulatedEscrowSharesErrors[_getCurrentEscrowAddress()]
            );

            _unlockWstETH(account);
            unlockedWstETH += details.stETHLockedShares.toUint256();

            _accountsDetails[account].sharesLockedInEscrow[_getCurrentEscrowAddress()] = 0;
            _accountsDetails[account].accumulatedEscrowSharesErrors[_getCurrentEscrowAddress()] = 0;

            _debug.debug(
                "Account %s unlocked %s wstETH from signalling escrow",
                account,
                details.stETHLockedShares.toUint256().formatEther()
            );

            return unlockedWstETH;
        }
    }

    function _unlockUnstETHByRandomSimulationAccount() internal {
        _debug.debug(">>> Unlocking unstETH by simulation account");
        (uint256 unstETHCount, uint256 unstETHAmount) = _unlockUnstETHByRandomAccount(_simulationAccounts);
        _totalUnlockedUnstETHBySimulationAccountsCount += unstETHCount;
        _totalUnlockedUnstETHBySimulationAccountsAmount += unstETHAmount;
    }

    function _unlockUnstETHByRandomRealAccount() internal {
        _debug.debug(">>> Unlocking unstETH by real account");
        (uint256 unstETHCount, uint256 unstETHAmount) = _unlockUnstETHByRandomAccount(_allRealHolders);
        _totalUnlockedUnstETHByRealAccountsCount += unstETHCount;
        _totalUnlockedUnstETHByRealAccountsAmount += unstETHAmount;
    }

    function _unlockUnstETHByRandomAccount(address[] memory accounts)
        internal
        returns (uint256 unstETHCount, uint256 unstETHAmount)
    {
        _activateNextStateIfNeeded();
        ISignallingEscrow escrow = _getVetoSignallingEscrow();

        uint256 randomIndexOffset = _random.nextUint256(accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];
            Escrow.VetoerDetails memory details = escrow.getVetoerDetails(account);

            if (
                details.unstETHIdsCount == 0
                    || Timestamps.now() <= escrow.getMinAssetsLockDuration().addTo(details.lastAssetsLockTimestamp)
            ) {
                continue;
            }
            uint256 randomUnstETHIdsCountToWithdraw = _random.nextUint256(1, details.unstETHIdsCount);
            uint256[] memory lockedUnstETHIds = escrow.getVetoerUnstETHIds(account);
            IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
                _lido.withdrawalQueue.getWithdrawalStatus(lockedUnstETHIds);
            uint256[] memory randomIndices = _random.nextPermutation(randomUnstETHIdsCountToWithdraw);

            Uint256ArrayBuilder.Context memory unstETHIdsBuilder =
                Uint256ArrayBuilder.create(randomUnstETHIdsCountToWithdraw);

            for (uint256 j = 0; j < randomUnstETHIdsCountToWithdraw; ++j) {
                if (!statuses[randomIndices[j]].isFinalized) {
                    unstETHIdsBuilder.addItem(lockedUnstETHIds[randomIndices[j]]);
                    unstETHAmount += statuses[randomIndices[j]].amountOfStETH;
                }
            }

            if (unstETHIdsBuilder.size == 0) {
                continue;
            }

            _unlockUnstETH(account, unstETHIdsBuilder.getSorted());
            unstETHCount += details.unstETHIdsCount;
            unstETHAmount += unstETHAmount;

            _debug.debug("Account %s unlocked %d unstETH from signalling escrow", account, details.unstETHIdsCount);

            return (unstETHCount, unstETHAmount);
        }
    }

    function _accidentalETHTransfer(address[] memory accounts) internal {
        _debug.debug(">>> Accidental ETH transfer");
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
            _accountsDetails[account].accidentalETHTransferAmount += transferAmount;
            _accidentalETHTransfersByEscrow[escrow] += transferAmount;

            _debug.debug(
                "Account %s transferred %s ETH to escrow %s", account, transferAmount.formatEther(), address(escrow)
            );

            return;
        }
    }

    function _accidentalStETHTransfer(address[] memory accounts) internal {
        _debug.debug(">>> Accidental stETH transfer");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);
        address payable escrow = _getCurrentEscrowAddress();

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.stETH.balanceOf(account);
            if (balance < MIN_ACCIDENTAL_TRANSFER_AMOUNT) {
                continue;
            }

            uint256 transferAmount =
                _random.nextUint256(MIN_ACCIDENTAL_TRANSFER_AMOUNT, Math.min(balance, MAX_ACCIDENTAL_TRANSFER_AMOUNT));
            vm.prank(account);
            _lido.stETH.transfer(escrow, transferAmount);

            _totalAccidentalStETHTransferAmount += transferAmount;
            _accountsDetails[account].accidentalStETHTransferAmount += transferAmount;
            _accidentalStETHTransfersByEscrow[escrow] += transferAmount;

            _debug.debug(
                "Account %s transferred %s stETH to escrow %s", account, transferAmount.formatEther(), address(escrow)
            );

            return;
        }
    }

    function _accidentalWstETHTransfer(address[] memory accounts) internal {
        _debug.debug(">>> Accidental wstETH transfer");
        uint256 randomIndexOffset = _random.nextUint256(accounts.length);
        address payable escrow = _getCurrentEscrowAddress();

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[(randomIndexOffset + i) % accounts.length];

            uint256 balance = _lido.wstETH.balanceOf(account);
            if (balance < MIN_ACCIDENTAL_TRANSFER_AMOUNT) {
                continue;
            }

            uint256 transferAmount =
                _random.nextUint256(MIN_ACCIDENTAL_TRANSFER_AMOUNT, Math.min(balance, MAX_ACCIDENTAL_TRANSFER_AMOUNT));
            vm.prank(account);
            _lido.wstETH.transfer(escrow, transferAmount);

            _totalAccidentalWstETHTransferAmount += transferAmount;
            _accountsDetails[account].accidentalWstETHTransferAmount += transferAmount;
            _accidentalWstETHTransfersByEscrow[escrow] += transferAmount;

            _debug.debug(
                "Account %s transferred %s wstETH to escrow %s", account, transferAmount.formatEther(), address(escrow)
            );

            return;
        }
    }

    function _accidentalUnstETHTransfer(address[] memory accounts) internal {
        _debug.debug(">>> Accidental unstETH transfer");
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
            requestAmounts[0] =
                _random.nextUint256(MIN_ACCIDENTAL_TRANSFER_AMOUNT, Math.min(balance, MAX_ACCIDENTAL_TRANSFER_AMOUNT));
            _lido.stETH.approve(address(_lido.withdrawalQueue), requestAmounts[0]);
            _lido.withdrawalQueue.requestWithdrawals(requestAmounts, escrow);
            vm.stopPrank();

            _totalAccidentalUnstETHTransferAmount += requestAmounts[0];
            _accountsDetails[account].accidentalUnstETHTransferAmount += requestAmounts[0];

            _debug.debug(
                "Account %s transferred %s unstETH to escrow %s",
                account,
                requestAmounts[0].formatEther(),
                address(escrow)
            );

            return;
        }
    }

    function _mineBlock() internal {
        vm.warp(block.timestamp + SLOT_DURATION);
        vm.roll(block.number + 1);
    }

    function _getRandomUniqueActionsSet() internal returns (SimulationActionsSet.Context memory result) {
        result = SimulationActionsSet.create();

        // Simulation accounts actions

        if (_getRandomProbability() <= SUBMIT_STETH_PROBABILITY) {
            result.add(SimulationActionType.SubmitStETH);
            _actionsCounters[SimulationActionType.SubmitStETH] += 1;
        }

        if (_getRandomProbability() <= SUBMIT_WSTETH_PROBABILITY) {
            result.add(SimulationActionType.SubmitWstETH);
            _actionsCounters[SimulationActionType.SubmitWstETH] += 1;
        }

        if (_getRandomProbability() <= WITHDRAW_STETH_PROBABILITY) {
            result.add(SimulationActionType.WithdrawStETH);
            _actionsCounters[SimulationActionType.WithdrawStETH] += 1;
        }

        if (_getRandomProbability() <= WITHDRAW_WSTETH_PROBABILITY) {
            result.add(SimulationActionType.WithdrawWstETH);
            _actionsCounters[SimulationActionType.WithdrawWstETH] += 1;
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

        if (_getRandomProbability() <= CLAIM_UNSTETH_PROBABILITY) {
            result.add(SimulationActionType.ClaimUnstETH);
            _actionsCounters[SimulationActionType.ClaimUnstETH] += 1;
        }

        // Real accounts actions

        if (_getRandomProbability() <= WITHDRAW_STETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.WithdrawStETHRealHolder);
            _actionsCounters[SimulationActionType.WithdrawStETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= WITHDRAW_WSTETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.WithdrawWstETHRealHolder);
            _actionsCounters[SimulationActionType.WithdrawWstETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= LOCK_STETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.LockStETHRealHolder);
            _actionsCounters[SimulationActionType.LockStETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= LOCK_WSTETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.LockWstETHRealHolder);
            _actionsCounters[SimulationActionType.LockWstETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= LOCK_UNSTETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.LockUnstETHRealHolder);
            _actionsCounters[SimulationActionType.LockUnstETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= UNLOCK_STETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.UnlockStETHRealHolder);
            _actionsCounters[SimulationActionType.UnlockStETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= UNLOCK_WSTETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.UnlockWstETHRealHolder);
            _actionsCounters[SimulationActionType.UnlockWstETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= UNLOCK_UNSTETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.UnlockUnstETHRealHolder);
            _actionsCounters[SimulationActionType.UnlockUnstETHRealHolder] += 1;
        }

        if (_getRandomProbability() <= CLAIM_UNSTETH_REAL_HOLDER_PROBABILITY) {
            result.add(SimulationActionType.ClaimUnstETHRealHolder);
            _actionsCounters[SimulationActionType.ClaimUnstETHRealHolder] += 1;
        }

        // General actions

        if (_getRandomProbability() <= MARK_UNST_ETH_FINALIZED_PROBABILITY) {
            result.add(SimulationActionType.MarkUnstETHFinalized);
            _actionsCounters[SimulationActionType.MarkUnstETHFinalized] += 1;
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
    }

    function _processSimulationActions(SimulationActionsSet.Context memory actions) internal {
        // Simulation accounts actions

        if (actions.has(SimulationActionType.SubmitStETH)) {
            _submitStETHByRandomAccount(_simulationAccounts);
            _mineBlock();
        }

        if (actions.has(SimulationActionType.SubmitWstETH)) {
            _submitWstETHByRandomAccount(_simulationAccounts);
            _mineBlock();
        }

        if (actions.has(SimulationActionType.WithdrawStETH)) {
            _withdrawStETHByRandomSimulationAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.WithdrawWstETH)) {
            _withdrawWstETHByRandomSimulationAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.LockStETH)) {
            _lockStETHByRandomSimulationAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.LockWstETH)) {
            _lockWstETHByRandomSimulationAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.LockUnstETH)) {
            _lockUnstETHByRandomSimulationAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.UnlockStETH)) {
            _unlockStETHByRandomSimulationAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.UnlockWstETH)) {
            _unlockWstETHByRandomSimulationAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.UnlockUnstETH)) {
            _unlockUnstETHByRandomSimulationAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.ClaimUnstETH)) {
            _claimUnstETHByRandomSimulationAccount();
            _mineBlock();
        }

        // Real accounts actions

        if (actions.has(SimulationActionType.WithdrawStETHRealHolder)) {
            _withdrawStETHByRandomRealAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.WithdrawWstETHRealHolder)) {
            _withdrawWstETHByRandomRealAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.LockStETHRealHolder)) {
            _lockStETHByRandomRealAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.LockWstETHRealHolder)) {
            _lockWstETHByRandomRealAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.UnlockStETHRealHolder)) {
            _unlockStETHByRandomRealAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.UnlockWstETHRealHolder)) {
            _unlockWstETHByRandomRealAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.UnlockUnstETHRealHolder)) {
            _unlockUnstETHByRandomRealAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.LockUnstETHRealHolder)) {
            _lockUnstETHByRandomRealAccount();
            _mineBlock();
        }

        if (actions.has(SimulationActionType.ClaimUnstETHRealHolder)) {
            _claimUnstETHByRandomRealAccount();
            _mineBlock();
        }

        // General actions

        if (actions.has(SimulationActionType.MarkUnstETHFinalized)) {
            _markRandomUnstETHFinalized();
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

        if (actions.isEmpty()) {
            _mineBlock();
        }
    }

    function _getRandomProbability() internal returns (PercentD16) {
        return PercentsD16.from(_random.nextUint256(HUNDRED_PERCENT_D16));
    }

    function _loadHoldersFromFile(string memory path) internal view returns (address[] memory) {
        string memory vetoersFileRaw = vm.readFile(path);
        bytes memory data = vm.parseJson(vetoersFileRaw);
        VetoersFile memory vetoersFile = abi.decode(data, (VetoersFile));
        return vetoersFile.addresses;
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
            vm.deal(_simulationAccounts[i], _random.nextUint256(50_000 ether));
        }
    }

    function _setupAccounts() internal {
        _loadHolders();
        _setupSimulationAccounts();

        for (uint256 i = 0; i < _allAccounts.length; ++i) {
            address account = _allAccounts[i];

            _accountsDetails[account].ethBalanceBefore = account.balance;
            _accountsDetails[account].stETHBalanceBefore =
                _lido.stETH.balanceOf(account) + _lido.stETH.getPooledEthByShares(_lido.wstETH.balanceOf(account));
            _accountsDetails[account].sharesBalanceBefore =
                _lido.wstETH.balanceOf(account) + _lido.stETH.getSharesByPooledEth(_lido.stETH.balanceOf(account));

            uint256[] memory requestIds = _lido.withdrawalQueue.getWithdrawalRequests(account);

            if (requestIds.length == 0) {
                continue;
            }

            IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
                _lido.withdrawalQueue.getWithdrawalStatus(requestIds);

            uint256 unstETHBalance = 0;
            for (uint256 j = 0; j < statuses.length; ++j) {
                if (!statuses[j].isClaimed) {
                    unstETHBalance += statuses[j].amountOfStETH;
                    _accountsDetails[account].unstETHIdsRequested.push(requestIds[j]);
                }
            }
            _accountsDetails[account].unstETHBalanceBefore = unstETHBalance;
        }
    }

    function _getCurrentEscrowAddress() internal view returns (address payable) {
        return payable(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow());
    }

    function _printSimulationStats(uint256 iterationsCount) internal view {
        LogTable.logActionsHeader();

        LogTable.logRow("Submit StETH");
        LogTable.logRow(
            "Sim Accounts", _actionsCounters[SimulationActionType.SubmitStETH], _totalSubmittedStETH.formatEther()
        );
        LogTable.logRow("Submit WstETH");
        LogTable.logRow(
            "Sim Accounts", _actionsCounters[SimulationActionType.SubmitWstETH], _totalSubmittedWstETH.formatEther()
        );
        LogTable.logRow("Withdraw StETH");
        LogTable.logRow(
            "Sim Accounts",
            _actionsCounters[SimulationActionType.WithdrawStETH],
            _totalWithdrawnStETHBySimulationAccounts.formatEther()
        );
        LogTable.logRow(
            "Real Accounts",
            _actionsCounters[SimulationActionType.WithdrawStETHRealHolder],
            _totalWithdrawnStETHByRealAccounts.formatEther()
        );
        LogTable.logRow("Withdraw wstETH");
        LogTable.logRow(
            "Sim Accounts",
            _actionsCounters[SimulationActionType.WithdrawWstETH],
            _totalWithdrawnWstETHBySimulationAccounts.formatEther()
        );
        LogTable.logRow(
            "Real Accounts",
            _actionsCounters[SimulationActionType.WithdrawWstETHRealHolder],
            _totalWithdrawnWstETHByRealAccounts.formatEther()
        );

        LogTable.logRow("Claim unstETH");
        LogTable.logRow(
            "Sim Accounts",
            _actionsCounters[SimulationActionType.ClaimUnstETH],
            _totalClaimedUnstETHBySimulationAccountsAmount.formatEther()
        );

        LogTable.logRow(
            "Real Accounts",
            _actionsCounters[SimulationActionType.ClaimUnstETHRealHolder],
            _totalClaimedUnstETHByRealAccountsAmount.formatEther()
        );

        LogTable.logRow("Escrow Lock StETH");
        LogTable.logRow(
            "Sim Accounts",
            _actionsCounters[SimulationActionType.LockStETH],
            _totalLockedStETHBySimulationAccounts.formatEther()
        );
        LogTable.logRow(
            "Real Accounts",
            _actionsCounters[SimulationActionType.LockStETHRealHolder],
            _totalLockedStETHByRealAccounts.formatEther()
        );

        LogTable.logRow("Escrow Lock wstETH");
        LogTable.logRow(
            "Sim Accounts",
            _actionsCounters[SimulationActionType.LockWstETH],
            _totalLockedWstETHBySimulationAccounts.formatEther()
        );
        LogTable.logRow(
            "Real Accounts",
            _actionsCounters[SimulationActionType.LockWstETHRealHolder],
            _totalLockedWstETHByRealAccounts.formatEther()
        );

        //  TODO: Add counters for unstETH
        LogTable.logRow("Escrow Lock unstETH");
        LogTable.logRow(
            "Sim Accounts",
            _actionsCounters[SimulationActionType.LockUnstETH],
            _totalLockedUnstETHBySimulationAccountsAmount.formatEther()
        );
        LogTable.logRow(
            "Real Accounts",
            _actionsCounters[SimulationActionType.LockUnstETHRealHolder],
            _totalLockedUnstETHByRealAccountsAmount.formatEther()
        );
        LogTable.logRow("Escrow Unlock stETH");
        LogTable.logRow(
            "Sim Accounts",
            _actionsCounters[SimulationActionType.UnlockStETH],
            _totalUnlockedStETHBySimulationAccounts.formatEther()
        );
        LogTable.logRow(
            "Real Accounts",
            _actionsCounters[SimulationActionType.UnlockStETHRealHolder],
            _totalUnlockedStETHByRealAccounts.formatEther()
        );
        LogTable.logRow("Escrow Unlock wstETH");
        LogTable.logRow(
            "Sim Accounts",
            _actionsCounters[SimulationActionType.UnlockWstETH],
            _totalUnlockedWstETHBySimulationAccounts.formatEther()
        );
        LogTable.logRow(
            "Real Accounts",
            _actionsCounters[SimulationActionType.UnlockWstETHRealHolder],
            _totalUnlockedWstETHByRealAccounts.formatEther()
        );
        LogTable.logRow("Escrow Unlock unstETH");
        LogTable.logRow(
            "Sim Accounts",
            _totalUnlockedUnstETHBySimulationAccountsCount,
            _totalUnlockedUnstETHBySimulationAccountsAmount.formatEther()
        );
        LogTable.logRow(
            "Real Accounts",
            _totalUnlockedUnstETHByRealAccountsCount,
            _totalUnlockedUnstETHByRealAccountsAmount.formatEther()
        );

        LogTable.logRow("Mark unstETH finalized");
        LogTable.logRow(
            "All Accounts",
            _actionsCounters[SimulationActionType.MarkUnstETHFinalized],
            _totalMarkedUnstETHFinalizedAmount.formatEther()
        );
        LogTable.logRow("Accidental transfers");
        LogTable.logRow(
            "ETH",
            _actionsCounters[SimulationActionType.AccidentalETHTransfer],
            _totalAccidentalETHTransferAmount.formatEther()
        );
        LogTable.logRow(
            "stETH",
            _actionsCounters[SimulationActionType.AccidentalStETHTransfer],
            _totalAccidentalStETHTransferAmount.formatEther()
        );
        LogTable.logRow(
            "wstETH",
            _actionsCounters[SimulationActionType.AccidentalWstETHTransfer],
            _totalAccidentalWstETHTransferAmount.formatEther()
        );
        LogTable.logRow(
            "unstETH",
            _actionsCounters[SimulationActionType.AccidentalUnstETHTransfer],
            _totalAccidentalUnstETHTransferAmount.formatEther()
        );
        LogTable.logSeparator();

        uint256 initialVetoSignallingEscrowLockedStETH =
            _lido.stETH.getPooledEthByShares(_initialVetoSignallingEscrowLockedShares);

        LogTable.logHeader("  Rage Quit Escrow Stats");
        LogTable.logRow("Rage Quits count:", _rageQuitEscrows.length);
        LogTable.logSeparator();

        for (uint256 i = 0; i < _rageQuitEscrows.length; ++i) {
            LogTable.logRow("RageQuit escrow", address(_rageQuitEscrows[i]));
            LogTable.logRow("Is Rage Quit Finalized", _rageQuitEscrows[i].isRageQuitFinalized());
            if (i == 0) {
                LogTable.logRow("Initially locked stETH", initialVetoSignallingEscrowLockedStETH.formatEther());
            }
            console.log(" - Balances");
            LogTable.logRow("ETH", address(_rageQuitEscrows[i]).balance.formatEther());
            LogTable.logRow("stETH", _lido.stETH.balanceOf(address(_rageQuitEscrows[i])).formatEther());
            LogTable.logRow("wstETH", _lido.wstETH.balanceOf(address(_rageQuitEscrows[i])).formatEther());
            LogTable.logRow("unstETH", _lido.withdrawalQueue.balanceOf(address(_rageQuitEscrows[i])));

            console.log(" - Accidental Transfers");
            LogTable.logRow("ETH", _accidentalETHTransfersByEscrow[address(_rageQuitEscrows[i])].formatEther());
            LogTable.logRow("stETH", _accidentalStETHTransfersByEscrow[address(_rageQuitEscrows[i])].formatEther());
            LogTable.logRow("wstETH", _accidentalWstETHTransfersByEscrow[address(_rageQuitEscrows[i])].formatEther());
            LogTable.logRow("unstETH", _accidentalUnstETHTransfersByEscrow[address(_rageQuitEscrows[i])].formatEther());
            LogTable.logSeparator();
        }

        ISignallingEscrow signallingEscrow = _getVetoSignallingEscrow();
        LogTable.logHeader("  Veto Signalling Escrow Stats");
        LogTable.logRow("Veto Signalling Escrow", address(signallingEscrow));
        LogTable.logRow("DG State", _getDGStateName(_dgDeployedContracts.dualGovernance.getEffectiveState()));
        LogTable.logRow("Rage Quit Support:", signallingEscrow.getRageQuitSupport().format());
        LogTable.logRow("stETH Balance:", _lido.stETH.balanceOf(address(signallingEscrow)).formatEther());

        LogTable.logHeader("  Simulation Stats");

        PercentD16 rebasePercent =
            PercentsD16.fromFraction(_lido.stETH.getPooledEthByShares(10 ** 18), _initialShareRate);

        console.log("  - Iteration Count:      ", iterationsCount);
        console.log("  - Finalization Iters:   ", _finalizationPhaseIterations);
        console.log("  - Block Number:         ", block.number);
        console.log("  - Block Timestamp:      ", block.timestamp);
        console.log("  - stETH Total Supply:   ", _lido.stETH.totalSupply().formatEther());
        console.log("  - stETH Share Rate:     ", _lido.stETH.getPooledEthByShares(10 ** 18).formatEther());
        console.log("  - Rebase during test:   ", rebasePercent.format());
        console.log("  - Negative rebases:     ", _totalNegativeRebaseCount);
    }
}

contract SelfDestructSender {
    constructor(address payable recipient) payable {
        selfdestruct(recipient);
    }
}

library LogTable {
    function logRow(string memory col1, string memory col2, string memory col3) internal pure {
        string memory line = string.concat(_padLeft(col1, 28), " | ", _padLeft(col2, 7), " | ", _padLeft(col3, 20));
        console.log(line);
    }

    function logRow(string memory col1, string memory col2) internal pure {
        string memory line = string.concat(_padLeft(col1, 28), " | ", _padLeft(col2, 7));
        console.log(line);
    }

    function logRow(string memory col1, uint256 col2, string memory col3) internal pure {
        logRow(col1, uintToString(col2), col3);
    }

    function logRow(string memory col1, uint256 col2) internal pure {
        logRow(col1, uintToString(col2));
    }

    function logRow(string memory col1, address addr) internal pure {
        string memory line = string.concat(_padRight(col1, 28), " | ", _toHexString(addr));
        console.log(line);
    }

    function logRow(string memory label, bool value) internal pure {
        string memory boolStr = value ? "true" : "false";
        string memory line = string.concat(_padLeft(label, 28), " | ", boolStr);
        console.log(line);
    }

    function logActionsHeader() internal pure {
        console.log("\n");
        console.log("======================================================================");
        console.log("  Actions Stats");
        console.log("======================================================================");
        console.log("Action                       |  Count  |              Amount");
    }

    function logHeader(string memory header) internal pure {
        console.log("\n");
        console.log("======================================================================");
        console.log(header);
        console.log("======================================================================");
    }

    function logRow(string memory col1) internal pure {
        console.log("---------------------------------------------------------------------");
        console.log(_padRight(col1, 28));
    }

    function logSeparator() internal pure {
        console.log("---------------------------------------------------------------------");
    }

    function _padRight(string memory str, uint256 len) private pure returns (string memory) {
        bytes memory bStr = bytes(str);
        if (bStr.length >= len) return str;

        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < bStr.length; i++) {
            result[i] = bStr[i];
        }
        for (uint256 i = bStr.length; i < len; i++) {
            result[i] = " ";
        }
        return string(result);
    }

    function _padLeft(string memory str, uint256 len) private pure returns (string memory) {
        bytes memory bStr = bytes(str);
        if (bStr.length >= len) return str;

        bytes memory result = new bytes(len);
        uint256 pad = len - bStr.length;
        for (uint256 i = 0; i < pad; i++) {
            result[i] = " ";
        }
        for (uint256 i = 0; i < bStr.length; i++) {
            result[pad + i] = bStr[i];
        }
        return string(result);
    }

    function uintToString(uint256 val) internal pure returns (string memory) {
        if (val == 0) return "0";
        uint256 temp = val;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (val != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(val % 10)));
            val /= 10;
        }
        return string(buffer);
    }

    function _toHexString(address addr) private pure returns (string memory) {
        bytes20 value = bytes20(addr);
        bytes memory hexChars = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = hexChars[uint8(value[i] >> 4)];
            str[3 + i * 2] = hexChars[uint8(value[i] & 0x0f)];
        }
        return string(str);
    }
}

library Debug {
    struct Context {
        bool debuggingEnabled;
    }

    function debug(Context memory ctx, string memory message) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(message);
        }
    }

    function debug(Context memory ctx, string memory label, uint256 a, uint256 b, uint256 c) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(label, a, b, c);
        }
    }

    function debug(
        Context memory ctx,
        string memory label,
        address addr,
        uint256 val,
        string memory str
    ) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(label, addr, val, str);
        }
    }

    function debug(Context memory ctx, string memory label, address addr, uint256 val1, uint256 val2) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(label, addr, val1, val2);
        }
    }

    function debug(Context memory ctx, string memory label, address addr, uint256 val) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(label, addr, val);
        }
    }

    function debug(Context memory ctx, string memory label, uint256 val1, uint256 val2) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(label, val1, val2);
        }
    }

    function debug(
        Context memory ctx,
        string memory label,
        address addr,
        string memory str1,
        string memory str2
    ) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(label, addr, str1, str2);
        }
    }

    function debug(
        Context memory ctx,
        string memory label,
        address addr1,
        string memory str,
        address addr2
    ) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(label, addr1, str, addr2);
        }
    }

    function debug(Context memory ctx, string memory label, address addr) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(label, addr);
        }
    }

    function debug(Context memory ctx, string memory label, address addr, string memory str) internal pure {
        if (ctx.debuggingEnabled) {
            console.log(label, addr, str);
        }
    }
}
