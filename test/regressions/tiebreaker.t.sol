// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGRegressionTestSetup, PercentsD16, ExternalCall} from "../utils/integration-tests.sol";

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
        address[] memory members;

        ITiebreaker.TiebreakerDetails memory details = _dgDeployedContracts.dualGovernance.getTiebreakerDetails();

        // Tiebreak activation
        _assertNormalState();
        _lockStETH(_VETOER, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(50));
        _wait(_getVetoSignallingMaxDuration().plusSeconds(1));

        _activateNextState();
        _assertRageQuitState();

        _wait(details.tiebreakerActivationTimeout);
        _activateNextState();

        ExternalCall[] memory proposalCalls = _getMockTargetRegularStaffCalls(2);
        uint256 proposalIdToExecute = _submitProposalByAdminProposer(proposalCalls, "Proposal for execution");

        // Tiebreaker subcommittee 0
        TiebreakerCoreCommittee coreTiebreaker = TiebreakerCoreCommittee(details.tiebreakerCommittee);

        address[] memory subTiebreakers = coreTiebreaker.getMembers();

        uint256 quorum;
        uint256 support;
        bool isExecuted;
        for (uint256 i = 0; i < coreTiebreaker.getQuorum(); ++i) {
            TiebreakerSubCommittee subTiebreaker = TiebreakerSubCommittee(subTiebreakers[i]);

            _executeScheduleProposalBySubCommittee(TiebreakerSubCommittee(subTiebreakers[i]), proposalIdToExecute);

            (support, quorum, /* quorumAt */, isExecuted) = coreTiebreaker.getScheduleProposalState(proposalIdToExecute);

            assertFalse(isExecuted);
            assertEq(support, i + 1);
        }
        assertEq(support, quorum);

        // Waiting for submit delay pass
        _wait(coreTiebreaker.getTimelockDuration());

        coreTiebreaker.executeScheduleProposal(proposalIdToExecute);

        _assertProposalScheduled(proposalIdToExecute);

        _wait(_getAfterScheduleDelay());

        _executeProposal(proposalIdToExecute);
        _assertProposalExecuted(proposalIdToExecute);
        _assertTargetMockCalls(_getAdminExecutor(), proposalCalls);
    }

    // function testFork_ResumeWithdrawals() external {
    //     uint256 quorum;
    //     uint256 support;
    //     bool isExecuted;

    //     address[] memory members;

    //     ITiebreaker.TiebreakerDetails memory details = _dgDeployedContracts.dualGovernance.getTiebreakerDetails();

    //     vm.prank(address(_lido.agent));
    //     _lido.withdrawalQueue.grantRole(
    //         0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d, address(_lido.agent)
    //     );
    //     vm.prank(address(_lido.agent));
    //     _lido.withdrawalQueue.pauseFor(type(uint256).max);
    //     assertEq(_lido.withdrawalQueue.isPaused(), true);

    //     // Tiebreak activation
    //     _assertNormalState();
    //     _lockStETH(_VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT());
    //     _lockStETH(_VETOER, 1 gwei);
    //     _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
    //     _activateNextState();
    //     _assertRageQuitState();
    //     _wait(_dualGovernance.getTiebreakerDetails().tiebreakerActivationTimeout);
    //     _activateNextState();

    //     // Tiebreaker subcommittee 0
    //     members = _tiebreakerSubCommittees[0].getMembers();
    //     for (uint256 i = 0; i < _tiebreakerSubCommittees[0].getQuorum() - 1; i++) {
    //         vm.prank(members[i]);
    //         _tiebreakerSubCommittees[0].sealableResume(address(_lido.withdrawalQueue));
    //         (support, quorum,, isExecuted) =
    //             _tiebreakerSubCommittees[0].getSealableResumeState(address(_lido.withdrawalQueue));
    //         assertTrue(support < quorum);
    //         assertFalse(isExecuted);
    //     }

    //     vm.prank(members[members.length - 1]);
    //     _tiebreakerSubCommittees[0].sealableResume(address(_lido.withdrawalQueue));
    //     (support, quorum,, isExecuted) =
    //         _tiebreakerSubCommittees[0].getSealableResumeState(address(_lido.withdrawalQueue));
    //     assertEq(support, quorum);
    //     assertFalse(isExecuted);

    //     _tiebreakerSubCommittees[0].executeSealableResume(address(_lido.withdrawalQueue));
    //     (support, quorum,, isExecuted) = _tiebreakerCoreCommittee.getSealableResumeState(
    //         address(_lido.withdrawalQueue),
    //         _tiebreakerCoreCommittee.getSealableResumeNonce(address(_lido.withdrawalQueue))
    //     );
    //     assertTrue(support < quorum);

    //     // Tiebreaker subcommittee 1
    //     members = _tiebreakerSubCommittees[1].getMembers();
    //     for (uint256 i = 0; i < _tiebreakerSubCommittees[1].getQuorum() - 1; i++) {
    //         vm.prank(members[i]);
    //         _tiebreakerSubCommittees[1].sealableResume(address(_lido.withdrawalQueue));
    //         (support, quorum,, isExecuted) =
    //             _tiebreakerSubCommittees[1].getSealableResumeState(address(_lido.withdrawalQueue));
    //         assertTrue(support < quorum);
    //         assertEq(isExecuted, false);
    //     }

    //     vm.prank(members[members.length - 1]);
    //     _tiebreakerSubCommittees[1].sealableResume(address(_lido.withdrawalQueue));
    //     (support, quorum,, isExecuted) =
    //         _tiebreakerSubCommittees[1].getSealableResumeState(address(_lido.withdrawalQueue));
    //     assertEq(support, quorum);
    //     assertFalse(isExecuted);

    //     _tiebreakerSubCommittees[1].executeSealableResume(address(_lido.withdrawalQueue));
    //     (support, quorum,, isExecuted) = _tiebreakerCoreCommittee.getSealableResumeState(
    //         address(_lido.withdrawalQueue),
    //         _tiebreakerCoreCommittee.getSealableResumeNonce(address(_lido.withdrawalQueue))
    //     );
    //     assertEq(support, quorum);

    //     // Waiting for submit delay pass
    //     _wait(_tiebreakerCoreCommittee.getTimelockDuration());

    //     _tiebreakerCoreCommittee.executeSealableResume(address(_lido.withdrawalQueue));

    //     assertEq(_lido.withdrawalQueue.isPaused(), false);
    // }

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
}
