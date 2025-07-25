// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";

import {Executor} from "contracts/Executor.sol";
import {Proposers} from "contracts/libraries/Proposers.sol";

import {DGRegressionTestSetup, DualGovernance} from "../utils/integration-tests.sol";

import {ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";

interface ISomeContract {
    function someMethod(uint256 someParameter) external;
}

contract ExecutorOwnershipTransferRegressionTest is DGRegressionTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    address private immutable _NEW_REGULAR_PROPOSER = makeAddr("NEW_REGULAR_PROPOSER");

    Executor private _oldAdminExecutor;
    Executor private _newAdminExecutor;

    function setUp() external {
        _loadOrDeployDGSetup();
        _newAdminExecutor = new Executor({owner: address(this)});

        _oldAdminExecutor = Executor(payable(_getAdminExecutor()));
        _newAdminExecutor.transferOwnership(address(_timelock));
    }

    function testFork_ExecutorOwnershipTransfer_HappyPath() external {
        uint256 shuffleExecutorsProposalId;
        DualGovernance dualGovernance = DualGovernance(_getGovernance());

        _step("1. DAO creates proposal to add new proposer and change the admin executor");
        {
            ExternalCallsBuilder.Context memory executorsShuffleCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 3});

            // 1. Register new proposer and assign it to the old admin executor
            executorsShuffleCallsBuilder.addCall(
                address(dualGovernance),
                abi.encodeCall(dualGovernance.registerProposer, (_NEW_REGULAR_PROPOSER, address(_oldAdminExecutor)))
            );
            // 2. Assign previous proposer (Aragon Voting) to the new executor
            executorsShuffleCallsBuilder.addCall(
                address(dualGovernance),
                abi.encodeCall(dualGovernance.setProposerExecutor, (address(_lido.voting), address(_newAdminExecutor)))
            );
            // 3. Replace the admin executor of the Timelock contract
            executorsShuffleCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setAdminExecutor, (address(_newAdminExecutor)))
            );

            shuffleExecutorsProposalId = _submitProposalByAdminProposer(
                executorsShuffleCallsBuilder.getResult(), "Register new proposer and swap executors"
            );
        }

        _step("2. Proposal is scheduled and executed");
        {
            _assertProposalSubmitted(shuffleExecutorsProposalId);
            _wait(_getAfterSubmitDelay());

            _scheduleProposal(shuffleExecutorsProposalId);
            _assertProposalScheduled(shuffleExecutorsProposalId);
            _wait(_getAfterScheduleDelay());

            _executeProposal(shuffleExecutorsProposalId);
        }
        _step("3. The proposers and executors were set up correctly");
        {
            assertEq(_getAdminExecutor(), address(_newAdminExecutor));

            Proposers.Proposer[] memory proposers = _getProposers();

            assertEq(proposers.length, 2);

            assertEq(proposers[0].account, address(_lido.voting));
            assertEq(proposers[0].executor, address(_newAdminExecutor));

            assertEq(proposers[1].account, _NEW_REGULAR_PROPOSER);
            assertEq(proposers[1].executor, address(_oldAdminExecutor));
        }

        _step("4. New admin proposer can manage Dual Governance contracts");
        {
            ExternalCallsBuilder.Context memory dgManageOperationsCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 6});

            dgManageOperationsCallsBuilder.addCall(
                address(dualGovernance), abi.encodeCall(dualGovernance.unregisterProposer, (_NEW_REGULAR_PROPOSER))
            );
            dgManageOperationsCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.transferExecutorOwnership, (address(_oldAdminExecutor), address(_newAdminExecutor))
                )
            );
            dgManageOperationsCallsBuilder.addCall(
                address(_oldAdminExecutor),
                abi.encodeCall(
                    _oldAdminExecutor.execute, (address(_targetMock), 0, abi.encodeCall(ISomeContract.someMethod, (42)))
                )
            );
            dgManageOperationsCallsBuilder.addCall(
                address(_oldAdminExecutor), abi.encodeCall(_oldAdminExecutor.transferOwnership, (address(_timelock)))
            );
            dgManageOperationsCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setAfterSubmitDelay, (_timelock.MAX_AFTER_SUBMIT_DELAY().minusSeconds(1)))
            );
            dgManageOperationsCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setAfterScheduleDelay, (Durations.ZERO))
            );

            uint256 proposalId = _submitProposalByAdminProposer(
                dgManageOperationsCallsBuilder.getResult(), "Manage Dual Governance parameters"
            );

            _assertProposalSubmitted(proposalId);
            _wait(_getAfterSubmitDelay());

            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);
            _wait(_getAfterScheduleDelay());

            _executeProposal(proposalId);

            Proposers.Proposer[] memory proposers = _getProposers();

            assertEq(proposers.length, 1);
            assertEq(proposers[0].account, address(_lido.voting));
            assertEq(proposers[0].executor, address(_newAdminExecutor));

            assertEq(_getAfterScheduleDelay(), Durations.ZERO);

            assertEq(_oldAdminExecutor.owner(), address(_timelock));
        }
    }
}
