// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {Durations, Duration as DurationType} from "contracts/types/Duration.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Escrow, VetoerState, LockedAssetsTotals} from "contracts/Escrow.sol";
import {IConfiguration, Configuration} from "contracts/Configuration.sol";
import {Executor} from "contracts/Executor.sol";

import {EmergencyActivationCommittee} from "contracts/committees/EmergencyActivationCommittee.sol";
import {EmergencyExecutionCommittee} from "contracts/committees/EmergencyExecutionCommittee.sol";
import {TiebreakerCore} from "contracts/committees/TiebreakerCore.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

import {ResealManager} from "contracts/ResealManager.sol";

import {
    ExecutorCall,
    EmergencyState,
    EmergencyProtection,
    EmergencyProtectedTimelock
} from "contracts/EmergencyProtectedTimelock.sol";

import {SingleGovernance, IGovernance} from "contracts/SingleGovernance.sol";
import {DualGovernance, DualGovernanceState, State} from "contracts/DualGovernance.sol";

import {Proposal, Status as ProposalStatus} from "contracts/libraries/Proposals.sol";

import {Percents, percents} from "../utils/percents.sol";
import {
    IERC20,
    IStEth,
    IWstETH,
    IWithdrawalQueue,
    WithdrawalRequestStatus,
    IDangerousContract
} from "../utils/interfaces.sol";
import {ExecutorCallHelpers} from "../utils/executor-calls.sol";
import {Utils, TargetMock, console} from "../utils/utils.sol";

import {DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, DAO_AGENT} from "../utils/mainnet-addresses.sol";

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

DurationType constant ONE_SECOND = DurationType.wrap(1);

contract ScenarioTestBlueprint is Test {
    address internal immutable _ADMIN_PROPOSER = DAO_VOTING;
    DurationType internal immutable _EMERGENCY_MODE_DURATION = Durations.from(180 days);
    DurationType internal immutable _EMERGENCY_PROTECTION_DURATION = Durations.from(90 days);
    address internal immutable _EMERGENCY_ACTIVATION_COMMITTEE = makeAddr("EMERGENCY_ACTIVATION_COMMITTEE");
    address internal immutable _EMERGENCY_EXECUTION_COMMITTEE = makeAddr("EMERGENCY_EXECUTION_COMMITTEE");

    DurationType internal immutable _SEALING_DURATION = Durations.from(14 days);
    DurationType internal immutable _SEALING_COMMITTEE_LIFETIME = Durations.from(365 days);
    address internal immutable _SEALING_COMMITTEE = makeAddr("SEALING_COMMITTEE");

    IStEth public immutable _ST_ETH = IStEth(ST_ETH);
    IWstETH public immutable _WST_ETH = IWstETH(WST_ETH);
    IWithdrawalQueue public immutable _WITHDRAWAL_QUEUE = IWithdrawalQueue(WITHDRAWAL_QUEUE);

    EmergencyActivationCommittee internal _emergencyActivationCommittee;
    EmergencyExecutionCommittee internal _emergencyExecutionCommittee;
    TiebreakerCore internal _tiebreakerCommittee;
    TiebreakerSubCommittee[] internal _tiebreakerSubCommittees;

    TargetMock internal _target;

    IConfiguration internal _config;
    IConfiguration internal _configImpl;
    ProxyAdmin internal _configProxyAdmin;
    TransparentUpgradeableProxy internal _configProxy;

    Escrow internal _escrowMasterCopy;

    Executor internal _adminExecutor;

    EmergencyProtectedTimelock internal _timelock;
    SingleGovernance internal _singleGovernance;
    DualGovernance internal _dualGovernance;

    ResealManager internal _resealManager;

    address[] internal _sealableWithdrawalBlockers = [WITHDRAWAL_QUEUE];

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

    function _getTargetRegularStaffCalls() internal view returns (ExecutorCall[] memory) {
        return ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRegularStaff, (42)));
    }

    function _getVetoSignallingState()
        internal
        view
        returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt)
    {
        DurationType duration_;
        Timestamp activatedAt_;
        Timestamp enteredAt_;
        (isActive, duration_, activatedAt_, enteredAt_) = _dualGovernance.getVetoSignallingState();
        duration = DurationType.unwrap(duration_);
        enteredAt = Timestamp.unwrap(enteredAt_);
        activatedAt = Timestamp.unwrap(activatedAt_);
    }

    function _getVetoSignallingDeactivationState()
        internal
        view
        returns (bool isActive, uint256 duration, uint256 enteredAt)
    {
        Timestamp enteredAt_;
        DurationType duration_;
        (isActive, duration_, enteredAt_) = _dualGovernance.getVetoSignallingDeactivationState();
        duration = DurationType.unwrap(duration_);
        enteredAt = Timestamp.unwrap(enteredAt_);
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

        vm.prank(vetoer);
        escrow.unlockUnstETH(unstETHIds);

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
        ExecutorCall[] memory calls
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

    function _assertSubmittedProposalData(uint256 proposalId, ExecutorCall[] memory calls) internal {
        _assertSubmittedProposalData(proposalId, _config.ADMIN_EXECUTOR(), calls);
    }

    function _assertSubmittedProposalData(uint256 proposalId, address executor, ExecutorCall[] memory calls) internal {
        Proposal memory proposal = _timelock.getProposal(proposalId);
        assertEq(proposal.id, proposalId, "unexpected proposal id");
        assertEq(uint256(proposal.status), uint256(ProposalStatus.Submitted), "unexpected status value");
        assertEq(proposal.executor, executor, "unexpected executor");
        assertEq(Timestamp.unwrap(proposal.submittedAt), block.timestamp, "unexpected scheduledAt");
        assertEq(Timestamp.unwrap(proposal.executedAt), 0, "unexpected executedAt");
        assertEq(proposal.calls.length, calls.length, "unexpected calls length");

        for (uint256 i = 0; i < proposal.calls.length; ++i) {
            ExecutorCall memory expected = calls[i];
            ExecutorCall memory actual = proposal.calls[i];

            assertEq(actual.value, expected.value);
            assertEq(actual.target, expected.target);
            assertEq(actual.payload, expected.payload);
        }
    }

    function _assertTargetMockCalls(address sender, ExecutorCall[] memory calls) internal {
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

    function _assertTargetMockCalls(address[] memory senders, ExecutorCall[] memory calls) internal {
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
        assertEq(governance.canSchedule(proposalId), canSchedule, "unexpected canSchedule() value");
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
            _timelock.getProposal(proposalId).status, ProposalStatus.Submitted, "Proposal not in 'Submitted' state"
        );
    }

    function _assertProposalScheduled(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposal(proposalId).status, ProposalStatus.Scheduled, "Proposal not in 'Scheduled' state"
        );
    }

    function _assertProposalExecuted(uint256 proposalId) internal {
        assertEq(_timelock.getProposal(proposalId).status, ProposalStatus.Executed, "Proposal not in 'Executed' state");
    }

    function _assertProposalCanceled(uint256 proposalId) internal {
        assertEq(_timelock.getProposal(proposalId).status, ProposalStatus.Cancelled, "Proposal not in 'Canceled' state");
    }

    function _assertNormalState() internal {
        assertEq(uint256(_dualGovernance.getCurrentState()), uint256(State.Normal));
    }

    function _assertVetoSignalingState() internal {
        assertEq(uint256(_dualGovernance.getCurrentState()), uint256(State.VetoSignalling));
    }

    function _assertVetoSignalingDeactivationState() internal {
        assertEq(uint256(_dualGovernance.getCurrentState()), uint256(State.VetoSignallingDeactivation));
    }

    function _assertRageQuitState() internal {
        assertEq(uint256(_dualGovernance.getCurrentState()), uint256(State.RageQuit));
    }

    function _assertVetoCooldownState() internal {
        assertEq(uint256(_dualGovernance.getCurrentState()), uint256(State.VetoCooldown));
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
        _deployAdminExecutor(address(this));
        _deployConfigImpl();
        _deployConfigProxy(address(this));
        _deployEscrowMasterCopy();
        _deployUngovernedTimelock();
        _deployDualGovernance();
        _deployEmergencyActivationCommittee();
        _deployEmergencyExecutionCommittee();
        _deployTiebreaker();
        _finishTimelockSetup(address(_dualGovernance), isEmergencyProtectionEnabled);
    }

    function _deploySingleGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        _deployAdminExecutor(address(this));
        _deployConfigImpl();
        _deployConfigProxy(address(this));
        _deployEscrowMasterCopy();
        _deployUngovernedTimelock();
        _deploySingleGovernance();
        _deployEmergencyActivationCommittee();
        _deployEmergencyExecutionCommittee();
        _deployTiebreaker();
        _finishTimelockSetup(address(_singleGovernance), isEmergencyProtectionEnabled);
    }

    function _deployTarget() internal {
        _target = new TargetMock();
    }

    function _deployAdminExecutor(address owner) internal {
        _adminExecutor = new Executor(owner);
    }

    function _deployConfigImpl() internal {
        _configImpl = new Configuration(address(_adminExecutor), address(DAO_VOTING), _sealableWithdrawalBlockers);
    }

    function _deployConfigProxy(address owner) internal {
        _configProxy = new TransparentUpgradeableProxy(address(_configImpl), address(owner), new bytes(0));
        _configProxyAdmin = ProxyAdmin(Utils.predictDeployedAddress(address(_configProxy), 1));
        _config = Configuration(address(_configProxy));
    }

    function _deployUngovernedTimelock() internal {
        _timelock = new EmergencyProtectedTimelock(address(_config));
    }

    function _deploySingleGovernance() internal {
        _singleGovernance = new SingleGovernance(address(_config), DAO_VOTING, address(_timelock));
    }

    function _deployDualGovernance() internal {
        _dualGovernance =
            new DualGovernance(address(_config), address(_timelock), address(_escrowMasterCopy), _ADMIN_PROPOSER);
    }

    function _deployEscrowMasterCopy() internal {
        _escrowMasterCopy = new Escrow(ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, address(_config));
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

    function _finishTimelockSetup(address governance, bool isEmergencyProtectionEnabled) internal {
        if (isEmergencyProtectionEnabled) {
            _adminExecutor.execute(
                address(_timelock),
                0,
                abi.encodeCall(
                    _timelock.setEmergencyProtection,
                    (
                        address(_emergencyActivationCommittee),
                        address(_emergencyExecutionCommittee),
                        _EMERGENCY_PROTECTION_DURATION,
                        _EMERGENCY_MODE_DURATION
                    )
                )
            );
        }

        _resealManager = new ResealManager(address(_timelock));

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
                abi.encodeCall(
                    _dualGovernance.setTiebreakerProtection, (address(_tiebreakerCommittee), address(_resealManager))
                )
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

    function _wait(DurationType duration) internal {
        vm.warp(duration.addTo(Timestamps.now()).toSeconds());
    }

    function _waitAfterSubmitDelayPassed() internal {
        _wait(_config.AFTER_SUBMIT_DELAY() + ONE_SECOND);
    }

    function _waitAfterScheduleDelayPassed() internal {
        _wait(_config.AFTER_SCHEDULE_DELAY() + ONE_SECOND);
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

    struct Duration {
        uint256 _days;
        uint256 _hours;
        uint256 _minutes;
        uint256 _seconds;
    }

    function _toDuration(uint256 timestamp) internal view returns (Duration memory duration) {
        duration._days = timestamp / 1 days;
        duration._hours = (timestamp - 1 days * duration._days) / 1 hours;
        duration._minutes = (timestamp - 1 days * duration._days - 1 hours * duration._hours) / 1 minutes;
        duration._seconds = timestamp % 1 minutes;
    }

    function _formatDuration(Duration memory duration) internal pure returns (string memory) {
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

    function assertEq(DurationType a, DurationType b) internal {
        assertEq(uint256(DurationType.unwrap(a)), uint256(DurationType.unwrap(b)));
    }

    function assertEq(ProposalStatus a, ProposalStatus b) internal {
        assertEq(uint256(a), uint256(b));
    }

    function assertEq(ProposalStatus a, ProposalStatus b, string memory message) internal {
        assertEq(uint256(a), uint256(b), message);
    }

    function assertEq(State a, State b) internal {
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
