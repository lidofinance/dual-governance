// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {PercentD16} from "contracts/types/PercentD16.sol";

import {Random} from "../utils/random.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISignallingEscrow, UnstETHRecordStatus} from "contracts/interfaces/ISignallingEscrow.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {DGRegressionTestSetup, ExternalCall, MAINNET_CHAIN_ID} from "../utils/integration-tests.sol";
import {DecimalsFormatting} from "../utils/formatting.sol";

struct VetoersFile {
    address[] addresses;
}

uint256 constant EPSILON = 2 wei;

uint256 constant SLOT_DURATION = 1 hours;

uint256 constant MIN_LOCKABLE_STETH_AMOUNT = 10;
uint256 constant MIN_LOCKABLE_WSTETH_AMOUNT = 10;

uint256 constant MAX_LOCKABLE_STETH_AMOUNT = 100_000 ether;
uint256 constant MAX_LOCKABLE_WSTETH_AMOUNT = 100_000 ether;

contract VetoSignallingDeEscalation is DGRegressionTestSetup {
    using Random for Random.Context;
    using DecimalsFormatting for uint256;
    using DecimalsFormatting for PercentD16;

    Random.Context internal _random;
    address[] internal _stETHVetoers;
    address[] internal _wstETHVetoers;
    uint256[] internal _unfinalizedUnstETHIds;
    uint256 internal _nextUnstETHIdIndex;

    mapping(address vetoer => bool) internal _vetoersLockedStETH;
    mapping(address vetoer => bool) internal _vetoersLockedWstETH;

    function setUp() external {
        _loadOrDeployDGSetup();
        _random = Random.create(vm.unixTime());
        if (block.chainid != MAINNET_CHAIN_ID) {
            vm.skip(true, "Test supports can be run only on mainnet network");
        }
    }

    function testFork_VetoSignallingDeEscalation_HappyPath() external {
        _step("1. Loading stETH & wstETH holders");
        {
            _stETHVetoers =
                _shuffleVetoers(_loadVetoers("./test/regressions/complete-rage-quit-files/steth_vetoers.json"));
            _wstETHVetoers =
                _shuffleVetoers(_loadVetoers("./test/regressions/complete-rage-quit-files/wsteth_vetoers.json"));

            console.log("Loaded %d stETH holders and %d wstETH holders", _stETHVetoers.length, _wstETHVetoers.length);
        }

        _step("2. Retrieve all unfinalized unstETH NFTs ids");
        {
            uint256 lastRequestId = _lido.withdrawalQueue.getLastRequestId();
            uint256 lastFinalizedRequestId = _lido.withdrawalQueue.getLastFinalizedRequestId();

            if (lastRequestId > lastFinalizedRequestId) {
                uint256[] memory shuffledRequestIds =
                    _random.nextPermutation(lastRequestId - lastFinalizedRequestId, lastFinalizedRequestId + 1);

                IWithdrawalQueue.WithdrawalRequestStatus[] memory requestStatuses =
                    _lido.withdrawalQueue.getWithdrawalStatus(shuffledRequestIds);

                for (uint256 i = 0; i < shuffledRequestIds.length; ++i) {
                    if (
                        requestStatuses[i].owner == address(_getVetoSignallingEscrow())
                            || requestStatuses[i].owner == address(_getRageQuitEscrow())
                    ) {
                        continue;
                    }
                    _unfinalizedUnstETHIds.push(shuffledRequestIds[i]);
                }
            }

            console.log("Collected %d unfinalized unstETH ids", lastRequestId - lastFinalizedRequestId);
        }

        uint256 controversialProposalId;
        ExternalCall[] memory veryControversialProposalCalls = _getMockTargetRegularStaffCalls();
        _step("3. Very controversial proposal was submitted by the DAO");
        {
            controversialProposalId = _submitProposalByAdminProposer(veryControversialProposalCalls);
            _assertProposalSubmitted(controversialProposalId);
        }

        uint256 lockOperationsCount = 0;
        uint256 escrowStETHBalanceBefore = _lido.stETH.balanceOf(address(_getVetoSignallingEscrow()));
        uint256 escrowUnstETHBalanceBefore = _lido.withdrawalQueue.balanceOf(address(_getVetoSignallingEscrow()));

        _step("4. stETH, wstETH, unstETH holders lock their funds in the VetoSignalling escrow");
        {
            uint256 vetoSignallingAccumulationEndTime =
                block.timestamp + _getVetoSignallingMaxDuration().dividedBy(2).toSeconds();

            while (block.timestamp < vetoSignallingAccumulationEndTime) {
                // 0 - lock stETH
                // 1 - lock wstETH
                // 2 - lock unstETH
                uint256 randomOperation = _random.nextUint256(3);

                if (randomOperation == 0) {
                    (address randomStETHVetoer, uint256 balance) = _getNextStETHVetoer();
                    if (randomStETHVetoer != address(0) && balance >= MIN_LOCKABLE_STETH_AMOUNT) {
                        uint256 lockAmount = Math.min(balance, _random.nextUint256(MAX_LOCKABLE_STETH_AMOUNT));

                        _lockStETH(randomStETHVetoer, lockAmount);

                        _vetoersLockedStETH[randomStETHVetoer] = true;
                    }
                } else if (randomOperation == 1) {
                    (address randomWstETHVetoer, uint256 balance) = _getNextWstETHVetoer();
                    if (randomWstETHVetoer != address(0) && balance >= MIN_LOCKABLE_WSTETH_AMOUNT) {
                        uint256 lockAmount = Math.min(balance, _random.nextUint256(MAX_LOCKABLE_WSTETH_AMOUNT));

                        _lockWstETH(randomWstETHVetoer, lockAmount);

                        _vetoersLockedWstETH[randomWstETHVetoer] = true;
                    }
                } else if (randomOperation == 2) {
                    uint256 randomUnfinalizedUnstETHId = _getNextUnstETHId();
                    if (randomUnfinalizedUnstETHId > 0) {
                        uint256[] memory unstETHIds = new uint256[](1);
                        unstETHIds[0] = randomUnfinalizedUnstETHId;

                        _lockUnstETH(_lido.withdrawalQueue.ownerOf(randomUnfinalizedUnstETHId), unstETHIds);
                    }
                } else {
                    revert("invalid operation");
                }

                _mineBlock();
                lockOperationsCount += 1;
            }

            console.log("Total lock operations :%s", lockOperationsCount);
            console.log(
                "Locked stETH amount :%s",
                (_lido.stETH.balanceOf(address(_getVetoSignallingEscrow())) - escrowStETHBalanceBefore).formatEther()
            );
            console.log(
                "Locked unstETH NFTs count :%s",
                _lido.withdrawalQueue.balanceOf(address(_getVetoSignallingEscrow())) - escrowUnstETHBalanceBefore
            );
            console.log("RageQuit support :%s", _getVetoSignallingEscrow().getRageQuitSupport().format());
        }

        _step("5. DAO decides cancel controversial proposal");
        {
            _cancelAllPendingProposalsByProposalsCanceller();
            _assertProposalCancelled(controversialProposalId);
            _assertCanSchedule(controversialProposalId, false);
        }

        _step("6. Vetoers withdraw their funds from the Escrow");
        {
            _wait(_getMinAssetsLockDuration());

            for (uint256 i = 0; i < _stETHVetoers.length; ++i) {
                if (!_vetoersLockedStETH[_stETHVetoers[i]]) {
                    continue;
                }
                uint256 lockedShares =
                    _getVetoSignallingEscrow().getVetoerDetails(_stETHVetoers[i]).stETHLockedShares.toUint256();
                if (lockedShares == 0) {
                    continue;
                }
                _unlockWstETH(_stETHVetoers[i]);
            }

            for (uint256 i = 0; i < _wstETHVetoers.length; ++i) {
                if (!_vetoersLockedWstETH[_wstETHVetoers[i]]) {
                    continue;
                }
                uint256 lockedShares =
                    _getVetoSignallingEscrow().getVetoerDetails(_wstETHVetoers[i]).stETHLockedShares.toUint256();
                if (lockedShares == 0) {
                    continue;
                }
                _unlockStETH(_wstETHVetoers[i]);
            }

            if (_nextUnstETHIdIndex > 0) {
                uint256[] memory lockedUnstETHIds = new uint256[](_nextUnstETHIdIndex);

                for (uint256 i = 0; i < lockedUnstETHIds.length; ++i) {
                    lockedUnstETHIds[i] = _unfinalizedUnstETHIds[i];
                }

                ISignallingEscrow.LockedUnstETHDetails[] memory unstETHDetails =
                    _getVetoSignallingEscrow().getLockedUnstETHDetails(lockedUnstETHIds);

                for (uint256 i = 0; i < unstETHDetails.length; ++i) {
                    if (unstETHDetails[i].status == UnstETHRecordStatus.NotLocked) {
                        continue;
                    }
                    uint256[] memory unstETHIds = new uint256[](1);
                    unstETHIds[0] = unstETHDetails[i].id;
                    _unlockUnstETH(unstETHDetails[i].lockedBy, unstETHIds);
                }
            }

            assertApproxEqAbs(
                escrowStETHBalanceBefore,
                _lido.stETH.balanceOf(address(_getVetoSignallingEscrow())),
                EPSILON * lockOperationsCount
            );
            assertEq(_lido.withdrawalQueue.balanceOf(address(_getVetoSignallingEscrow())), escrowUnstETHBalanceBefore);

            console.log(
                "Escrow stETH balance: %s", _lido.stETH.balanceOf(address(_getVetoSignallingEscrow())).formatEther()
            );
        }

        _step(
            "7. After vetoers unlocked tokens system enters VetoSignallingDeactivation -> VetoCooldown -> Normal state"
        );
        {
            _assertVetoSignallingDeactivationState();
            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoCooldownState();

            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();
            _assertNormalState();
        }
    }

    function _getNextStETHVetoer() internal view returns (address, uint256) {
        for (uint256 i = 0; i < _stETHVetoers.length; ++i) {
            uint256 balance = _lido.stETH.balanceOf(_stETHVetoers[i]);
            if (balance >= MIN_LOCKABLE_STETH_AMOUNT) {
                return (_stETHVetoers[i], balance);
            }
        }
        return (address(0), 0);
    }

    function _getNextWstETHVetoer() internal view returns (address, uint256) {
        for (uint256 i = 0; i < _wstETHVetoers.length; ++i) {
            uint256 balance = _lido.wstETH.balanceOf(_wstETHVetoers[i]);
            if (balance >= MIN_LOCKABLE_WSTETH_AMOUNT) {
                return (_wstETHVetoers[i], balance);
            }
        }
        return (address(0), 0);
    }

    function _getNextUnstETHId() internal returns (uint256 unstETHId) {
        if (_nextUnstETHIdIndex < _unfinalizedUnstETHIds.length) {
            unstETHId = _unfinalizedUnstETHIds[_nextUnstETHIdIndex++];
        }
    }

    function _shuffleVetoers(address[] memory vetoers) internal returns (address[] memory shuffledVetoers) {
        uint256[] memory randomIndicesPermutation = _random.nextPermutation(vetoers.length);

        shuffledVetoers = new address[](vetoers.length);
        for (uint256 i = 0; i < randomIndicesPermutation.length; ++i) {
            shuffledVetoers[i] = vetoers[randomIndicesPermutation[i]];
        }
    }

    function _loadVetoers(string memory path) internal view returns (address[] memory) {
        string memory vetoersFileRaw = vm.readFile(path);
        bytes memory data = vm.parseJson(vetoersFileRaw);
        return abi.decode(data, (VetoersFile)).addresses;
    }

    function _mineBlock() internal {
        vm.warp(block.timestamp + SLOT_DURATION);
        vm.roll(block.number + 1);
    }
}
