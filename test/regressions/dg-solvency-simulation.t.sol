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
import {Timestamp} from "contracts/types/Timestamp.sol";
import {SharesValue} from "contracts/types/SharesValue.sol";
import {PercentsD16, PercentD16, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";
import {IWithdrawalQueue} from "test/utils/interfaces/IWithdrawalQueue.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";
import {Escrow} from "contracts/Escrow.sol";

import {DecimalsFormatting} from "test/utils/formatting.sol";

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
    MarkUnstETHFinalized
}
// UnlockStETH,
// UnlockWstETH,
// UnlockUnstETH,
//
// AccidentalETHTransfer,
// AccidentalStETHTransfer,
// AccidentalWtETHTransfer,
// AccidentalUntETHTransfer
//
// WithdrawStETHRealHolder
// WithdrawWstETHRealHolder
// ClaimUnstETHRealHolder

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

// Set value of the below variable to false if the simulation test should be run.
// Note: simulation test may take significant time to pass
bool constant SKIP_SIMULATION_TEST = true;

uint256 constant MIN_ST_ETH_WITHDRAW_AMOUNT = 1000 wei;
uint256 constant MAX_ST_ETH_WITHDRAW_AMOUNT = 1000 ether;

uint256 constant MIN_WST_ETH_WITHDRAW_AMOUNT = 1000 wei;
uint256 constant MAX_WST_ETH_WITHDRAW_AMOUNT = 700 ether;

// 3 times more than real slot duration to speed up test. Must not affect correctness of the test
uint256 constant SLOT_DURATION = 3 * 12 seconds;
uint256 constant SIMULATION_ACCOUNTS = 512;
uint256 constant SIMULATION_DURATION = 60 days;

uint256 constant MIN_ST_ETH_SUBMIT_AMOUNT = 0.1 ether;
uint256 constant MAX_ST_ETH_SUBMIT_AMOUNT = 750 ether;

uint256 constant MIN_WST_ETH_SUBMIT_AMOUNT = 0.1 ether;
uint256 constant MAX_WST_ETH_SUBMIT_AMOUNT = 500 ether;

uint256 constant ORACLE_REPORT_FREQUENCY = 24 hours;
uint256 constant WITHDRAWALS_FINALIZATION_FREQUENCY = 60 * 24 hours;

contract EscrowSolvencyTest is DGRegressionTestSetup {
    using Random for Random.Context;
    using DecimalsFormatting for uint256;
    using LidoUtils for LidoUtils.Context;
    using Uint256ArrayBuilder for Uint256ArrayBuilder.Context;
    using SimulationActionsSet for SimulationActionsSet.Context;

    PercentD16 immutable LOCK_ST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(3_00);
    PercentD16 immutable LOCK_WST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(2_75);
    PercentD16 immutable LOCK_UNST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(2_00);

    PercentD16 immutable MARK_UNST_ETH_FINALIZED_PROBABILITY = PercentsD16.fromBasisPoints(1_25);

    PercentD16 immutable SUBMIT_STETH_PROBABILITY = PercentsD16.fromBasisPoints(3_00);
    PercentD16 immutable SUBMIT_WSTETH_PROBABILITY = PercentsD16.fromBasisPoints(3_00);

    PercentD16 immutable WITHDRAW_STETH_PROBABILITY = PercentsD16.fromBasisPoints(50);
    PercentD16 immutable WITHDRAW_WSTETH_PROBABILITY = PercentsD16.fromBasisPoints(50);
    PercentD16 immutable CLAIM_UNSTETH_PROBABILITY = PercentsD16.fromBasisPoints(50);

    uint256 internal _totalLockedStETH = 0;
    uint256 internal _totalLockedWstETH = 0;
    uint256 internal _totalLockedUnstETH = 0;
    uint256 internal _totalSubmittedStETH = 0;
    uint256 internal _totalSubmittedWstETH = 0;
    uint256 internal _totalWithdrawnStETH = 0;
    uint256 internal _totalWithdrawnWstETH = 0;
    Escrow[] internal _rageQuitEscrows;

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

        // TODO: remove when test is finished. Currently preserved for debug purposes
        //
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
        uint256 nextRageQuitOperationDelay = 0;
        uint256 lastRageQuitOperationTimestamp = 0;
        uint256 minWithdrawalsBatchSize = Escrow(
            payable(address(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow()))
        ).MIN_WITHDRAWALS_BATCH_SIZE();
        // TODO: Add env flag to run this test, by default should not be run
        if (SKIP_SIMULATION_TEST) {
            vm.skip(true);
            return;
        }
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
                _withdrawStETHByRandomAccount();
                _mineBlock();
            }

            if (actions.has(SimulationActionType.WithdrawWstETH)) {
                _withdrawWstETHByRandomAccount();
                _mineBlock();
            }

            if (actions.has(SimulationActionType.LockStETH)) {
                _lockStETHInSignallingEscrowByRandomAccount();
                _mineBlock();
            }

            if (actions.has(SimulationActionType.LockWstETH)) {
                _lockWtETHInSignallingEscrowByRandomAccount();
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

            if (actions.isEmpty()) {
                _mineBlock();
            }

            if (_lastOracleReportTimestamp + ORACLE_REPORT_FREQUENCY < block.timestamp) {
                _lastOracleReportTimestamp = block.timestamp;

                uint256 requestIdToFinalize = _random.nextUint256(
                    _lido.withdrawalQueue.getLastFinalizedRequestId() + 1, _lido.withdrawalQueue.getLastRequestId() + 1
                );

                // TODO: add a rare case when the negative rebase happens
                uint256 rebaseAmount = _random.nextUint256(HUNDRED_PERCENT_D16, HUNDRED_PERCENT_D16 + 1 gwei);

                _lido.performRebase(PercentsD16.from(rebaseAmount), requestIdToFinalize);
            }

            DGState effectiveDGState = _dgDeployedContracts.dualGovernance.getEffectiveState();
            if (currentDGState != effectiveDGState) {
                if (currentDGState == DGState.RageQuit && effectiveDGState != DGState.RageQuit) {
                    console.log(">>> Exiting RageQuit state");
                }
                if (currentDGState != DGState.RageQuit && effectiveDGState == DGState.RageQuit) {
                    _rageQuitEscrows.push(
                        Escrow(payable(address(_dgDeployedContracts.dualGovernance.getRageQuitEscrow())))
                    );
                }
                console.log(
                    ">>> DG State changed from %s to %s",
                    _getDGStateName(currentDGState),
                    _getDGStateName(effectiveDGState)
                );
                currentDGState = effectiveDGState;
                _activateNextState();
            }

            // TODO: implement flow to handle ongoing rage quit
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

                for (uint256 i = 0; i < SIMULATION_ACCOUNTS; ++i) {
                    address account = _getSimulationAccount(i);
                    uint256[] memory lockedUnstETHIds = rageQuitEscrow.getVetoerUnstETHIds(account);

                    Uint256ArrayBuilder.Context memory unstETHIdsToClaimBuilder =
                        Uint256ArrayBuilder.create(lockedUnstETHIds.length);
                    if (lockedUnstETHIds.length > 0) {
                        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
                            _lido.withdrawalQueue.getWithdrawalStatus(lockedUnstETHIds);
                        for (uint256 j = 0; j < statuses.length; ++j) {
                            if (statuses[i].isFinalized && !statuses[i].isClaimed) {
                                unstETHIdsToClaimBuilder.addItem(lockedUnstETHIds[i]);
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
                                    claimedRanges, vm.toString(startUnstETHId), "-", vm.toString(currentUnstETHId), ","
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

            for (uint256 i = 0; i < _rageQuitEscrows.length; ++i) {
                Escrow escrow = _rageQuitEscrows[i];
                address account = _getRandomSimulationAccount();
                Escrow.VetoerDetails memory details = escrow.getVetoerDetails(account);
                if (details.stETHLockedShares.toUint256() > 0) {
                    vm.prank(account);
                    escrow.withdrawETH();
                }
            }
        }
        console.log("After simulation block number: %d, after simulation timestamp: %d", block.number, block.timestamp);
        console.log("After simulation stETH Total Supply: %s", _lido.stETH.totalSupply().formatEther());
        console.log("After simulation share rate: %s", _lido.stETH.getPooledEthByShares(10 ** 18).formatEther());

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

        console.log("  - Mark unstETH finalized count: %d", _actionsCounters[SimulationActionType.MarkUnstETHFinalized]);

        console.log("  - Claim unstETH count: %d", _actionsCounters[SimulationActionType.ClaimUnstETH]);

        ISignallingEscrow signallingEscrow =
            ISignallingEscrow(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow());
        console.log("Signalling Escrow Stats:");
        console.log("  - Rage Quit Support: %s", signallingEscrow.getRageQuitSupport().toUint256().format(16));
        console.log("  - stETH Balance: %s", _lido.stETH.balanceOf(address(signallingEscrow)).formatEther());

        // TODO: implement after simulation checks
    }

    function _getRandomSimulationAccount() internal returns (address) {
        return _getSimulationAccount(_random.nextUint256(SIMULATION_ACCOUNTS));
    }

    function _getSimulationAccount(uint256 index) internal returns (address) {
        string memory accountName = string(bytes.concat("SIMULATION_ACC_", bytes(Strings.toString(index))));
        return makeAddr(accountName);
    }

    function _submitStETHByRandomAccount() internal {
        address account = _getRandomSimulationAccount();
        uint256 submitAmount = _random.nextUint256(MIN_ST_ETH_SUBMIT_AMOUNT, MAX_ST_ETH_SUBMIT_AMOUNT);
        _lido.submitStETH(account, submitAmount);
        _totalSubmittedStETH += submitAmount;
    }

    function _submitWstETHByRandomAccount() internal {
        address account = _getRandomSimulationAccount();
        uint256 submitAmount = _random.nextUint256(MIN_WST_ETH_SUBMIT_AMOUNT, MAX_WST_ETH_SUBMIT_AMOUNT);
        _lido.submitWstETH(account, submitAmount);
        _totalSubmittedWstETH += submitAmount;
    }

    function _withdrawStETHByRandomAccount() internal {
        address account = _getRandomSimulationAccount();
        uint256 balance = _lido.stETH.balanceOf(account);
        if (balance > MIN_ST_ETH_WITHDRAW_AMOUNT) {
            // TODO: withdraw all tokens or create multiple requests
            uint256[] memory withdrawalAmounts = new uint256[](1);
            withdrawalAmounts[0] =
                _random.nextUint256(MIN_ST_ETH_WITHDRAW_AMOUNT, Math.min(balance, MAX_ST_ETH_WITHDRAW_AMOUNT));

            vm.startPrank(account);
            _lido.stETH.approve(address(_lido.withdrawalQueue), withdrawalAmounts[0]);
            uint256[] memory requestIds = _lido.withdrawalQueue.requestWithdrawals(withdrawalAmounts, account);
            vm.stopPrank();

            _totalWithdrawnStETH += withdrawalAmounts[0];
            console.log(
                "Account %s withdrawn %s stETH. Request id: %s",
                account,
                withdrawalAmounts[0].formatEther(),
                requestIds[0]
            );
        }
    }

    function _withdrawWstETHByRandomAccount() internal {
        address account = _getRandomSimulationAccount();
        uint256 balance = _lido.wstETH.balanceOf(account);
        if (balance > MIN_WST_ETH_WITHDRAW_AMOUNT) {
            // TODO: withdraw all tokens or create multiple requests
            uint256[] memory withdrawalAmounts = new uint256[](1);
            withdrawalAmounts[0] =
                _random.nextUint256(MIN_WST_ETH_WITHDRAW_AMOUNT, Math.min(balance, MAX_WST_ETH_WITHDRAW_AMOUNT));

            vm.startPrank(account);
            _lido.wstETH.approve(address(_lido.withdrawalQueue), withdrawalAmounts[0]);
            uint256[] memory requestIds = _lido.withdrawalQueue.requestWithdrawalsWstETH(withdrawalAmounts, account);
            vm.stopPrank();

            _totalWithdrawnWstETH += withdrawalAmounts[0];
            console.log(
                "Account %s withdrawn %s wstETH. Request id: %s",
                account,
                withdrawalAmounts[0].formatEther(),
                requestIds[0]
            );
        }
    }

    function _lockStETHInSignallingEscrowByRandomAccount() internal {
        for (uint256 i = 0; i < SIMULATION_ACCOUNTS; ++i) {
            address account = _getSimulationAccount(i);
            uint256 balance = _lido.stETH.balanceOf(account);
            if (balance > MIN_ST_ETH_SUBMIT_AMOUNT) {
                _lockStETH(account, balance);
                _totalLockedStETH += balance;
                break;
            }
        }
    }

    function _lockWtETHInSignallingEscrowByRandomAccount() internal {
        for (uint256 i = 0; i < SIMULATION_ACCOUNTS; ++i) {
            address account = _getSimulationAccount(i);
            uint256 balance = _lido.wstETH.balanceOf(account);
            if (balance > MIN_WST_ETH_SUBMIT_AMOUNT) {
                _lockWstETH(account, balance);
                _totalLockedWstETH += balance;
                break;
            }
        }
    }

    function _lockUnstETHByRandomAccount() internal {
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

                return;
            }
        }
    }

    function _claimUnstETHByRandomAccount() internal {
        uint256 maxRequestsToClaim = _random.nextUint256(1, 64);
        Uint256ArrayBuilder.Context memory requestsArrayBuilder = Uint256ArrayBuilder.create(maxRequestsToClaim);

        for (uint256 i = 0; i < SIMULATION_ACCOUNTS; ++i) {
            address account = _getSimulationAccount(i);
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
        uint256[] memory requestIds = _lido.withdrawalQueue.getWithdrawalRequests(address(_lido.withdrawalQueue));

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
    }

    function _getRandomProbability() internal returns (PercentD16) {
        return PercentsD16.from(_random.nextUint256(HUNDRED_PERCENT_D16));
    }
}
