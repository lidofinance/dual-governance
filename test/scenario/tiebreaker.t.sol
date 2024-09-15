// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {ScenarioTestBlueprint, ExternalCall, ExternalCallHelpers} from "../utils/scenario-test-blueprint.sol";

contract TiebreakerScenarioTest is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");
    uint256 public constant PAUSE_INFINITELY = type(uint256).max;

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});
        _setupStETHBalance(
            _VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1_00)
        );
    }

    function test_proposal_approval() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        address[] memory members;

        // Tiebreak activation
        _assertNormalState();
        _lockStETH(_VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT());
        _lockStETH(_VETOER, 1 gwei);
        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        _activateNextState();
        _assertRageQuitState();
        _wait(_dualGovernance.getTiebreakerDetails().tiebreakerActivationTimeout);
        _activateNextState();

        ExternalCall[] memory proposalCalls = ExternalCallHelpers.create(address(0), new bytes(0));
        uint256 proposalIdToExecute = _submitProposal(_dualGovernance, "Proposal for execution", proposalCalls);

        // Tiebreaker subcommittee 0
        members = _tiebreakerSubCommittees[0].getMembers();
        for (uint256 i = 0; i < _tiebreakerSubCommittees[0].quorum() - 1; i++) {
            vm.prank(members[i]);
            _tiebreakerSubCommittees[0].scheduleProposal(proposalIdToExecute);
            (support, quorum,, isExecuted) = _tiebreakerSubCommittees[0].getScheduleProposalState(proposalIdToExecute);
            assertTrue(support < quorum);
            assertFalse(isExecuted);
        }

        vm.prank(members[members.length - 1]);
        _tiebreakerSubCommittees[0].scheduleProposal(proposalIdToExecute);
        (support, quorum,, isExecuted) = _tiebreakerSubCommittees[0].getScheduleProposalState(proposalIdToExecute);
        assertEq(support, quorum);
        assertFalse(isExecuted);

        _tiebreakerSubCommittees[0].executeScheduleProposal(proposalIdToExecute);
        (support, quorum,, isExecuted) = _tiebreakerCoreCommittee.getScheduleProposalState(proposalIdToExecute);
        assertTrue(support < quorum);

        // Tiebreaker subcommittee 1
        members = _tiebreakerSubCommittees[1].getMembers();
        for (uint256 i = 0; i < _tiebreakerSubCommittees[1].quorum() - 1; i++) {
            vm.prank(members[i]);
            _tiebreakerSubCommittees[1].scheduleProposal(proposalIdToExecute);
            (support, quorum,, isExecuted) = _tiebreakerSubCommittees[1].getScheduleProposalState(proposalIdToExecute);
            assertTrue(support < quorum);
            assertEq(isExecuted, false);
        }

        vm.prank(members[members.length - 1]);
        _tiebreakerSubCommittees[1].scheduleProposal(proposalIdToExecute);
        (support, quorum,, isExecuted) = _tiebreakerSubCommittees[1].getScheduleProposalState(proposalIdToExecute);
        assertEq(support, quorum);
        assertFalse(isExecuted);

        // Approve proposal for scheduling
        _tiebreakerSubCommittees[1].executeScheduleProposal(proposalIdToExecute);
        (support, quorum,, isExecuted) = _tiebreakerCoreCommittee.getScheduleProposalState(proposalIdToExecute);
        assertEq(support, quorum);

        // Waiting for submit delay pass
        _wait(_tiebreakerCoreCommittee.timelockDuration());

        _tiebreakerCoreCommittee.executeScheduleProposal(proposalIdToExecute);
    }

    function test_resume_withdrawals() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        address[] memory members;

        vm.prank(address(_lido.agent));
        _lido.withdrawalQueue.grantRole(
            0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d, address(_lido.agent)
        );
        vm.prank(address(_lido.agent));
        _lido.withdrawalQueue.pauseFor(type(uint256).max);
        assertEq(_lido.withdrawalQueue.isPaused(), true);

        // Tiebreak activation
        _assertNormalState();
        _lockStETH(_VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT());
        _lockStETH(_VETOER, 1 gwei);
        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        _activateNextState();
        _assertRageQuitState();
        _wait(_dualGovernance.getTiebreakerDetails().tiebreakerActivationTimeout);
        _activateNextState();

        // Tiebreaker subcommittee 0
        members = _tiebreakerSubCommittees[0].getMembers();
        for (uint256 i = 0; i < _tiebreakerSubCommittees[0].quorum() - 1; i++) {
            vm.prank(members[i]);
            _tiebreakerSubCommittees[0].sealableResume(address(_lido.withdrawalQueue));
            (support, quorum,, isExecuted) =
                _tiebreakerSubCommittees[0].getSealableResumeState(address(_lido.withdrawalQueue));
            assertTrue(support < quorum);
            assertFalse(isExecuted);
        }

        vm.prank(members[members.length - 1]);
        _tiebreakerSubCommittees[0].sealableResume(address(_lido.withdrawalQueue));
        (support, quorum,, isExecuted) =
            _tiebreakerSubCommittees[0].getSealableResumeState(address(_lido.withdrawalQueue));
        assertEq(support, quorum);
        assertFalse(isExecuted);

        _tiebreakerSubCommittees[0].executeSealableResume(address(_lido.withdrawalQueue));
        (support, quorum,, isExecuted) = _tiebreakerCoreCommittee.getSealableResumeState(
            address(_lido.withdrawalQueue),
            _tiebreakerCoreCommittee.getSealableResumeNonce(address(_lido.withdrawalQueue))
        );
        assertTrue(support < quorum);

        // Tiebreaker subcommittee 1
        members = _tiebreakerSubCommittees[1].getMembers();
        for (uint256 i = 0; i < _tiebreakerSubCommittees[1].quorum() - 1; i++) {
            vm.prank(members[i]);
            _tiebreakerSubCommittees[1].sealableResume(address(_lido.withdrawalQueue));
            (support, quorum,, isExecuted) =
                _tiebreakerSubCommittees[1].getSealableResumeState(address(_lido.withdrawalQueue));
            assertTrue(support < quorum);
            assertEq(isExecuted, false);
        }

        vm.prank(members[members.length - 1]);
        _tiebreakerSubCommittees[1].sealableResume(address(_lido.withdrawalQueue));
        (support, quorum,, isExecuted) =
            _tiebreakerSubCommittees[1].getSealableResumeState(address(_lido.withdrawalQueue));
        assertEq(support, quorum);
        assertFalse(isExecuted);

        _tiebreakerSubCommittees[1].executeSealableResume(address(_lido.withdrawalQueue));
        (support, quorum,, isExecuted) = _tiebreakerCoreCommittee.getSealableResumeState(
            address(_lido.withdrawalQueue),
            _tiebreakerCoreCommittee.getSealableResumeNonce(address(_lido.withdrawalQueue))
        );
        assertEq(support, quorum);

        // Waiting for submit delay pass
        _wait(_tiebreakerCoreCommittee.timelockDuration());

        _tiebreakerCoreCommittee.executeSealableResume(address(_lido.withdrawalQueue));

        assertEq(_lido.withdrawalQueue.isPaused(), false);
    }
}
