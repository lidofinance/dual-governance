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

enum SimulationActionType {
    SubmitStETH,
    SubmitWstETH,
    WithdrawStETH,
    WithdrawWstETH,
    LockStETH,
    // MarkUnstETHFinalized,
    LockWstETH
}
// LockUnstETH,
// UnlockStETH,
// UnlockWstETH,
// UnlockUnstETH,
// DirectStETHTransfer
// DirectWtETHTransfer
// DirectUntETHTransfer

library SimulationActionsSet {
    struct Context {
        bool[] flags;
    }

    function create() internal pure returns (Context memory res) {
        res.flags = new bool[](uint256(uint8(type(SimulationActionType).max)) + 1);
    }

    function add(Context memory self, SimulationActionType actionType) internal pure {
        self.flags[uint8(actionType)] = true;
    }

    function has(Context memory self, SimulationActionType actionType) internal pure returns (bool) {
        return self.flags[uint8(actionType)];
    }
}

// Set value of the below variable to false if the simulation test should be run.
// Note: simulation test may take significant time to pass
bool constant SKIP_SIMULATION_TEST = true;

uint256 constant MIN_ST_ETH_WITHDRAW_AMOUNT = 1000 wei;
uint256 constant MAX_ST_ETH_WITHDRAW_AMOUNT = 1000 ether;

uint256 constant MIN_WST_ETH_WITHDRAW_AMOUNT = 1000 wei;
uint256 constant MAX_WST_ETH_WITHDRAW_AMOUNT = 700 ether;

uint256 constant SLOT_DURATION = 12 seconds;
uint256 constant SIMULATION_ACCOUNTS = 1024;
uint256 constant SIMULATION_DURATION = 90 days;

uint256 constant MIN_ST_ETH_SUBMIT_AMOUNT = 0.1 ether;
uint256 constant MAX_ST_ETH_SUBMIT_AMOUNT = 750 ether;

uint256 constant MIN_WST_ETH_SUBMIT_AMOUNT = 0.1 ether;
uint256 constant MAX_WST_ETH_SUBMIT_AMOUNT = 500 ether;

uint256 constant ORACLE_REPORT_FREQUENCY = 24 hours;
uint256 constant WITHDRAWALS_FINALIZATION_FREQUENCY = 3 * 24 hours;

contract EscrowSolvencyTest is DGRegressionTestSetup {
    using Random for Random.Context;
    using LidoUtils for LidoUtils.Context;
    using SimulationActionsSet for SimulationActionsSet.Context;

    PercentD16 immutable LOCK_ST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(1_50);
    PercentD16 immutable LOCK_WST_ETH_PROBABILITY = PercentsD16.fromBasisPoints(1_00);

    PercentD16 immutable SUBMIT_STETH_PROBABILITY = PercentsD16.fromBasisPoints(2_50);
    PercentD16 immutable SUBMIT_WSTETH_PROBABILITY = PercentsD16.fromBasisPoints(2_00);

    PercentD16 immutable WITHDRAW_STETH_PROBABILITY = PercentsD16.fromBasisPoints(75);
    PercentD16 immutable WITHDRAW_WSTETH_PROBABILITY = PercentsD16.fromBasisPoints(50);

    uint256 internal _totalLockedStETH = 0;
    uint256 internal _totalLockedWstETH = 0;
    uint256 internal _totalSubmittedStETH = 0;
    uint256 internal _totalSubmittedWstETH = 0;
    uint256 internal _totalWithdrawnStETH = 0;
    uint256 internal _totalWithdrawnWstETH = 0;

    Random.Context internal _random;
    mapping(SimulationActionType actionType => uint256 emittedCount) internal _actionsCounters;

    uint256 internal _lastOracleReportTimestamp;
    uint256 internal _lastWithdrawalsFinalizationTimestamp;

    function setUp() external {
        _loadOrDeployDGSetup();
        _random = Random.create(block.timestamp);
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
        // TODO: Add env flag to run this test, by default should not be run
        if (SKIP_SIMULATION_TEST) {
            vm.skip(true);
            return;
        }
        uint256 simulationEndTimestamp = block.timestamp + SIMULATION_DURATION;
        DGState currentDGState = _dgDeployedContracts.dualGovernance.getPersistedState();

        console.log("Initial share rate: %d", _lido.stETH.getPooledEthByShares(10 ** 18));
        console.log(
            "before simulation block number: %d, before simulation timestamp: %d", block.number, block.timestamp
        );
        console.log("Initial DG state: %s", _getDGStateName(currentDGState));

        while (block.timestamp < simulationEndTimestamp) {
            SimulationActionsSet.Context memory actions = _getRandomUniqueActionsSet();

            if (actions.has(SimulationActionType.SubmitStETH)) {
                _submitStETHByRandomAccount();
            }

            if (actions.has(SimulationActionType.SubmitWstETH)) {
                _submitWstETHByRandomAccount();
            }

            if (actions.has(SimulationActionType.WithdrawStETH)) {
                _withdrawStETHByRandomAccount();
            }

            if (actions.has(SimulationActionType.WithdrawWstETH)) {
                _withdrawWstETHByRandomAccount();
            }

            if (actions.has(SimulationActionType.LockStETH)) {
                _lockStETHInSignallingEscrowByRandomAccount();
            }

            if (actions.has(SimulationActionType.LockWstETH)) {
                _lockWtETHInSignallingEscrowByRandomAccount();
            }

            _mineBlock();

            if (_lastOracleReportTimestamp + ORACLE_REPORT_FREQUENCY < block.timestamp) {
                _lastOracleReportTimestamp = block.timestamp;
                _lido.simulateRebase(PercentsD16.fromFraction({numerator: 1_000_000_001, denominator: 1_000_000_000}));
            }

            if (_lastWithdrawalsFinalizationTimestamp + WITHDRAWALS_FINALIZATION_FREQUENCY < block.timestamp) {
                _lastWithdrawalsFinalizationTimestamp = block.timestamp;
                _lido.finalizeWithdrawalQueue();
            }

            DGState effectiveDGState = _dgDeployedContracts.dualGovernance.getEffectiveState();
            if (currentDGState != effectiveDGState) {
                console.log(
                    "DG State changed from %s to %s", _getDGStateName(currentDGState), _getDGStateName(effectiveDGState)
                );
                currentDGState = effectiveDGState;
                _activateNextState();
            }

            // TODO: implement flow to handle ongoing rage quit
            // if (currentDGState == DGState.RageQuit) {
            //     console.log("Rage Quit State Entered! Aborting...");
            //     break;
            // }
        }
        console.log("after simulation block number: %d, after simulation timestamp: %d", block.number, block.timestamp);
        console.log("stETH Total Supply: %d", _lido.stETH.totalSupply());
        console.log("Final share rate: %d", _lido.stETH.getPooledEthByShares(10 ** 18));

        console.log("Actions Count:");
        console.log(
            "  - Submit stETH count: %d, total submitted amount: %d",
            _actionsCounters[SimulationActionType.SubmitStETH],
            _totalSubmittedStETH / 10 ** 18
        );
        console.log(
            "  - Submit wstETH count: %d, total submitted amount: %d",
            _actionsCounters[SimulationActionType.SubmitWstETH],
            _totalSubmittedWstETH / 10 ** 18
        );
        console.log(
            "  - Withdraw stETH count: %d, total withdrawn amount: %d",
            _actionsCounters[SimulationActionType.WithdrawStETH],
            _totalWithdrawnStETH / 10 ** 18
        );
        console.log(
            "  - Withdraw wstETH count: %d, total withdrawn amount: %d",
            _actionsCounters[SimulationActionType.WithdrawWstETH],
            _totalWithdrawnWstETH / 10 ** 18
        );
        console.log(
            "  - Lock stETH count: %d, total locked stETH: %d",
            _actionsCounters[SimulationActionType.LockStETH],
            _totalLockedStETH / 10 ** 18
        );
        console.log(
            "  - Lock wstETH count: %d, total locked wstETH: %d",
            _actionsCounters[SimulationActionType.LockWstETH],
            _totalLockedWstETH / 10 ** 18
        );

        ISignallingEscrow signallingEscrow =
            ISignallingEscrow(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow());
        console.log("Signalling Escrow Stats:");
        console.log("  - Rage Quit Support: %d", signallingEscrow.getRageQuitSupport().toUint256());
        console.log("  - stETH Balance: %d", _lido.stETH.balanceOf(address(signallingEscrow)));

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
        for (uint256 i = 0; i < SIMULATION_ACCOUNTS; ++i) {
            address account = _getSimulationAccount(i);
            uint256 balance = _lido.stETH.balanceOf(account);
            if (balance > MIN_ST_ETH_WITHDRAW_AMOUNT) {
                // TODO: withdraw all tokens or create multiple requests
                uint256[] memory withdrawalAmounts = new uint256[](1);
                withdrawalAmounts[0] =
                    _random.nextUint256(MIN_ST_ETH_WITHDRAW_AMOUNT, Math.min(balance, MAX_ST_ETH_WITHDRAW_AMOUNT));

                vm.startPrank(account);
                _lido.stETH.approve(address(_lido.withdrawalQueue), withdrawalAmounts[0]);
                _lido.withdrawalQueue.requestWithdrawals(withdrawalAmounts, account);
                vm.stopPrank();

                _totalWithdrawnStETH += withdrawalAmounts[0];
                break;
            }
        }
    }

    function _withdrawWstETHByRandomAccount() internal {
        for (uint256 i = 0; i < SIMULATION_ACCOUNTS; ++i) {
            address account = _getSimulationAccount(i);
            uint256 balance = _lido.wstETH.balanceOf(account);
            if (balance > MIN_WST_ETH_WITHDRAW_AMOUNT) {
                // TODO: withdraw all tokens or create multiple requests
                uint256[] memory withdrawalAmounts = new uint256[](1);
                withdrawalAmounts[0] =
                    _random.nextUint256(MIN_WST_ETH_WITHDRAW_AMOUNT, Math.min(balance, MAX_WST_ETH_WITHDRAW_AMOUNT));

                vm.startPrank(account);
                _lido.wstETH.approve(address(_lido.withdrawalQueue), withdrawalAmounts[0]);
                _lido.withdrawalQueue.requestWithdrawalsWstETH(withdrawalAmounts, account);
                vm.stopPrank();

                _totalWithdrawnWstETH += withdrawalAmounts[0];
                break;
            }
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
    }

    function _getRandomProbability() internal returns (PercentD16) {
        return PercentsD16.from(_random.nextUint256(HUNDRED_PERCENT_D16));
    }
}
