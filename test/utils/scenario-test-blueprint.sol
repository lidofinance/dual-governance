// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EscrowState, Escrow, VetoerState, LockedAssetsTotals} from "contracts/Escrow.sol";
import {Executor} from "contracts/Executor.sol";

import {EmergencyActivationCommittee} from "contracts/committees/EmergencyActivationCommittee.sol";
import {EmergencyExecutionCommittee} from "contracts/committees/EmergencyExecutionCommittee.sol";
import {TiebreakerCore} from "contracts/committees/TiebreakerCore.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

import {ResealManager} from "contracts/ResealManager.sol";

import {
    ProposalStatus, EmergencyProtection, EmergencyProtectedTimelock
} from "contracts/EmergencyProtectedTimelock.sol";

import {DualGovernance, State as DGState, DualGovernanceStateMachine} from "contracts/DualGovernance.sol";
import {TimelockedGovernance, IGovernance} from "contracts/TimelockedGovernance.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {Percents, percents} from "../utils/percents.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";

import {IWithdrawalQueue, WithdrawalRequestStatus} from "contracts/interfaces/IWithdrawalQueue.sol";
import {IDangerousContract} from "../utils/interfaces.sol";
import {ExternalCallHelpers} from "../utils/executor-calls.sol";
import {Utils, TargetMock, console} from "../utils/utils.sol";
import {ImmutableDualGovernanceConfigProvider} from "contracts/DualGovernanceConfigProvider.sol";

import {DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, DAO_AGENT} from "../utils/mainnet-addresses.sol";

import {Deployment} from "../utils/deployment.sol";

struct Balances {
    uint256 stETHAmount;
    uint256 stETHShares;
    uint256 wstETHAmount;
    uint256 wstETHShares;
}

uint256 constant PERCENTS_PRECISION = 16;

function countDigits(uint256 number) pure returns (uint256 digitsCount) {
    do {
        digitsCount++;
    } while (number / 10 != 0);
}

Duration constant ONE_SECOND = Duration.wrap(1);

contract ScenarioTestBlueprint is Test {
    address internal immutable _ADMIN_PROPOSER = DAO_VOTING;
    Duration internal immutable _EMERGENCY_MODE_DURATION = Durations.from(180 days);
    Duration internal immutable _EMERGENCY_PROTECTION_DURATION = Durations.from(90 days);
    address internal immutable _EMERGENCY_ACTIVATION_COMMITTEE = makeAddr("EMERGENCY_ACTIVATION_COMMITTEE");
    address internal immutable _EMERGENCY_EXECUTION_COMMITTEE = makeAddr("EMERGENCY_EXECUTION_COMMITTEE");

    Duration internal immutable _SEALING_DURATION = Durations.from(14 days);
    Duration internal immutable _SEALING_COMMITTEE_LIFETIME = Durations.from(365 days);
    address internal immutable _SEALING_COMMITTEE = makeAddr("SEALING_COMMITTEE");

    Duration internal immutable _AFTER_SUBMIT_DELAY = Durations.from(3 days);
    Duration internal immutable _AFTER_SCHEDULE_DELAY = Durations.from(2 days);

    // ---
    // Protocol Dependencies
    // ---

    IStETH public immutable _ST_ETH = IStETH(ST_ETH);
    IWstETH public immutable _WST_ETH = IWstETH(WST_ETH);
    IWithdrawalQueue public immutable _WITHDRAWAL_QUEUE = IWithdrawalQueue(WITHDRAWAL_QUEUE);

    // ---
    // Core Components
    // ---

    Executor internal _adminExecutor;
    EmergencyProtectedTimelock internal _timelock;

    ResealManager internal _resealManager;
    DualGovernance internal _dualGovernance;
    ImmutableDualGovernanceConfigProvider internal _dualGovernanceConfigProvider;

    TimelockedGovernance internal _timelockedGovernance;

    // ---
    // Committees
    // ---

    EmergencyActivationCommittee internal _emergencyActivationCommittee;
    EmergencyExecutionCommittee internal _emergencyExecutionCommittee;
    TiebreakerCore internal _tiebreakerCommittee;
    TiebreakerSubCommittee[] internal _tiebreakerSubCommittees;

    address[] internal _sealableWithdrawalBlockers = [WITHDRAWAL_QUEUE];

    // ---
    // Helper Contracts
    // ---
    TargetMock internal _target;

    // ---
    // Helper Getters
    // ---

    function _getVetoSignallingEscrow() internal view returns (Escrow) {
        return Escrow(payable(_dualGovernance.getVetoSignallingEscrow()));
    }

    function _getRageQuitEscrow() internal view returns (Escrow) {
        address rageQuitEscrow = _dualGovernance.getRageQuitEscrow();
        return Escrow(payable(rageQuitEscrow));
    }

    function _getTargetRegularStaffCalls() internal view returns (ExternalCall[] memory) {
        return ExternalCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRegularStaff, (42)));
    }

    function _getVetoSignallingState()
        internal
        view
        returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt)
    {
        DualGovernanceStateMachine.Context memory stateContext = _dualGovernance.getCurrentStateContext();
        isActive = stateContext.state == DGState.VetoSignalling;
        duration = _dualGovernance.getDynamicDelayDuration().toSeconds();
        enteredAt = stateContext.enteredAt.toSeconds();
        activatedAt = stateContext.vetoSignallingActivatedAt.toSeconds();
    }

    function _getVetoSignallingDeactivationState()
        internal
        view
        returns (bool isActive, uint256 duration, uint256 enteredAt)
    {
        DualGovernanceStateMachine.Context memory stateContext = _dualGovernance.getCurrentStateContext();
        isActive = stateContext.state == DGState.VetoSignallingDeactivation;
        duration = _dualGovernanceConfigProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().toSeconds();
        enteredAt = stateContext.enteredAt.toSeconds();
    }

    // ---
    // Network Configuration
    // ---
    function _selectFork() internal {
        Utils.selectFork();
    }

    // ---
    // Balances Manipulation
    // ---

    function _depositStETH(
        address account,
        uint256 amountToMint
    ) internal returns (uint256 sharesMinted, uint256 amountMinted) {
        return Utils.depositStETH(account, amountToMint);
    }

    function _setupStETHWhale(address vetoer) internal returns (uint256 shares, uint256 amount) {
        Utils.removeLidoStakingLimit();
        return Utils.setupStETHWhale(vetoer, percents("10.0"));
    }

    function _setupStETHWhale(
        address vetoer,
        Percents memory vetoPowerInPercents
    ) internal returns (uint256 shares, uint256 amount) {
        Utils.removeLidoStakingLimit();
        return Utils.setupStETHWhale(vetoer, vetoPowerInPercents);
    }

    function _getBalances(address vetoer) internal view returns (Balances memory balances) {
        uint256 stETHAmount = _ST_ETH.balanceOf(vetoer);
        uint256 wstETHShares = _WST_ETH.balanceOf(vetoer);
        balances = Balances({
            stETHAmount: stETHAmount,
            stETHShares: _ST_ETH.getSharesByPooledEth(stETHAmount),
            wstETHAmount: _ST_ETH.getPooledEthByShares(wstETHShares),
            wstETHShares: wstETHShares
        });
    }

    // ---
    // Escrow Manipulation
    // ---
    function _lockStETH(address vetoer, Percents memory vetoPowerInPercents) internal returns (uint256 amount) {
        (, amount) = _setupStETHWhale(vetoer, vetoPowerInPercents);
        _lockStETH(vetoer, amount);
    }

    function _lockStETH(address vetoer, uint256 amount) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        vm.startPrank(vetoer);
        if (_ST_ETH.allowance(vetoer, address(escrow)) < amount) {
            _ST_ETH.approve(address(escrow), amount);
        }
        escrow.lockStETH(amount);
        vm.stopPrank();
    }

    function _unlockStETH(address vetoer) internal {
        vm.startPrank(vetoer);
        _getVetoSignallingEscrow().unlockStETH();
        vm.stopPrank();
    }

    function _lockWstETH(address vetoer, uint256 amount) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        vm.startPrank(vetoer);
        if (_WST_ETH.allowance(vetoer, address(escrow)) < amount) {
            _WST_ETH.approve(address(escrow), amount);
        }
        escrow.lockWstETH(amount);
        vm.stopPrank();
    }

    function _unlockWstETH(address vetoer) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        uint256 wstETHBalanceBefore = _WST_ETH.balanceOf(vetoer);
        VetoerState memory vetoerStateBefore = escrow.getVetoerState(vetoer);

        vm.startPrank(vetoer);
        uint256 wstETHUnlocked = escrow.unlockWstETH();
        vm.stopPrank();

        // 1 wei rounding issue may arise because of the wrapping stETH into wstETH before
        // sending funds to the user
        assertApproxEqAbs(wstETHUnlocked, vetoerStateBefore.stETHLockedShares, 1);
        assertApproxEqAbs(_WST_ETH.balanceOf(vetoer), wstETHBalanceBefore + vetoerStateBefore.stETHLockedShares, 1);
    }

    function _lockUnstETH(address vetoer, uint256[] memory unstETHIds) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        VetoerState memory vetoerStateBefore = escrow.getVetoerState(vetoer);
        LockedAssetsTotals memory lockedAssetsTotalsBefore = escrow.getLockedAssetsTotals();

        uint256 unstETHTotalSharesLocked = 0;
        WithdrawalRequestStatus[] memory statuses = _WITHDRAWAL_QUEUE.getWithdrawalStatus(unstETHIds);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            unstETHTotalSharesLocked += statuses[i].amountOfShares;
        }

        vm.startPrank(vetoer);
        _WITHDRAWAL_QUEUE.setApprovalForAll(address(escrow), true);
        escrow.lockUnstETH(unstETHIds);
        _WITHDRAWAL_QUEUE.setApprovalForAll(address(escrow), false);
        vm.stopPrank();

        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(_WITHDRAWAL_QUEUE.ownerOf(unstETHIds[i]), address(escrow));
        }

        VetoerState memory vetoerStateAfter = escrow.getVetoerState(vetoer);
        assertEq(vetoerStateAfter.unstETHIdsCount, vetoerStateBefore.unstETHIdsCount + unstETHIds.length);

        LockedAssetsTotals memory lockedAssetsTotalsAfter = escrow.getLockedAssetsTotals();
        assertEq(
            lockedAssetsTotalsAfter.unstETHUnfinalizedShares,
            lockedAssetsTotalsBefore.unstETHUnfinalizedShares + unstETHTotalSharesLocked
        );
    }

    function _unlockUnstETH(address vetoer, uint256[] memory unstETHIds) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        VetoerState memory vetoerStateBefore = escrow.getVetoerState(vetoer);
        LockedAssetsTotals memory lockedAssetsTotalsBefore = escrow.getLockedAssetsTotals();

        uint256 unstETHTotalSharesUnlocked = 0;
        WithdrawalRequestStatus[] memory statuses = _WITHDRAWAL_QUEUE.getWithdrawalStatus(unstETHIds);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            unstETHTotalSharesUnlocked += statuses[i].amountOfShares;
        }

        vm.startPrank(vetoer);
        escrow.unlockUnstETH(unstETHIds);
        vm.stopPrank();

        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(_WITHDRAWAL_QUEUE.ownerOf(unstETHIds[i]), vetoer);
        }

        VetoerState memory vetoerStateAfter = escrow.getVetoerState(vetoer);
        assertEq(vetoerStateAfter.unstETHIdsCount, vetoerStateBefore.unstETHIdsCount - unstETHIds.length);

        // TODO: implement correct assert. It must consider was unstETH finalized or not
        LockedAssetsTotals memory lockedAssetsTotalsAfter = escrow.getLockedAssetsTotals();
        assertEq(
            lockedAssetsTotalsAfter.unstETHUnfinalizedShares,
            lockedAssetsTotalsBefore.unstETHUnfinalizedShares - unstETHTotalSharesUnlocked
        );
    }

    // ---
    // Dual Governance State Manipulation
    // ---
    function _activateNextState() internal {
        _dualGovernance.activateNextState();
    }

    // ---
    // Proposals Submission
    // ---
    function _submitProposal(
        IGovernance governance,
        string memory description,
        ExternalCall[] memory calls
    ) internal returns (uint256 proposalId) {
        uint256 proposalsCountBefore = _timelock.getProposalsCount();

        bytes memory script =
            Utils.encodeEvmCallScript(address(governance), abi.encodeCall(IGovernance.submitProposal, (calls)));
        uint256 voteId = Utils.adoptVote(DAO_VOTING, description, script);

        // The scheduled calls count is the same until the vote is enacted
        assertEq(_timelock.getProposalsCount(), proposalsCountBefore);

        // executing the vote
        Utils.executeVote(DAO_VOTING, voteId);

        proposalId = _timelock.getProposalsCount();
        // new call is scheduled but has not executable yet
        assertEq(proposalId, proposalsCountBefore + 1);
    }

    function _scheduleProposal(IGovernance governance, uint256 proposalId) internal {
        governance.scheduleProposal(proposalId);
    }

    function _executeProposal(uint256 proposalId) internal {
        _timelock.execute(proposalId);
    }

    function _scheduleAndExecuteProposal(IGovernance governance, uint256 proposalId) internal {
        _scheduleProposal(governance, proposalId);
        _executeProposal(proposalId);
    }

    // ---
    // Assertions
    // ---

    function _assertSubmittedProposalData(uint256 proposalId, ExternalCall[] memory calls) internal {
        _assertSubmittedProposalData(proposalId, _timelock.getAdminExecutor(), calls);
    }

    function _assertSubmittedProposalData(uint256 proposalId, address executor, ExternalCall[] memory calls) internal {
        EmergencyProtectedTimelock.Proposal memory proposal = _timelock.getProposal(proposalId);
        assertEq(proposal.id, proposalId, "unexpected proposal id");
        assertEq(proposal.status, ProposalStatus.Submitted, "unexpected status value");
        assertEq(proposal.executor, executor, "unexpected executor");
        assertEq(Timestamp.unwrap(proposal.submittedAt), block.timestamp, "unexpected scheduledAt");
        assertEq(proposal.calls.length, calls.length, "unexpected calls length");

        for (uint256 i = 0; i < proposal.calls.length; ++i) {
            ExternalCall memory expected = calls[i];
            ExternalCall memory actual = proposal.calls[i];

            assertEq(actual.value, expected.value);
            assertEq(actual.target, expected.target);
            assertEq(actual.payload, expected.payload);
        }
    }

    function _assertTargetMockCalls(address sender, ExternalCall[] memory calls) internal {
        TargetMock.Call[] memory called = _target.getCalls();
        assertEq(called.length, calls.length);

        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(called[i].sender, sender);
            assertEq(called[i].value, calls[i].value);
            assertEq(called[i].data, calls[i].payload);
            assertEq(called[i].blockNumber, block.number);
        }
        _target.reset();
    }

    function _assertTargetMockCalls(address[] memory senders, ExternalCall[] memory calls) internal {
        TargetMock.Call[] memory called = _target.getCalls();
        assertEq(called.length, calls.length);
        assertEq(called.length, senders.length);

        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(called[i].sender, senders[i], "Unexpected sender");
            assertEq(called[i].value, calls[i].value, "Unexpected value");
            assertEq(called[i].data, calls[i].payload, "Unexpected payload");
            assertEq(called[i].blockNumber, block.number);
        }
        _target.reset();
    }

    function _assertCanExecute(uint256 proposalId, bool canExecute) internal {
        assertEq(_timelock.canExecute(proposalId), canExecute, "unexpected canExecute() value");
    }

    function _assertCanSchedule(IGovernance governance, uint256 proposalId, bool canSchedule) internal {
        assertEq(governance.canScheduleProposal(proposalId), canSchedule, "unexpected canSchedule() value");
    }

    function _assertCanScheduleAndExecute(IGovernance governance, uint256 proposalId) internal {
        _assertCanSchedule(governance, proposalId, true);
        assertFalse(
            _timelock.isEmergencyProtectionEnabled(),
            "Execution in the same block with scheduling allowed only when emergency protection is disabled"
        );
    }

    function _assertProposalSubmitted(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposal(proposalId).status,
            ProposalStatus.Submitted,
            "TimelockProposal not in 'Submitted' state"
        );
    }

    function _assertProposalScheduled(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposal(proposalId).status,
            ProposalStatus.Scheduled,
            "TimelockProposal not in 'Scheduled' state"
        );
    }

    function _assertProposalExecuted(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposal(proposalId).status,
            ProposalStatus.Executed,
            "TimelockProposal not in 'Executed' state"
        );
    }

    function _assertProposalCancelled(uint256 proposalId) internal {
        assertEq(_timelock.getProposal(proposalId).status, ProposalStatus.Cancelled, "Proposal not in 'Canceled' state");
    }

    function _assertNormalState() internal {
        assertEq(_dualGovernance.getCurrentState(), DGState.Normal);
    }

    function _assertVetoSignalingState() internal {
        assertEq(_dualGovernance.getCurrentState(), DGState.VetoSignalling);
    }

    function _assertVetoSignalingDeactivationState() internal {
        assertEq(_dualGovernance.getCurrentState(), DGState.VetoSignallingDeactivation);
    }

    function _assertRageQuitState() internal {
        assertEq(_dualGovernance.getCurrentState(), DGState.RageQuit);
    }

    function _assertVetoCooldownState() internal {
        assertEq(_dualGovernance.getCurrentState(), DGState.VetoCooldown);
    }

    function _assertNoTargetMockCalls() internal {
        assertEq(_target.getCalls().length, 0, "Unexpected target calls count");
    }

    // ---
    // Logging and Debugging
    // ---
    function _logVetoSignallingState() internal {
        /* solhint-disable no-console */
        (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt) = _getVetoSignallingState();

        if (!isActive) {
            console.log("VetoSignalling state is not active\n");
            return;
        }

        console.log("Veto signalling duration is %d seconds (%s)", duration, _formatDuration(_toDuration(duration)));
        console.log("Veto signalling entered at %d (activated at %d)", enteredAt, activatedAt);
        if (block.timestamp > activatedAt + duration) {
            console.log(
                "Veto signalling has ended %s ago\n",
                _formatDuration(_toDuration(block.timestamp - activatedAt - duration))
            );
        } else {
            console.log(
                "Veto signalling will end after %s\n",
                _formatDuration(_toDuration(activatedAt + duration - block.timestamp))
            );
        }
        /* solhint-enable no-console */
    }

    function _logVetoSignallingDeactivationState() internal {
        /* solhint-disable no-console */
        (bool isActive, uint256 duration, uint256 enteredAt) = _getVetoSignallingDeactivationState();

        if (!isActive) {
            console.log("VetoSignallingDeactivation state is not active\n");
            return;
        }

        console.log(
            "VetoSignallingDeactivation duration is %d seconds (%s)", duration, _formatDuration(_toDuration(duration))
        );
        console.log("VetoSignallingDeactivation entered at %d", enteredAt);
        if (block.timestamp > enteredAt + duration) {
            console.log(
                "VetoSignallingDeactivation has ended %s ago\n",
                _formatDuration(_toDuration(block.timestamp - enteredAt - duration))
            );
        } else {
            console.log(
                "VetoSignallingDeactivation will end after %s\n",
                _formatDuration(_toDuration(enteredAt + duration - block.timestamp))
            );
        }
        /* solhint-enable no-console */
    }

    // ---
    // Test Setup Deployment
    // ---

    function _deployDualGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        Deployment.DualGovernanceSetup memory dgSetup = Deployment.deployDualGovernanceContracts({
            stETH: _ST_ETH,
            wstETH: _WST_ETH,
            withdrawalQueue: _WITHDRAWAL_QUEUE,
            emergencyGovernance: DAO_VOTING
        });
        _adminExecutor = dgSetup.adminExecutor;
        _timelock = dgSetup.timelock;
        _resealManager = dgSetup.resealManager;
        _dualGovernanceConfigProvider = dgSetup.dualGovernanceConfigProvider;
        _dualGovernance = dgSetup.dualGovernance;

        _deployTiebreaker();
        _deployEmergencyActivationCommittee();
        _deployEmergencyExecutionCommittee();
        _finishTimelockSetup(
            address(_dualGovernance), address(dgSetup.emergencyGovernance), isEmergencyProtectionEnabled
        );
    }

    function _deployTimelockedGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        Deployment.DualGovernanceSetup memory dgSetup = Deployment.deployDualGovernanceContracts({
            stETH: _ST_ETH,
            wstETH: _WST_ETH,
            withdrawalQueue: _WITHDRAWAL_QUEUE,
            emergencyGovernance: DAO_VOTING
        });
        _timelockedGovernance = dgSetup.emergencyGovernance;
        _adminExecutor = dgSetup.adminExecutor;
        _timelock = dgSetup.timelock;

        _deployEmergencyActivationCommittee();
        _deployEmergencyExecutionCommittee();
        _finishTimelockSetup(
            address(_timelockedGovernance), address(dgSetup.emergencyGovernance), isEmergencyProtectionEnabled
        );
    }

    function _deployTarget() internal {
        _target = new TargetMock();
    }

    function _deployDualGovernance() internal {
        revert("not implemented");
    }

    function _deployTiebreaker() internal {
        uint256 subCommitteeMembersCount = 5;
        uint256 subCommitteeQuorum = 5;
        uint256 subCommitteesCount = 2;

        _tiebreakerCommittee =
            new TiebreakerCore(address(_adminExecutor), new address[](0), 1, address(_dualGovernance), 0);

        for (uint256 i = 0; i < subCommitteesCount; ++i) {
            address[] memory committeeMembers = new address[](subCommitteeMembersCount);
            for (uint256 j = 0; j < subCommitteeMembersCount; j++) {
                committeeMembers[j] = makeAddr(string(abi.encode(i + j * subCommitteeMembersCount + 65)));
            }
            _tiebreakerSubCommittees.push(
                new TiebreakerSubCommittee(
                    address(_adminExecutor), committeeMembers, subCommitteeQuorum, address(_tiebreakerCommittee)
                )
            );

            vm.prank(address(_adminExecutor));
            _tiebreakerCommittee.addMember(address(_tiebreakerSubCommittees[i]), i + 1);
        }
    }

    function _deployEmergencyActivationCommittee() internal {
        uint256 quorum = 3;
        uint256 membersCount = 5;
        address[] memory committeeMembers = new address[](membersCount);
        for (uint256 i = 0; i < membersCount; ++i) {
            committeeMembers[i] = makeAddr(string(abi.encode(0xFE + i * membersCount + 65)));
        }
        _emergencyActivationCommittee =
            new EmergencyActivationCommittee(address(_adminExecutor), committeeMembers, quorum, address(_timelock));
    }

    function _deployEmergencyExecutionCommittee() internal {
        uint256 quorum = 3;
        uint256 membersCount = 5;
        address[] memory committeeMembers = new address[](membersCount);
        for (uint256 i = 0; i < membersCount; ++i) {
            committeeMembers[i] = makeAddr(string(abi.encode(0xFD + i * membersCount + 65)));
        }
        _emergencyExecutionCommittee =
            new EmergencyExecutionCommittee(address(_adminExecutor), committeeMembers, quorum, address(_timelock));
    }

    function _finishTimelockSetup(
        address governance,
        address emergencyGovernance,
        bool isEmergencyProtectionEnabled
    ) internal {
        _adminExecutor.execute(
            address(_timelock), 0, abi.encodeCall(_timelock.setDelays, (_AFTER_SUBMIT_DELAY, _AFTER_SCHEDULE_DELAY))
        );

        if (isEmergencyProtectionEnabled) {
            _adminExecutor.execute(
                address(_timelock),
                0,
                abi.encodeCall(
                    _timelock.setupEmergencyProtection,
                    (
                        emergencyGovernance,
                        address(_emergencyActivationCommittee),
                        address(_emergencyExecutionCommittee),
                        _EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()),
                        _EMERGENCY_MODE_DURATION
                    )
                )
            );

            assertEq(_timelock.isEmergencyProtectionEnabled(), true);
        }

        vm.prank(DAO_AGENT);
        _WITHDRAWAL_QUEUE.grantRole(
            0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d, address(_resealManager)
        );
        vm.prank(DAO_AGENT);
        _WITHDRAWAL_QUEUE.grantRole(
            0x2fc10cc8ae19568712f7a176fb4978616a610650813c9d05326c34abb62749c7, address(_resealManager)
        );

        if (governance == address(_dualGovernance)) {
            _adminExecutor.execute(
                address(_dualGovernance),
                0,
                abi.encodeCall(_dualGovernance.setTiebreakerCommittee, address(_tiebreakerCommittee))
            );
            _adminExecutor.execute(
                address(_dualGovernance),
                0,
                abi.encodeCall(_dualGovernance.setTiebreakerActivationTimeout, Durations.from(365 days))
            );
            _adminExecutor.execute(
                address(_dualGovernance),
                0,
                abi.encodeCall(_dualGovernance.addTiebreakerSealableWithdrawalBlocker, WITHDRAWAL_QUEUE)
            );
            _adminExecutor.execute(
                address(_dualGovernance),
                0,
                abi.encodeCall(_dualGovernance.registerProposer, (_ADMIN_PROPOSER, address(_adminExecutor)))
            );
        }
        _adminExecutor.execute(address(_timelock), 0, abi.encodeCall(_timelock.setGovernance, (governance)));
        _adminExecutor.transferOwnership(address(_timelock));
    }

    // ---
    // Utils Methods
    // ---

    function _step(string memory text) internal {
        // solhint-disable-next-line
        console.log(string.concat(">>> ", text, " <<<"));
    }

    function _wait(Duration duration) internal {
        vm.warp(duration.addTo(Timestamps.now()).toSeconds());
    }

    function _waitAfterSubmitDelayPassed() internal {
        _wait(_timelock.getAfterSubmitDelay() + ONE_SECOND);
    }

    function _waitAfterScheduleDelayPassed() internal {
        _wait(_timelock.getAfterScheduleDelay() + ONE_SECOND);
    }

    function _executeEmergencyActivate() internal {
        address[] memory members = _emergencyActivationCommittee.getMembers();
        for (uint256 i = 0; i < _emergencyActivationCommittee.quorum(); ++i) {
            vm.prank(members[i]);
            _emergencyActivationCommittee.approveEmergencyActivate();
        }
        _emergencyActivationCommittee.executeEmergencyActivate();
    }

    function _executeEmergencyExecute(uint256 proposalId) internal {
        address[] memory members = _emergencyExecutionCommittee.getMembers();
        for (uint256 i = 0; i < _emergencyExecutionCommittee.quorum(); ++i) {
            vm.prank(members[i]);
            _emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);
        }
        _emergencyExecutionCommittee.executeEmergencyExecute(proposalId);
    }

    function _executeEmergencyReset() internal {
        address[] memory members = _emergencyExecutionCommittee.getMembers();
        for (uint256 i = 0; i < _emergencyExecutionCommittee.quorum(); ++i) {
            vm.prank(members[i]);
            _emergencyExecutionCommittee.approveEmergencyReset();
        }
        _emergencyExecutionCommittee.executeEmergencyReset();
    }

    struct DurationStruct {
        uint256 _days;
        uint256 _hours;
        uint256 _minutes;
        uint256 _seconds;
    }

    function _toDuration(uint256 timestamp) internal view returns (DurationStruct memory duration) {
        duration._days = timestamp / 1 days;
        duration._hours = (timestamp - 1 days * duration._days) / 1 hours;
        duration._minutes = (timestamp - 1 days * duration._days - 1 hours * duration._hours) / 1 minutes;
        duration._seconds = timestamp % 1 minutes;
    }

    function _formatDuration(DurationStruct memory duration) internal pure returns (string memory) {
        // format example: 1d:22h:33m:12s
        return string(
            abi.encodePacked(
                Strings.toString(duration._days),
                "d:",
                Strings.toString(duration._hours),
                "h:",
                Strings.toString(duration._minutes),
                "m:",
                Strings.toString(duration._seconds),
                "s"
            )
        );
    }

    function assertEq(uint40 a, uint40 b) internal {
        assertEq(uint256(a), uint256(b));
    }

    function assertEq(Timestamp a, Timestamp b) internal {
        assertEq(uint256(Timestamp.unwrap(a)), uint256(Timestamp.unwrap(b)));
    }

    function assertEq(Duration a, Duration b) internal {
        assertEq(uint256(Duration.unwrap(a)), uint256(Duration.unwrap(b)));
    }

    function assertEq(ProposalStatus a, ProposalStatus b) internal {
        assertEq(uint256(a), uint256(b));
    }

    function assertEq(ProposalStatus a, ProposalStatus b, string memory message) internal {
        assertEq(uint256(a), uint256(b), message);
    }

    function assertEq(DGState a, DGState b) internal {
        assertEq(uint256(a), uint256(b));
    }

    function assertEq(Balances memory b1, Balances memory b2, uint256 stETHSharesEpsilon) internal {
        assertEq(b1.wstETHShares, b2.wstETHShares);
        assertEq(b1.wstETHAmount, b2.wstETHAmount);

        uint256 stETHAmountEpsilon = _ST_ETH.getPooledEthByShares(stETHSharesEpsilon);
        assertApproxEqAbs(b1.stETHShares, b2.stETHShares, stETHSharesEpsilon);
        assertApproxEqAbs(b1.stETHAmount, b2.stETHAmount, stETHAmountEpsilon);
    }
}
