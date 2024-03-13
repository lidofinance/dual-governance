// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Escrow} from "contracts/Escrow.sol";
import {BurnerVault} from "contracts/BurnerVault.sol";
import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {Configuration} from "contracts/DualGovernanceConfiguration.sol";

import {
    ExecutorCall,
    EmergencyState,
    EmergencyProtection,
    EmergencyProtectedTimelock
} from "contracts/EmergencyProtectedTimelock.sol";

import {SingleGovernanceTimelockController} from "contracts/SingleGovernanceTimelockController.sol";
import {DualGovernanceTimelockController, DualGovernanceStatus} from "contracts/DualGovernanceTimelockController.sol";

import {Proposal} from "contracts/libraries/Proposals.sol";

import {IERC20} from "../utils/interfaces.sol";
import {ExecutorCallHelpers} from "../utils/executor-calls.sol";
import {Utils, TargetMock, console} from "../utils/utils.sol";

import {DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER} from "../utils/mainnet-addresses.sol";

uint256 constant PERCENTS_PRECISION = 16;

function countDigits(uint256 number) pure returns (uint256 digitsCount) {
    do {
        digitsCount++;
    } while (number / 10 != 0);
}

function percents(uint256 integerPart, uint256 fractionalPart) pure returns (uint256) {
    return integerPart * 10 ** PERCENTS_PRECISION
        + fractionalPart * 10 ** (PERCENTS_PRECISION - countDigits(fractionalPart));
}

interface IDangerousContract {
    function doRegularStaff(uint256 magic) external;
    function doRugPool() external;
    function doControversialStaff() external;
}

contract ScenarioTestBlueprint is Test {
    address internal immutable _ADMIN_PROPOSER = DAO_VOTING;
    uint256 internal immutable _EMERGENCY_MODE_DURATION = 180 days;
    uint256 internal immutable _EMERGENCY_PROTECTION_DURATION = 90 days;
    address internal immutable _EMERGENCY_COMMITTEE = makeAddr("EMERGENCY_COMMITTEE");

    uint256 internal immutable _SEALING_DURATION = 14 days;
    uint256 internal immutable _SEALING_COMMITTEE_LIFETIME = 365 days;
    address internal immutable _SEALING_COMMITTEE = makeAddr("SEALING_COMMITTEE");

    address internal immutable _TIEBREAK_COMMITTEE = makeAddr("TIEBREAK_COMMITTEE");

    TargetMock internal _target;

    Configuration internal _config;
    Configuration internal _configImpl;
    ProxyAdmin internal _configProxyAdmin;
    TransparentUpgradeableProxy internal _configProxy;

    Escrow internal _escrowMasterCopy;
    BurnerVault internal _burnerVault;

    OwnableExecutor internal _adminExecutor;

    EmergencyProtectedTimelock internal _timelock;
    SingleGovernanceTimelockController internal _singleGovernanceTimelockController;
    DualGovernanceTimelockController internal _dualGovernanceTimelockController;

    address[] internal _sealableWithdrawalBlockers = [WITHDRAWAL_QUEUE];

    // ---
    // Helper Getters
    // ---
    function _getSignallingEscrow() internal view returns (Escrow) {
        return Escrow(payable(_dualGovernanceTimelockController.signallingEscrow()));
    }

    function _getTargetRegularStaffCalls() internal view returns (ExecutorCall[] memory) {
        return ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRegularStaff, (42)));
    }

    function _getVetoSignallingState()
        internal
        view
        returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt)
    {
        return _dualGovernanceTimelockController.getVetoSignallingState();
    }

    // ---
    // Network Configuration
    // ---
    function _selectFork() internal {
        Utils.selectFork();
    }

    // ---
    // Escrow Manipulation
    // ---
    function _lockStEth(address vetoer, uint256 vetoPowerInPercents) internal {
        Utils.removeLidoStakingLimit();
        Utils.setupStEthWhale(vetoer, vetoPowerInPercents);
        uint256 vetoerBalance = IERC20(ST_ETH).balanceOf(vetoer);

        vm.startPrank(vetoer);
        IERC20(ST_ETH).approve(address(_getSignallingEscrow()), vetoerBalance);
        _getSignallingEscrow().lockStEth(vetoerBalance);
        vm.stopPrank();
    }

    function _unlockStEth(address vetoer) internal {
        vm.startPrank(vetoer);
        _getSignallingEscrow().unlockStEth();
        vm.stopPrank();
    }

    // ---
    // Dual Governance State Manipulation
    // ---
    function _activateNextState() internal {
        _dualGovernanceTimelockController.activateNextState();
    }

    // ---
    // Proposals Submission
    // ---
    function _submitProposal(
        address executor,
        string memory description,
        ExecutorCall[] memory calls
    ) internal returns (uint256 proposalId) {
        uint256 proposalsCountBefore = _timelock.getProposalsCount();

        bytes memory script =
            Utils.encodeEvmCallScript(address(_timelock), abi.encodeCall(_timelock.submit, (executor, calls)));
        uint256 voteId = Utils.adoptVote(DAO_VOTING, description, script);

        // The scheduled calls count is the same until the vote is enacted
        assertEq(_timelock.getProposalsCount(), proposalsCountBefore);

        // executing the vote
        Utils.executeVote(DAO_VOTING, voteId);

        proposalId = _timelock.getProposalsCount();
        // new call is scheduled but has not executable yet
        assertEq(proposalId, proposalsCountBefore + 1);
    }

    function _submitProposal(
        string memory description,
        ExecutorCall[] memory calls
    ) internal returns (uint256 proposalId) {
        proposalId = _submitProposal(_config.ADMIN_EXECUTOR(), description, calls);
    }

    function _scheduleProposal(uint256 proposalId) internal {
        _dualGovernanceTimelockController.scheduleProposal(proposalId);
    }

    function _executeProposal(uint256 proposalId) internal {
        _timelock.execute(proposalId);
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
        assertFalse(proposal.isCanceled, "proposal is canceled");
        assertEq(proposal.executor, executor, "unexpected executor");
        assertEq(proposal.submittedAt, block.timestamp, "unexpected scheduledAt");
        assertEq(proposal.executedAt, 0, "unexpected executedAt");
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

    function _assertCanSchedule(uint256 proposalId, bool canSchedule) internal {
        assertEq(
            _dualGovernanceTimelockController.canSchedule(proposalId), canSchedule, "unexpected canSchedule() value"
        );
    }

    function _assertProposalSubmitted(uint256 proposalId) internal {
        assertTrue(_timelock.isProposalSubmitted(proposalId), "Proposal not in 'Submitted' state");
    }

    function _assertProposalScheduled(uint256 proposalId, bool isExecutable) internal {
        assertTrue(_dualGovernanceTimelockController.isScheduled(proposalId));
    }

    function _assertProposalExecuted(uint256 proposalId) internal {
        assertTrue(_timelock.isProposalExecuted(proposalId), "Proposal not in 'Executed' state");
    }

    function _assertProposalCanceled(uint256 proposalId) internal {
        assertTrue(_timelock.isProposalCanceled(proposalId), "Proposal not in 'Canceled' state");
    }

    function _assertVetoSignalingState() internal {
        assertEq(
            uint256(_dualGovernanceTimelockController.currentState()), uint256(DualGovernanceStatus.VetoSignalling)
        );
    }

    function _assertVetoSignalingDeactivationState() internal {
        assertEq(
            uint256(_dualGovernanceTimelockController.currentState()),
            uint256(DualGovernanceStatus.VetoSignallingDeactivation)
        );
    }

    function _assertRageQuitState() internal {
        assertEq(uint256(_dualGovernanceTimelockController.currentState()), uint256(DualGovernanceStatus.RageQuit));
    }

    function _assertVetoCooldownState() internal {
        assertEq(uint256(_dualGovernanceTimelockController.currentState()), uint256(DualGovernanceStatus.VetoCooldown));
    }

    function _assertNoTargetCalls() internal {
        assertEq(_target.getCalls().length, 0, "Unexpected target calls count");
    }

    // ---
    // Logging and Debugging
    // ---
    function _logVetoSignallingState() internal {
        /* solhint-disable no-console */
        (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt) =
            _dualGovernanceTimelockController.getVetoSignallingState();

        if (!isActive) {
            console.log("VetoSignalling state is not active");
            return;
        }

        console.log("Veto signalling duration is %d seconds (%s)", duration, _formatDuration(_toDuration(duration)));
        console.log("Veto signalling entered at %d (activated at %d)", enteredAt, activatedAt);
        if (block.timestamp > activatedAt + duration) {
            console.log(
                "Veto signalling has ended %s ago",
                _formatDuration(_toDuration(block.timestamp - activatedAt - duration))
            );
        } else {
            console.log(
                "Veto signalling will end after %s",
                _formatDuration(_toDuration(activatedAt + duration - block.timestamp))
            );
        }
        /* solhint-enable no-console */
    }

    function _logVetoSignallingDeactivationState() internal {
        /* solhint-disable no-console */
        (bool isActive, uint256 duration, uint256 enteredAt) =
            _dualGovernanceTimelockController.getVetoSignallingDeactivationState();

        if (!isActive) {
            console.log("VetoSignallingDeactivation state is not active");
            return;
        }

        console.log(
            "VetoSignallingDeactivation duration is %d seconds (%s)", duration, _formatDuration(_toDuration(duration))
        );
        console.log("VetoSignallingDeactivation entered at %d", enteredAt);
        if (block.timestamp > enteredAt + duration) {
            console.log(
                "VetoSignallingDeactivation has ended %s ago",
                _formatDuration(_toDuration(block.timestamp - enteredAt - duration))
            );
        } else {
            console.log(
                "VetoSignallingDeactivation will end after %s",
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
        _deploySingleGovernanceTimelockController();
        _deployConfigImpl();
        _deployConfigProxy(address(this));
        _deployEscrowMasterCopy();
        _deployUngovernedTimelock();
        _deployDualGovernanceTimelockController();
        _finishTimelockSetup(address(_dualGovernanceTimelockController), isEmergencyProtectionEnabled);
    }

    function _deploySingleGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        _deployAdminExecutor(address(this));
        _deploySingleGovernanceTimelockController();
        _deployConfigImpl();
        _deployConfigProxy(address(this));
        _deployEscrowMasterCopy();
        _deployUngovernedTimelock();
        _finishTimelockSetup(address(_singleGovernanceTimelockController), isEmergencyProtectionEnabled);
    }

    function _deployTarget() internal {
        _target = new TargetMock();
    }

    function _deployAdminExecutor(address owner) internal {
        _adminExecutor = new OwnableExecutor(owner);
    }

    function _deployConfigImpl() internal {
        _configImpl = new Configuration(
            address(_adminExecutor), address(_singleGovernanceTimelockController), _sealableWithdrawalBlockers
        );
    }

    function _deployConfigProxy(address owner) internal {
        _configProxy = new TransparentUpgradeableProxy(address(_configImpl), address(owner), new bytes(0));
        _configProxyAdmin = ProxyAdmin(Utils.predictDeployedAddress(address(_configProxy), 1));
        _config = Configuration(address(_configProxy));
    }

    function _deployUngovernedTimelock() internal {
        _timelock = new EmergencyProtectedTimelock(address(_config));
    }

    function _deploySingleGovernanceTimelockController() internal {
        _singleGovernanceTimelockController = new SingleGovernanceTimelockController(DAO_VOTING);
    }

    function _deployDualGovernanceTimelockController() internal {
        _dualGovernanceTimelockController =
            new DualGovernanceTimelockController(address(_config), address(_timelock), address(_escrowMasterCopy));
    }

    function _deployEscrowMasterCopy() internal {
        _burnerVault = new BurnerVault(BURNER, ST_ETH, WST_ETH);
        _escrowMasterCopy = new Escrow(ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, address(_burnerVault));
    }

    function _finishTimelockSetup(address controller, bool isEmergencyProtectionEnabled) internal {
        if (isEmergencyProtectionEnabled) {
            _adminExecutor.execute(
                address(_timelock),
                0,
                abi.encodeCall(
                    _timelock.setEmergencyProtection,
                    (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, _EMERGENCY_MODE_DURATION)
                )
            );
        }
        _adminExecutor.execute(address(_timelock), 0, abi.encodeCall(_timelock.setController, (controller)));
        if (controller == address(_dualGovernanceTimelockController)) {
            _adminExecutor.execute(
                address(_dualGovernanceTimelockController),
                0,
                abi.encodeCall(_dualGovernanceTimelockController.setTiebreakCommittee, (_TIEBREAK_COMMITTEE))
            );
            _adminExecutor.execute(
                address(_dualGovernanceTimelockController),
                0,
                abi.encodeCall(
                    _dualGovernanceTimelockController.registerProposer, (_ADMIN_PROPOSER, address(_adminExecutor))
                )
            );
        }

        _adminExecutor.transferOwnership(address(_timelock));
    }

    // ---
    // Utils Methods
    // ---

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

    function assertEq(DualGovernanceStatus a, DualGovernanceStatus b) internal {
        assertEq(uint256(a), uint256(b));
    }
}
