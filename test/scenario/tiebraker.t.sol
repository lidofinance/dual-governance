// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    ScenarioTestBlueprint, percents, ExecutorCall, ExecutorCallHelpers
} from "../utils/scenario-test-blueprint.sol";

import {TiebreakerCore} from "contracts/TiebreakerCore.sol";
import {TiebreakerSubCommittee} from "contracts/TiebreakerSubCommittee.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {DAO_AGENT} from "../utils/mainnet-addresses.sol";

contract TiebreakerScenarioTest is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");
    uint256 public constant PAUSE_INFINITELY = type(uint256).max;

    function setUp() external {
        _selectFork();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);
    }

    function test_proposal_approval() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        // Tiebreak activation
        _assertNormalState();
        _lockStETH(_VETOER, percents("15.00"));
        _wait(_config.SIGNALLING_MAX_DURATION());
        _activateNextState();
        _assertRageQuitState();
        _wait(_config.TIE_BREAK_ACTIVATION_TIMEOUT());
        _activateNextState();

        ExecutorCall[] memory proposalCalls = ExecutorCallHelpers.create(address(0), new bytes(0));
        uint256 proposalIdToExecute = _submitProposal(_dualGovernance, "Proposal for execution", proposalCalls);

        // Tiebreaker subcommittee 0
        for (uint256 i = 0; i < _tiebreakerSubCommittees[0].quorum - 1; i++) {
            vm.prank(_tiebreakerSubCommittees[0].members[i]);
            _tiebreakerSubCommittees[0].committee.voteApproveProposal(proposalIdToExecute, true);
            (support, quorum, isExecuted) =
                _tiebreakerSubCommittees[0].committee.getApproveProposalState(proposalIdToExecute);
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(_tiebreakerSubCommittees[0].members[_tiebreakerSubCommittees[0].members.length - 1]);
        _tiebreakerSubCommittees[0].committee.voteApproveProposal(proposalIdToExecute, true);
        (support, quorum, isExecuted) =
            _tiebreakerSubCommittees[0].committee.getApproveProposalState(proposalIdToExecute);
        assert(support == quorum);
        assert(isExecuted == false);

        _tiebreakerSubCommittees[0].committee.executeApproveProposal(proposalIdToExecute);
        (support, quorum, isExecuted) = _tiebreakerCommittee.getApproveProposalState(proposalIdToExecute);
        assert(support < quorum);

        // Tiebreaker subcommittee 1
        for (uint256 i = 0; i < _tiebreakerSubCommittees[1].quorum - 1; i++) {
            vm.prank(_tiebreakerSubCommittees[1].members[i]);
            _tiebreakerSubCommittees[1].committee.voteApproveProposal(proposalIdToExecute, true);
            (support, quorum, isExecuted) =
                _tiebreakerSubCommittees[1].committee.getApproveProposalState(proposalIdToExecute);
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(_tiebreakerSubCommittees[1].members[_tiebreakerSubCommittees[1].members.length - 1]);
        _tiebreakerSubCommittees[1].committee.voteApproveProposal(proposalIdToExecute, true);
        (support, quorum, isExecuted) =
            _tiebreakerSubCommittees[1].committee.getApproveProposalState(proposalIdToExecute);
        assert(support == quorum);
        assert(isExecuted == false);

        // Approve proposal for scheduling
        _tiebreakerSubCommittees[1].committee.executeApproveProposal(proposalIdToExecute);
        (support, quorum, isExecuted) = _tiebreakerCommittee.getApproveProposalState(proposalIdToExecute);
        assert(support == quorum);

        _tiebreakerCommittee.executeApproveProposal(proposalIdToExecute);

        // Waiting for submit delay pass
        _wait(_config.AFTER_SUBMIT_DELAY());

        _dualGovernance.tiebreakerSchedule(proposalIdToExecute);
    }

    function test_resume_withdrawals() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        // Tiebreak activation
        _assertNormalState();
        _lockStETH(_VETOER, percents("15.00"));
        _wait(_config.SIGNALLING_MAX_DURATION());
        _activateNextState();
        _assertRageQuitState();
        vm.startPrank(DAO_AGENT);
        _WITHDRAWAL_QUEUE.grantRole(_WITHDRAWAL_QUEUE.PAUSE_ROLE(), address(this));
        vm.stopPrank();
        _WITHDRAWAL_QUEUE.pauseFor(PAUSE_INFINITELY);
        _activateNextState();

        // Tiebreaker subcommittee 0
        for (uint256 i = 0; i < _tiebreakerSubCommittees[0].quorum - 1; i++) {
            vm.prank(_tiebreakerSubCommittees[0].members[i]);
            _tiebreakerSubCommittees[0].committee.voteApproveSealableResume(address(_WITHDRAWAL_QUEUE), true);
            (support, quorum, isExecuted) =
                _tiebreakerSubCommittees[0].committee.getApproveSealableResumeState(address(_WITHDRAWAL_QUEUE));
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(_tiebreakerSubCommittees[0].members[_tiebreakerSubCommittees[0].members.length - 1]);
        _tiebreakerSubCommittees[0].committee.voteApproveSealableResume(address(_WITHDRAWAL_QUEUE), true);
        (support, quorum, isExecuted) =
            _tiebreakerSubCommittees[0].committee.getApproveSealableResumeState(address(_WITHDRAWAL_QUEUE));
        assert(support == quorum);
        assert(isExecuted == false);

        _tiebreakerSubCommittees[0].committee.executeApproveSealableResume(address(_WITHDRAWAL_QUEUE));
        (support, quorum, isExecuted) = _tiebreakerCommittee.getSealableResumeState(
            address(_WITHDRAWAL_QUEUE), _tiebreakerCommittee.getSealableResumeNonce(address(_WITHDRAWAL_QUEUE))
        );
        assert(support < quorum);

        // Tiebreaker subcommittee 1
        for (uint256 i = 0; i < _tiebreakerSubCommittees[1].quorum - 1; i++) {
            vm.prank(_tiebreakerSubCommittees[1].members[i]);
            _tiebreakerSubCommittees[1].committee.voteApproveSealableResume(address(_WITHDRAWAL_QUEUE), true);
            (support, quorum, isExecuted) =
                _tiebreakerSubCommittees[1].committee.getApproveSealableResumeState(address(_WITHDRAWAL_QUEUE));
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(_tiebreakerSubCommittees[1].members[_tiebreakerSubCommittees[1].members.length - 1]);
        _tiebreakerSubCommittees[1].committee.voteApproveSealableResume(address(_WITHDRAWAL_QUEUE), true);
        (support, quorum, isExecuted) =
            _tiebreakerSubCommittees[1].committee.getApproveSealableResumeState(address(_WITHDRAWAL_QUEUE));
        assert(support == quorum);
        assert(isExecuted == false);

        // Approve proposal for scheduling
        _tiebreakerSubCommittees[1].committee.executeApproveSealableResume(address(_WITHDRAWAL_QUEUE));
        (support, quorum, isExecuted) = _tiebreakerCommittee.getSealableResumeState(
            address(_WITHDRAWAL_QUEUE), _tiebreakerCommittee.getSealableResumeNonce(address(_WITHDRAWAL_QUEUE))
        );
        assert(support == quorum);

        uint256 lastProposalId = EmergencyProtectedTimelock(address(_dualGovernance.TIMELOCK())).getProposalsCount();
        _tiebreakerCommittee.executeSealableResume(address(_WITHDRAWAL_QUEUE));
        uint256 proposalIdToExecute =
            EmergencyProtectedTimelock(address(_dualGovernance.TIMELOCK())).getProposalsCount();
        assert(lastProposalId + 1 == proposalIdToExecute);

        // Waiting for submit delay pass
        _wait(_config.AFTER_SUBMIT_DELAY());

        _dualGovernance.tiebreakerSchedule(proposalIdToExecute);
    }
}
