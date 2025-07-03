// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {IGovernance} from "contracts/interfaces/IGovernance.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";

import {DGRegressionTestSetup} from "../utils/integration-tests.sol";

import {CallsScriptBuilder} from "scripts/utils/CallsScriptBuilder.sol";
import {ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";

import {IACL} from "scripts/launch/interfaces/IACL.sol";

contract EmergencyProtectionRegressionTest is DGRegressionTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;
    using CallsScriptBuilder for CallsScriptBuilder.Context;
    using LidoUtils for LidoUtils.Context;

    function setUp() external {
        _loadOrDeployDGSetup();

        if (vm.envOr(string("GRANT_REQUIRED_PERMISSIONS"), false)) {
            address agent = address(_lido.agent);
            address voting = address(_lido.voting);
            address adminExecutor = address(_dgDeployedContracts.adminExecutor);
            bytes32 runScriptRole = _lido.agent.RUN_SCRIPT_ROLE();

            if (!_lido.acl.hasPermission(adminExecutor, agent, runScriptRole)) {
                vm.startPrank(_lido.acl.getPermissionManager(agent, runScriptRole));
                {
                    _lido.acl.grantPermission(adminExecutor, agent, runScriptRole);
                    _lido.acl.revokePermission(voting, agent, runScriptRole);
                    _lido.acl.setPermissionManager(agent, agent, runScriptRole);
                }
                vm.stopPrank();

                assertEq(_lido.acl.getPermissionManager(agent, runScriptRole), agent);
                assertTrue(_lido.acl.hasPermission(adminExecutor, agent, runScriptRole));
                assertFalse(_lido.acl.hasPermission(voting, agent, runScriptRole));

                console.log(unicode"⚠️ Permission 'Agent.RUN_SCRIPT_ROLE' was granted to the AdminExecutor");
                console.log(unicode"⚠️ Permission 'Agent.RUN_SCRIPT_ROLE' was revoked from the Voting");
                console.log(unicode"⚠️ Permission manager on 'Agent.RUN_SCRIPT_ROLE' was set to the Agent");
            }
        }
    }

    function testFork_EmergencyReset_HappyPath() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. The proposal is submitted");
        {
            proposalId =
                _submitProposalByAdminProposer(regularStaffCalls, "Propose to doSmth on target passing dual governance");
            _assertSubmittedProposalData(proposalId, regularStaffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(proposalId, false);
        }

        _step("2. The proposal is scheduled");
        {
            // wait until the delay has passed
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(proposalId, true);

            _scheduleProposal(proposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(proposalId);
            _assertCanExecute(proposalId, false);
        }

        _step("3. Emergency mode activated & governance reset");
        {
            // some time passes and emergency committee activates emergency mode
            // and resets the controller
            _wait(_getAfterScheduleDelay().dividedBy(2));

            // committee resets governance
            _activateEmergencyMode();
            _emergencyReset();

            // proposal is cancelled now
            _wait(_getAfterScheduleDelay().dividedBy(2).plusSeconds(1));

            // remove cancelled call from the timelock
            _assertCanExecute(proposalId, false);
            _assertProposalCancelled(proposalId);
        }

        address acl = address(_lido.acl);
        address agent = address(_lido.agent);
        address voting = address(_lido.voting);
        address adminExecutor = address(_dgDeployedContracts.adminExecutor);

        uint256 disconnectTimelockProposalId;
        _step(
            "4. DAO submits a proposal using Voting contract through TimelockedGovernance to the transfer Agent.RUN_SCRIPT_ROLE"
        );
        {
            IGovernance governance = IGovernance(_timelock.getGovernance());

            ExternalCallsBuilder.Context memory proposalCallsBuilder = ExternalCallsBuilder.create(2);
            proposalCallsBuilder.addForwardCall(
                agent, acl, abi.encodeCall(IACL.grantPermission, (voting, agent, _lido.agent.RUN_SCRIPT_ROLE()))
            );

            proposalCallsBuilder.addForwardCall(
                agent, acl, abi.encodeCall(IACL.revokePermission, (adminExecutor, agent, _lido.agent.RUN_SCRIPT_ROLE()))
            );

            CallsScriptBuilder.Context memory voteWithProposal = CallsScriptBuilder.create(
                address(governance),
                abi.encodeCall(
                    governance.submitProposal,
                    (proposalCallsBuilder.getResult(), "Proposal to grant RUN_SCRIPT_ROLE to DAO Voting")
                )
            );

            uint256 voteId =
                _lido.adoptVote("Proposal to grant RUN_SCRIPT_ROLE to DAO Voting", voteWithProposal.getResult());

            _lido.executeVote(voteId);

            disconnectTimelockProposalId = _dgDeployedContracts.timelock.getProposalsCount();

            _assertProposalSubmitted(disconnectTimelockProposalId);
        }

        _step("5. Schedule and execute proposal");
        {
            _wait(_getAfterSubmitDelay());
            _scheduleProposal(disconnectTimelockProposalId);

            _assertProposalScheduled(disconnectTimelockProposalId);
            _wait(_getAfterScheduleDelay());
            _assertCanExecute(disconnectTimelockProposalId, true);

            _executeProposal(disconnectTimelockProposalId);
            _assertProposalExecuted(disconnectTimelockProposalId);
        }

        _step("6. Check RUN_SCRIPT_ROLE has been transferred to Voting contract");
        {
            assertTrue(_lido.acl.hasPermission(voting, agent, _lido.agent.RUN_SCRIPT_ROLE()));
            assertFalse(_lido.acl.hasPermission(adminExecutor, agent, _lido.agent.RUN_SCRIPT_ROLE()));
            assertEq(_lido.acl.getPermissionManager(agent, _lido.agent.RUN_SCRIPT_ROLE()), agent);
        }
    }

    function testFork_EmergencyProtectionExpiration_HappyPath() external {
        _step("1. DAO operates regularly");
        {
            _adoptProposalByAdminProposer(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }

        _step("2. Emergency protection expires");
        {
            if (_isEmergencyProtectionEnabled()) {
                _wait(_getEmergencyProtectionDuration().plusSeconds(1));
            }
            assertFalse(_isEmergencyProtectionEnabled());
        }

        _step("3. Emergency activation committee has not power");
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    EmergencyProtection.EmergencyProtectionExpired.selector,
                    _getEmergencyProtectionEndsAfter().toSeconds()
                )
            );
            this.external__activateEmergencyMode();
        }

        _step("4. DAO operated as usually when emergency protection expired");
        {
            _adoptProposalByAdminProposer(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }
    }

    function testFork_EmergencyExecution_HappyPath() external {
        ExternalCall[] memory incorrectStuffCalls = _getMockTargetRegularStaffCalls({callsCount: 5});
        ExternalCall[] memory correctStuffCalls = _getMockTargetRegularStaffCalls({callsCount: 6});

        uint256 badProposalId;
        uint256 goodProposalId;
        _step("1. The bad proposal is submitted");
        {
            badProposalId = _submitProposalByAdminProposer(
                incorrectStuffCalls, "Propose to doSmth incorrect on target passing dual governance"
            );
            _assertSubmittedProposalData(badProposalId, incorrectStuffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(badProposalId, false);
        }

        _step("2. The bad proposal is scheduled");
        {
            // wait until the delay has passed
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(badProposalId, true);

            _scheduleProposal(badProposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(badProposalId);
            _assertCanExecute(badProposalId, false);
        }

        _step("3. Emergency mode is activated - the bad proposal can't be executed");
        {
            // some time passes and emergency committee activates emergency mode
            _wait(_getAfterScheduleDelay().dividedBy(2));

            // committee activates emergency mode
            _activateEmergencyMode();

            _assertCanExecute(badProposalId, false);

            _wait(_getAfterScheduleDelay().dividedBy(2).plusSeconds(100));

            // no one can execute the proposal now, except the emergency execution committee
            _assertCanExecute(badProposalId, false);
            _assertProposalScheduled(badProposalId);
        }

        _step("4. The good proposal is submitted");
        {
            goodProposalId = _submitProposalByAdminProposer(
                correctStuffCalls, "Propose to doSmth correct on target passing dual governance"
            );
            _assertSubmittedProposalData(goodProposalId, correctStuffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(goodProposalId, false);
        }

        _step("5. The good proposal is scheduled");
        {
            // wait until the delay has passed
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(goodProposalId, true);

            _scheduleProposal(goodProposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(goodProposalId);
            _assertCanExecute(goodProposalId, false);
        }

        _step("6. Emergency execution committee executes the good proposal");
        {
            _wait(_getAfterScheduleDelay().plusSeconds(1));

            // no one can execute the good proposal now, except the emergency execution committee
            _assertCanExecute(goodProposalId, false);
            _assertProposalScheduled(goodProposalId);

            // emergency execution committee executes the good proposal
            _emergencyExecute(goodProposalId);
            _assertProposalExecuted(goodProposalId);
            _assertTargetMockCalls(_getAdminExecutor(), correctStuffCalls);
        }

        _step("7. Emergency mode expired and the bad proposal is cancelled");
        {
            _wait(_getEmergencyModeDuration().plusSeconds(1));
            _deactivateEmergencyMode();
            assertFalse(_isEmergencyModeActive());

            assertEq(_timelock.getEmergencyExecutionCommittee(), address(0));

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
            vm.prank(address(0));
            _timelock.emergencyExecute(badProposalId);

            _assertProposalCancelled(badProposalId);
            _assertCanExecute(badProposalId, false);
        }
    }

    function testFork_EmergencyModeExpiration_HappyPath() external {
        ExternalCall[] memory regularStuffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. The proposal is submitted");
        {
            proposalId =
                _submitProposalByAdminProposer(regularStuffCalls, "Propose to doSmth on target passing dual governance");
            _assertSubmittedProposalData(proposalId, regularStuffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(proposalId, false);
        }

        _step("2. The proposal is scheduled");
        {
            // wait until the delay has passed
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(proposalId, true);

            _scheduleProposal(proposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(proposalId);
            _assertCanExecute(proposalId, false);
        }

        _step("3. Emergency mode activated");
        {
            // some time passes and emergency committee activates emergency mode
            _wait(_getAfterScheduleDelay().dividedBy(2));

            // committee activates emergency mode
            _activateEmergencyMode();

            // no one can execute the proposal now, except the emergency execution committee
            _assertCanExecute(proposalId, false);
            _assertProposalScheduled(proposalId);
        }

        _step("4. Emergency mode expired and all proposals are cancelled");
        {
            _wait(_getEmergencyModeDuration().plusSeconds(1));

            vm.prank(makeAddr("Random address - Anyone"));
            _deactivateEmergencyMode();
            assertFalse(_isEmergencyModeActive());

            assertEq(_timelock.getEmergencyExecutionCommittee(), address(0));

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
            vm.prank(address(0));
            _timelock.emergencyExecute(proposalId);

            _assertProposalCancelled(proposalId);
        }

        _step("5. Emergency committees have no power anymore");
        {
            assertEq(_timelock.getEmergencyActivationCommittee(), address(0));

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.EmergencyProtectionExpired.selector, 0));
            vm.prank(address(0));
            _timelock.activateEmergencyMode();
        }
    }
}
