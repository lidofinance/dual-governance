// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";

import {Ownable, Executor} from "contracts/Executor.sol";
import {Proposers} from "contracts/libraries/Proposers.sol";

import {DGScenarioTestSetup, ExternalCallHelpers, ExternalCall, DualGovernance} from "../utils/integration-tests.sol";

interface ISomeContract {
    function someMethod(uint256 someParameter) external;
}

contract ExecutorOwnershipTransferScenarioTest is DGScenarioTestSetup {
    address private immutable _NEW_REGULAR_PROPOSER = makeAddr("NEW_REGULAR_PROPOSER");

    Executor private _oldAdminExecutor;
    Executor private _newAdminExecutor;

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});
        _newAdminExecutor = new Executor({owner: address(this)});

        _oldAdminExecutor = Executor(payable(_getAdminExecutor()));
        _newAdminExecutor.transferOwnership(address(_timelock));
    }

    function testFork_ExecutorOwnershipTransfer_HappyPath() external {
        uint256 shuffleExecutorsProposalId;
        DualGovernance dualGovernance = DualGovernance(_getGovernance());
        _step("1. DAO creates proposal to add new proposer and change the admin executor");
        {
            ExternalCall[] memory executorsShuffleCalls = ExternalCallHelpers.create(
                [
                    // 1. Register new proposer and assign it to the old admin executor
                    ExternalCall({
                        value: 0,
                        target: address(dualGovernance),
                        payload: abi.encodeCall(
                            dualGovernance.registerProposer, (_NEW_REGULAR_PROPOSER, address(_oldAdminExecutor))
                        )
                    }),
                    // 2. Assign previous proposer (Aragon Voting) to the new executor
                    ExternalCall({
                        value: 0,
                        target: address(dualGovernance),
                        payload: abi.encodeCall(
                            dualGovernance.setProposerExecutor, (address(_lido.voting), address(_newAdminExecutor))
                        )
                    }),
                    // 3. Replace the admin executor of the Timelock contract
                    ExternalCall({
                        value: 0,
                        target: address(_timelock),
                        payload: abi.encodeCall(_timelock.setAdminExecutor, (address(_newAdminExecutor)))
                    })
                ]
            );
            shuffleExecutorsProposalId =
                _submitProposalByAdminProposer(executorsShuffleCalls, "Register new proposer and swap executors");
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
            ExternalCall[] memory dgManageOperations = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        value: 0,
                        target: address(dualGovernance),
                        payload: abi.encodeCall(dualGovernance.unregisterProposer, (_NEW_REGULAR_PROPOSER))
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_timelock),
                        payload: abi.encodeCall(
                            _timelock.transferExecutorOwnership, (address(_oldAdminExecutor), address(_newAdminExecutor))
                        )
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_oldAdminExecutor),
                        payload: abi.encodeCall(
                            _oldAdminExecutor.execute, (address(_targetMock), 0, abi.encodeCall(ISomeContract.someMethod, (42)))
                        )
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_oldAdminExecutor),
                        payload: abi.encodeCall(_oldAdminExecutor.transferOwnership, (address(_timelock)))
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_timelock),
                        payload: abi.encodeCall(_timelock.setAfterSubmitDelay, (Durations.from(5 days)))
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_timelock),
                        payload: abi.encodeCall(_timelock.setAfterScheduleDelay, (Durations.ZERO))
                    })
                ]
            );

            uint256 proposalId = _submitProposalByAdminProposer(dgManageOperations, "Manage Dual Governance parameters");

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
