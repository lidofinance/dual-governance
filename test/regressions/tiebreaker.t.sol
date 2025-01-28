// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGRegressionTestSetup, PercentsD16, ExternalCall} from "../utils/integration-tests.sol";

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
    }

    function testFork_ProposalApproval_TiebreakerActivationTimeout() external {
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

                _executeScheduleProposalBySubCommittee(TiebreakerSubCommittee(subTiebreakers[i]), proposalIdToExecute);

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

    function testFork_ResumeWithdrawals() external {
        ITiebreaker.TiebreakerDetails memory details = _dgDeployedContracts.dualGovernance.getTiebreakerDetails();

        address[] memory sealableWithdrawalBlockers = _getSealableWithdrawalBlockers();
        _step("1. Validate that sealable withdrawal blockers not empty");
        {
            assertTrue(sealableWithdrawalBlockers.length > 0);
        }

        _step("2. Pause sealable withdrawal blockers manually");

        ISealable pausedSealable = ISealable(sealableWithdrawalBlockers[0]);
        if (!pausedSealable.isPaused()) {
            vm.startPrank(address(_dgDeployedContracts.resealManager));
            pausedSealable.pauseFor(pausedSealable.PAUSE_INFINITELY());
            vm.stopPrank();
            assertTrue(pausedSealable.isPaused());
        }

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
        {
            uint256 quorum;
            uint256 support;
            bool isExecuted;
            TiebreakerCoreCommittee coreTiebreaker = TiebreakerCoreCommittee(details.tiebreakerCommittee);
            address[] memory subTiebreakers = coreTiebreaker.getMembers();

            for (uint256 i = 0; i < coreTiebreaker.getQuorum(); ++i) {
                TiebreakerSubCommittee subTiebreaker = TiebreakerSubCommittee(subTiebreakers[i]);

                _executeResumeProposalBySubCommittee(TiebreakerSubCommittee(subTiebreakers[i]), address(pausedSealable));

                (support, quorum, /* quorumAt */, isExecuted) = coreTiebreaker.getSealableResumeState(
                    address(pausedSealable), coreTiebreaker.getSealableResumeNonce(address(pausedSealable))
                );

                assertFalse(isExecuted);
                assertEq(support, i + 1);
            }
            assertEq(support, quorum);

            // Waiting for submit delay pass
            _wait(coreTiebreaker.getTimelockDuration());

            coreTiebreaker.executeSealableResume(address(pausedSealable));
        }

        _step("5. Sealable is resumed and rage quit may be finalized");
        {
            assertFalse(pausedSealable.isPaused());
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
            (uint256 support, uint256 quorum, /* quorumAt */, bool isExecuted) =
                subTiebreaker.getScheduleProposalState(proposalIdToExecute);
            assertEq(support, j + 1);
            assertFalse(isExecuted);
        }
        _wait(subTiebreaker.getTimelockDuration());
        subTiebreaker.executeScheduleProposal(proposalIdToExecute);

        (uint256 support, uint256 quorum, /* quorumAt */, bool isExecuted) =
            subTiebreaker.getScheduleProposalState(proposalIdToExecute);
        assertEq(support, quorum);
        assertTrue(isExecuted);
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
            (uint256 support, uint256 quorum, /* quorumAt */, bool isExecuted) =
                subTiebreaker.getSealableResumeState(sealableToUnpause);
            assertEq(support, j + 1);
            assertFalse(isExecuted);
        }
        _wait(subTiebreaker.getTimelockDuration());
        subTiebreaker.executeSealableResume(sealableToUnpause);

        (uint256 support, uint256 quorum, /* quorumAt */, bool isExecuted) =
            subTiebreaker.getSealableResumeState(sealableToUnpause);
        assertEq(support, quorum);
        assertTrue(isExecuted);
    }
}
