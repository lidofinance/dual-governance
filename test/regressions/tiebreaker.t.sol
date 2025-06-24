// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {DGRegressionTestSetup, PercentsD16} from "../utils/integration-tests.sol";

import {ISealable} from "../utils/interfaces/ISealable.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";

import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

contract TiebreakerRegressionTest is DGRegressionTestSetup {
    address internal immutable _VETOER = makeAddr("VETOER");
    uint256 public constant PAUSE_INFINITELY = type(uint256).max;

    function setUp() external {
        _loadOrDeployDGSetup();
        _setupStETHBalance(_VETOER, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));

        if (vm.envOr(string("GRANT_REQUIRED_PERMISSIONS"), false)) {
            address resealManager = address(_dgDeployedContracts.resealManager);
            address[] memory sealableWithdrawalBlockers = _getSealableWithdrawalBlockers();

            for (uint256 i = 0; i < sealableWithdrawalBlockers.length; ++i) {
                ISealable sealable = ISealable(sealableWithdrawalBlockers[i]);
                vm.startPrank(address(_lido.agent));
                {
                    bytes32 pauseRole = sealable.PAUSE_ROLE();
                    if (!sealable.hasRole(pauseRole, resealManager)) {
                        sealable.grantRole(pauseRole, resealManager);
                        assertTrue(sealable.hasRole(pauseRole, resealManager));
                        console.log(
                            unicode"⚠️ %s: Role 'PAUSE_ROLE' was granted to the ResealManager", address(sealable)
                        );
                    }

                    bytes32 resumeRole = sealable.RESUME_ROLE();
                    if (!sealable.hasRole(resumeRole, resealManager)) {
                        sealable.grantRole(resumeRole, address(resealManager));
                        assertTrue(sealable.hasRole(resumeRole, resealManager));
                        console.log(
                            unicode"⚠️ %s: Role 'RESUME_ROLE' was granted to the ResealManager", address(sealable)
                        );
                    }
                }
                vm.stopPrank();
            }
        }
    }

    function testFork_ProposalApproval_ActivationTimeout() external {
        ITiebreaker.TiebreakerDetails memory details = _dgDeployedContracts.dualGovernance.getTiebreakerDetails();

        _step("1. Tiebreaker activation");
        {
            _assertNormalState();

            _lockStETH(_VETOER, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(50));
            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertRageQuitState();

            _wait(details.tiebreakerActivationTimeout);
            _activateNextState();
        }

        _step("2. Proposal is submitted by the DAO to execute by Tiebreaker");
        uint256 proposalIdToExecute;
        ExternalCall[] memory proposalCalls;
        {
            proposalCalls = _getMockTargetRegularStaffCalls(2);
            proposalIdToExecute = _submitProposalByAdminProposer(proposalCalls, "Proposal for execution");
        }

        _step("3. Tiebreaker votes to execute the proposal");
        {
            uint256 quorum;
            uint256 support;
            bool isExecuted;
            TiebreakerCoreCommittee coreTiebreaker = TiebreakerCoreCommittee(details.tiebreakerCommittee);
            address[] memory subTiebreakers = coreTiebreaker.getMembers();

            for (uint256 i = 0; i < coreTiebreaker.getQuorum(); ++i) {
                TiebreakerSubCommittee subTiebreaker = TiebreakerSubCommittee(subTiebreakers[i]);

                _executeScheduleProposalBySubCommittee(subTiebreaker, proposalIdToExecute);

                (support, quorum, /* quorumAt */, isExecuted) =
                    coreTiebreaker.getScheduleProposalState(proposalIdToExecute);

                assertFalse(isExecuted);
                assertEq(support, i + 1);
            }
            assertEq(support, quorum);

            // Waiting for submit delay pass
            _wait(coreTiebreaker.getTimelockDuration());

            coreTiebreaker.executeScheduleProposal(proposalIdToExecute);
        }

        _step("4. Proposal may be scheduled and executed now");
        {
            _assertProposalScheduled(proposalIdToExecute);

            _wait(_getAfterScheduleDelay());

            _executeProposal(proposalIdToExecute);
            _assertProposalExecuted(proposalIdToExecute);
            _assertTargetMockCalls(_getAdminExecutor(), proposalCalls);
        }
    }

    function testFork_ResumeSealable_RageQuit_HappyPath() external {
        ITiebreaker.TiebreakerDetails memory details = _dgDeployedContracts.dualGovernance.getTiebreakerDetails();

        address[] memory sealableWithdrawalBlockers = _getSealableWithdrawalBlockers();
        _step("1. Validate that sealable withdrawal blockers not empty");
        {
            assertTrue(sealableWithdrawalBlockers.length > 0);
        }

        _step("2. Pause sealables withdrawal blockers manually");
        _pauseSealables(sealableWithdrawalBlockers);

        // Tiebreak activation
        _step("3. Rage Quit state is entered");
        {
            _assertNormalState();
            _lockStETH(_VETOER, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1));
            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();
            _wait(_dgDeployedContracts.dualGovernance.getTiebreakerDetails().tiebreakerActivationTimeout);
            _activateNextState();
        }

        _step("4. Tiebreaker votes to resume paused sealable");
        _tiebreakerVoteForSealablesResume(details.tiebreakerCommittee, sealableWithdrawalBlockers);

        _step("5. Sealable is resumed and rage quit may be finalized");
        {
            for (uint256 sealableIndex = 0; sealableIndex < sealableWithdrawalBlockers.length; ++sealableIndex) {
                assertFalse(ISealable(sealableWithdrawalBlockers[sealableIndex]).isPaused());
            }
        }
    }

    function _pauseSealables(address[] memory sealableWithdrawalBlockers) internal {
        for (uint256 i = 0; i < sealableWithdrawalBlockers.length; ++i) {
            ISealable pausedSealable = ISealable(sealableWithdrawalBlockers[i]);
            if (!pausedSealable.isPaused()) {
                vm.startPrank(address(_dgDeployedContracts.resealManager));
                pausedSealable.pauseFor(pausedSealable.PAUSE_INFINITELY());
                vm.stopPrank();
                assertTrue(pausedSealable.isPaused());
            }
        }
    }

    function _tiebreakerVoteForSealablesResume(
        address tiebreakerCommittee,
        address[] memory sealableWithdrawalBlockers
    ) internal {
        TiebreakerCoreCommittee coreTiebreaker = TiebreakerCoreCommittee(tiebreakerCommittee);
        address[] memory subTiebreakers = coreTiebreaker.getMembers();

        for (uint256 sealableIndex = 0; sealableIndex < sealableWithdrawalBlockers.length; ++sealableIndex) {
            uint256 quorum;
            uint256 support;
            bool isExecuted;

            for (uint256 i = 0; i < coreTiebreaker.getQuorum(); ++i) {
                TiebreakerSubCommittee subTiebreaker = TiebreakerSubCommittee(subTiebreakers[i]);

                _executeResumeProposalBySubCommittee(subTiebreaker, sealableWithdrawalBlockers[sealableIndex]);

                (support, quorum, /* quorumAt */, isExecuted) = coreTiebreaker.getSealableResumeState(
                    sealableWithdrawalBlockers[sealableIndex],
                    coreTiebreaker.getSealableResumeNonce(sealableWithdrawalBlockers[0])
                );

                assertFalse(isExecuted);
                assertEq(support, i + 1);
            }
            assertEq(support, quorum);
        }

        // Waiting for submit delay pass
        _wait(coreTiebreaker.getTimelockDuration());

        for (uint256 sealableIndex = 0; sealableIndex < sealableWithdrawalBlockers.length; ++sealableIndex) {
            coreTiebreaker.executeSealableResume(sealableWithdrawalBlockers[sealableIndex]);
        }
    }

    function _executeScheduleProposalBySubCommittee(
        TiebreakerSubCommittee subTiebreaker,
        uint256 proposalIdToExecute
    ) internal {
        uint256 subTiebreakerQuorum = subTiebreaker.getQuorum();
        address[] memory subTiebreakerMembers = subTiebreaker.getMembers();

        for (uint256 j = 0; j < subTiebreakerQuorum; ++j) {
            vm.prank(subTiebreakerMembers[j]);
            subTiebreaker.scheduleProposal(proposalIdToExecute);
            (uint256 support, /* quorum */, /* quorumAt */, bool isExecuted) =
                subTiebreaker.getScheduleProposalState(proposalIdToExecute);
            assertEq(support, j + 1);
            assertFalse(isExecuted);
        }
        _wait(subTiebreaker.getTimelockDuration());
        subTiebreaker.executeScheduleProposal(proposalIdToExecute);

        (uint256 _support, uint256 quorum, /* quorumAt */, bool _isExecuted) =
            subTiebreaker.getScheduleProposalState(proposalIdToExecute);
        assertEq(_support, quorum);
        assertTrue(_isExecuted);
    }

    function _executeResumeProposalBySubCommittee(
        TiebreakerSubCommittee subTiebreaker,
        address sealableToUnpause
    ) internal {
        uint256 subTiebreakerQuorum = subTiebreaker.getQuorum();
        address[] memory subTiebreakerMembers = subTiebreaker.getMembers();

        for (uint256 j = 0; j < subTiebreakerQuorum; ++j) {
            vm.prank(subTiebreakerMembers[j]);
            subTiebreaker.sealableResume(sealableToUnpause);
            (uint256 support, /* quorum */, /* quorumAt */, bool isExecuted) =
                subTiebreaker.getSealableResumeState(sealableToUnpause);
            assertEq(support, j + 1);
            assertFalse(isExecuted);
        }
        _wait(subTiebreaker.getTimelockDuration());
        subTiebreaker.executeSealableResume(sealableToUnpause);

        (uint256 _support, uint256 quorum, /* quorumAt */, bool _isExecuted) =
            subTiebreaker.getSealableResumeState(sealableToUnpause);
        assertEq(_support, quorum);
        assertTrue(_isExecuted);
    }
}
