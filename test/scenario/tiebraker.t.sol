// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    ScenarioTestBlueprint, percents, ExecutorCall, ExecutorCallHelpers
} from "../utils/scenario-test-blueprint.sol";

import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {DAO_AGENT} from "../utils/mainnet-addresses.sol";

contract TiebreakerScenarioTest is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");
    uint256 public constant PAUSE_INFINITELY = type(uint256).max;

    function setUp() external {
        _selectFork();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);
        _depositStETH(_VETOER, 1 ether);
    }

    function test_proposal_approval() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        address[] memory members;

        // Tiebreak activation
        _assertNormalState();
        _lockStETH(_VETOER, percents(_config.SECOND_SEAL_RAGE_QUIT_SUPPORT()));
        _lockStETH(_VETOER, 1 gwei);
        _wait(_config.DYNAMIC_TIMELOCK_MAX_DURATION().plusSeconds(1));
        _activateNextState();
        _assertRageQuitState();
        _wait(_config.TIE_BREAK_ACTIVATION_TIMEOUT());
        _activateNextState();

        ExecutorCall[] memory proposalCalls = ExecutorCallHelpers.create(address(0), new bytes(0));
        uint256 proposalIdToExecute = _submitProposal(_dualGovernance, "Proposal for execution", proposalCalls);

        // Tiebreaker subcommittee 0
        members = _tiebreakerSubCommittees[0].getMembers();
        for (uint256 i = 0; i < _tiebreakerSubCommittees[0].quorum() - 1; i++) {
            vm.prank(members[i]);
            _tiebreakerSubCommittees[0].scheduleProposal(proposalIdToExecute);
            (support, quorum, isExecuted) = _tiebreakerSubCommittees[0].getScheduleProposalState(proposalIdToExecute);
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(members[members.length - 1]);
        _tiebreakerSubCommittees[0].scheduleProposal(proposalIdToExecute);
        (support, quorum, isExecuted) = _tiebreakerSubCommittees[0].getScheduleProposalState(proposalIdToExecute);
        assert(support == quorum);
        assert(isExecuted == false);

        _tiebreakerSubCommittees[0].executeScheduleProposal(proposalIdToExecute);
        (support, quorum, isExecuted) = _tiebreakerCommittee.getScheduleProposalState(proposalIdToExecute);
        assert(support < quorum);

        // Tiebreaker subcommittee 1
        members = _tiebreakerSubCommittees[1].getMembers();
        for (uint256 i = 0; i < _tiebreakerSubCommittees[1].quorum() - 1; i++) {
            vm.prank(members[i]);
            _tiebreakerSubCommittees[1].scheduleProposal(proposalIdToExecute);
            (support, quorum, isExecuted) = _tiebreakerSubCommittees[1].getScheduleProposalState(proposalIdToExecute);
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(members[members.length - 1]);
        _tiebreakerSubCommittees[1].scheduleProposal(proposalIdToExecute);
        (support, quorum, isExecuted) = _tiebreakerSubCommittees[1].getScheduleProposalState(proposalIdToExecute);
        assert(support == quorum);
        assert(isExecuted == false);

        // Approve proposal for scheduling
        _tiebreakerSubCommittees[1].executeScheduleProposal(proposalIdToExecute);
        (support, quorum, isExecuted) = _tiebreakerCommittee.getScheduleProposalState(proposalIdToExecute);
        assert(support == quorum);

        // Waiting for submit delay pass
        _wait(_config.AFTER_SUBMIT_DELAY());

        _tiebreakerCommittee.executeScheduleProposal(proposalIdToExecute);
    }

    function test_resume_withdrawals() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        address[] memory members;

        vm.prank(DAO_AGENT);
        _WITHDRAWAL_QUEUE.grantRole(
            0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d, address(DAO_AGENT)
        );
        vm.prank(DAO_AGENT);
        _WITHDRAWAL_QUEUE.pauseFor(type(uint256).max);
        assertEq(_WITHDRAWAL_QUEUE.isPaused(), true);

        // Tiebreak activation
        _assertNormalState();
        _lockStETH(_VETOER, percents(_config.SECOND_SEAL_RAGE_QUIT_SUPPORT()));
        _lockStETH(_VETOER, 1 gwei);
        _wait(_config.DYNAMIC_TIMELOCK_MAX_DURATION().plusSeconds(1));
        _activateNextState();
        _assertRageQuitState();
        _wait(_config.TIE_BREAK_ACTIVATION_TIMEOUT());
        _activateNextState();

        // Tiebreaker subcommittee 0
        members = _tiebreakerSubCommittees[0].getMembers();
        for (uint256 i = 0; i < _tiebreakerSubCommittees[0].quorum() - 1; i++) {
            vm.prank(members[i]);
            _tiebreakerSubCommittees[0].sealableResume(address(_WITHDRAWAL_QUEUE));
            (support, quorum, isExecuted) =
                _tiebreakerSubCommittees[0].getSealableResumeState(address(_WITHDRAWAL_QUEUE));
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(members[members.length - 1]);
        _tiebreakerSubCommittees[0].sealableResume(address(_WITHDRAWAL_QUEUE));
        (support, quorum, isExecuted) = _tiebreakerSubCommittees[0].getSealableResumeState(address(_WITHDRAWAL_QUEUE));
        assert(support == quorum);
        assert(isExecuted == false);

        _tiebreakerSubCommittees[0].executeSealableResume(address(_WITHDRAWAL_QUEUE));
        (support, quorum, isExecuted) = _tiebreakerCommittee.getSealableResumeState(
            address(_WITHDRAWAL_QUEUE), _tiebreakerCommittee.getSealableResumeNonce(address(_WITHDRAWAL_QUEUE))
        );
        assert(support < quorum);

        // Tiebreaker subcommittee 1
        members = _tiebreakerSubCommittees[1].getMembers();
        for (uint256 i = 0; i < _tiebreakerSubCommittees[1].quorum() - 1; i++) {
            vm.prank(members[i]);
            _tiebreakerSubCommittees[1].sealableResume(address(_WITHDRAWAL_QUEUE));
            (support, quorum, isExecuted) =
                _tiebreakerSubCommittees[1].getSealableResumeState(address(_WITHDRAWAL_QUEUE));
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(members[members.length - 1]);
        _tiebreakerSubCommittees[1].sealableResume(address(_WITHDRAWAL_QUEUE));
        (support, quorum, isExecuted) = _tiebreakerSubCommittees[1].getSealableResumeState(address(_WITHDRAWAL_QUEUE));
        assert(support == quorum);
        assert(isExecuted == false);

        _tiebreakerSubCommittees[1].executeSealableResume(address(_WITHDRAWAL_QUEUE));
        (support, quorum, isExecuted) = _tiebreakerCommittee.getSealableResumeState(
            address(_WITHDRAWAL_QUEUE), _tiebreakerCommittee.getSealableResumeNonce(address(_WITHDRAWAL_QUEUE))
        );
        assert(support == quorum);

        _tiebreakerCommittee.executeSealableResume(address(_WITHDRAWAL_QUEUE));

        assertEq(_WITHDRAWAL_QUEUE.isPaused(), false);
    }
}
