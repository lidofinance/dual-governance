// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGRegressionTestSetup, PercentsD16} from "../utils/integration-tests.sol";
import {ISealable} from "../utils/interfaces/ISealable.sol";

contract ResealManagerRegressionTest is DGRegressionTestSetup {
    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _loadOrDeployDGSetup();
        _setupStETHBalance(_VETOER, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
    }

    function testFork_Reseal_HappyPath() external {
        ISealable pausedSealable;
        address[] memory sealableWithdrawalBlockers = _getSealableWithdrawalBlockers();
        _step("1. Validate that sealable withdrawal blockers not empty");
        {
            assertTrue(sealableWithdrawalBlockers.length > 0);
        }

        _step("2. Pause first sealable withdrawal blocker manually for some time");
        {
            pausedSealable = ISealable(sealableWithdrawalBlockers[0]);
            if (!pausedSealable.isPaused()) {
                vm.startPrank(address(_dgDeployedContracts.resealManager));
                pausedSealable.pauseFor(1 hours);
                vm.stopPrank();
                assertTrue(pausedSealable.isPaused());
                assertEq(pausedSealable.getResumeSinceTimestamp(), block.timestamp + 1 hours);
            }
        }

        _step("3. VetoSignalling state is entered");
        {
            _assertNormalState();
            _lockStETH(_VETOER, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1));
            _activateNextState();
            _assertVetoSignalingState();
        }

        _step("4. ResealCommittee reseals sealable");
        {
            _resealSealable(address(pausedSealable));
        }

        _step("5. Sealable is paused infinitely");
        {
            assertTrue(pausedSealable.isPaused());
            assertEq(pausedSealable.getResumeSinceTimestamp(), pausedSealable.PAUSE_INFINITELY());
        }
    }
}
