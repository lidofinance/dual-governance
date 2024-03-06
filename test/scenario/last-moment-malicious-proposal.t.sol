// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {
    Timelock,
    Proposal,
    ExecutorCall,
    DualGovernance,
    DualGovernanceStatus
} from "contracts/ProposersFacadeScratchpad.sol";

import {Escrow} from "contracts/Escrow.sol";
import {BurnerVault} from "contracts/BurnerVault.sol";
import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {Configuration} from "contracts/DualGovernanceConfiguration.sol";

import {IERC20} from "../utils/interfaces.sol";
import {Utils, TargetMock} from "../utils/utils.sol";
import {ExecutorCallHelpers} from "../utils/executor-calls.sol";

import {DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER} from "../utils/mainnet-addresses.sol";

interface IDangerousContract {
    function doRegularStaff(uint256 magic) external;
    function doRugPool() external;
    function doControversialStaff() external;
}

contract LastMomentMaliciousProposal is Test {
    address private immutable _ADMIN_PROPOSER = DAO_VOTING;
    address private immutable _EMERGENCY_GOVERNANCE = DAO_VOTING;

    uint256 private immutable _EMERGENCY_MODE_DURATION = 180 days;
    uint256 private immutable _EMERGENCY_PROTECTION_DURATION = 90 days;
    address private immutable _EMERGENCY_COMMITTEE = makeAddr("EMERGENCY_COMMITTEE");

    address internal immutable _TIEBREAK_COMMITTEE = makeAddr("TIEBREAK_COMMITTEE");

    TargetMock private _target;
    Timelock private _timelock;
    Configuration private _config;
    DualGovernance private _dualGovernance;

    address[] private _sealableWithdrawalBlockers = [WITHDRAWAL_QUEUE];

    function setUp() external {
        Utils.selectFork();

        _target = new TargetMock();

        // deploy admin executor
        OwnableExecutor adminExecutor = new OwnableExecutor(address(this));

        // deploy configuration implementation
        Configuration configImpl =
            new Configuration(address(adminExecutor), _EMERGENCY_GOVERNANCE, _sealableWithdrawalBlockers);
        TransparentUpgradeableProxy configProxy =
            new TransparentUpgradeableProxy(address(configImpl), address(this), new bytes(0));
        _config = Configuration(address(configProxy));

        _timelock = new Timelock(address(_config));

        // deploy dual governance
        BurnerVault burnerVault = new BurnerVault(BURNER, ST_ETH, WST_ETH);
        Escrow escrowMasterCopy = new Escrow(address(0), ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, address(burnerVault));
        _dualGovernance =
            new DualGovernance(address(_config), address(_timelock), address(escrowMasterCopy), _ADMIN_PROPOSER);

        // setup the timelock with controller and governance
        adminExecutor.execute(
            address(_timelock), 0, abi.encodeCall(_timelock.setGovernance, (address(_dualGovernance)))
        );

        adminExecutor.execute(
            address(_timelock), 0, abi.encodeCall(_timelock.setTiebreakCommittee, (_TIEBREAK_COMMITTEE))
        );

        adminExecutor.execute(
            address(_timelock),
            0,
            abi.encodeCall(
                _timelock.setEmergencyProtection,
                (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, _EMERGENCY_MODE_DURATION)
            )
        );

        adminExecutor.execute(
            address(_timelock), 0, abi.encodeCall(_timelock.setController, (address(_dualGovernance)))
        );

        adminExecutor.transferOwnership(address(_timelock));
    }

    function testFork_LastMomentMaliciousProposal() external {
        bytes memory regularStaffCalldata = abi.encodeCall(IDangerousContract.doRegularStaff, (42));
        ExecutorCall[] memory regularStaffCalls = ExecutorCallHelpers.create(address(_target), regularStaffCalldata);

        uint256 proposalId;
        // ---
        // ACT 1. DAO SUBMITS PROPOSAL WITH REGULAR STAFF
        // ---
        {
            proposalId = _submitProposalToDualGovernance(
                "DAO does regular staff on potentially dangerous contract", regularStaffCalls
            );
            // the call isn't executable until the delay has passed
            assertFalse(_timelock.canSchedule(proposalId));
            assertFalse(_timelock.canExecuteScheduled(proposalId));
            assertFalse(_timelock.canExecuteSubmitted(proposalId));
        }

        // ---
        // ACT 2. MALICIOUS ACTOR STARTS ACQUIRE VETO SIGNALLING DURATION
        // ---
        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        Escrow escrow = Escrow(payable(_dualGovernance.signallingEscrow()));
        {
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(maliciousActor, 12 * 10 ** 16);
            uint256 maliciousActorBalance = IERC20(ST_ETH).balanceOf(maliciousActor);

            vm.startPrank(maliciousActor);
            IERC20(ST_ETH).approve(address(escrow), maliciousActorBalance);
            escrow.lockStEth(maliciousActorBalance);
            vm.stopPrank();
            assertEq(uint256(_dualGovernance.currentState()), uint256(DualGovernanceStatus.VetoSignalling));

            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2 + 1);

            assertFalse(_timelock.canSchedule(proposalId));
            assertFalse(_timelock.canExecuteScheduled(proposalId));
            assertFalse(_timelock.canExecuteSubmitted(proposalId));

            vm.warp(block.timestamp + 18 days);
            _dualGovernance.activateNextState();
            assertEq(uint256(_dualGovernance.currentState()), uint256(DualGovernanceStatus.VetoSignalling));
        }

        // ---
        // ACT 3. MALICIOUS ACTOR SUBMITS MALICIOUS PROPOSAL
        // ---
        uint256 maliciousProposalId;
        {
            maliciousProposalId = _submitProposalToDualGovernance(
                "Malicious Proposal",
                ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()))
            );

            // the call isn't executable until the delay has passed
            assertFalse(_timelock.canSchedule(proposalId));
            assertFalse(_timelock.canExecuteScheduled(proposalId));
            assertFalse(_timelock.canExecuteSubmitted(proposalId));
        }

        // ---
        // ACT 4. MALICIOUS ACTOR UNLOCK FUNDS FROM ESCROW
        // ---
        {
            vm.prank(maliciousActor);
            escrow.unlockStEth();

            assertEq(uint256(_dualGovernance.currentState()), uint256(DualGovernanceStatus.VetoSignallingDeactivation));
        }

        // ---
        // ACT 5. STETH HOLDERS TRY ACQUIRE QUORUM, DURING THE DEACTIVATION PERIOD BUT UNSUCCESSFULLY
        // ---
        address stEthWhale = makeAddr("STETH_WHALE");
        {
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(stEthWhale, 10 * 10 ** 16);
            uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

            vm.startPrank(stEthWhale);
            IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
            escrow.lockStEth(stEthWhaleBalance);
            vm.stopPrank();
            assertEq(uint256(_dualGovernance.currentState()), uint256(DualGovernanceStatus.VetoSignallingDeactivation));
        }

        // ---
        // ACT 6. BUT THE DEACTIVATION PHASE IS PROLONGED BECAUSE THE MALICIOUS VOTE
        //        WAS SUBMITTED ON VETO SIGNALLING PHASE
        // ---
        {
            vm.warp(block.timestamp + _config.SIGNALLING_DEACTIVATION_DURATION() + 1);

            // the veto signalling deactivation duration is passed, but proposal will be executed
            // only when the _config.SIGNALLING_MIN_PROPOSAL_REVIEW_DURATION() from the last proposal
            // submission is passed.
            _dualGovernance.activateNextState();
            assertEq(uint256(_dualGovernance.currentState()), uint256(DualGovernanceStatus.VetoSignallingDeactivation));

            vm.warp(block.timestamp + _config.SIGNALLING_MIN_PROPOSAL_REVIEW_DURATION() / 2);

            // stEth holders reach the rage quit threshold
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(stEthWhale, 10 * 10 ** 16);
            uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

            vm.startPrank(stEthWhale);
            IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
            escrow.lockStEth(stEthWhaleBalance);
            _dualGovernance.activateNextState();

            // the dual governance immediately transfers to the Rage Quit state
            assertEq(uint256(_dualGovernance.currentState()), uint256(DualGovernanceStatus.RageQuit));

            // the malicious call still not executable
            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));
        }
    }

    function testFork_VetoSignallingDeactivationDefaultDuration() external {
        bytes memory regularStaffCalldata = abi.encodeCall(IDangerousContract.doRegularStaff, (42));
        ExecutorCall[] memory regularStaffCalls = ExecutorCallHelpers.create(address(_target), regularStaffCalldata);

        uint256 proposalId;
        // ---
        // ACT 1. DAO SUBMITS CONTROVERSIAL PROPOSAL
        // ---
        {
            proposalId = _submitProposalToDualGovernance(
                "DAO does regular staff on potentially dangerous contract", regularStaffCalls
            );
            // the call isn't executable until the delay has passed
            assertFalse(_timelock.canSchedule(proposalId));
            assertFalse(_timelock.canExecuteScheduled(proposalId));
            assertFalse(_timelock.canExecuteSubmitted(proposalId));
        }

        // ---
        // ACT 2. MALICIOUS ACTOR ACCUMULATES FIRST THRESHOLD OF STETH IN THE ESCROW
        // ---
        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        Escrow escrow = Escrow(payable(_dualGovernance.signallingEscrow()));
        {
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(maliciousActor, _config.FIRST_SEAL_THRESHOLD() + 1);
            uint256 maliciousActorBalance = IERC20(ST_ETH).balanceOf(maliciousActor);

            vm.startPrank(maliciousActor);
            IERC20(ST_ETH).approve(address(escrow), maliciousActorBalance);
            escrow.lockStEth(maliciousActorBalance);
            vm.stopPrank();
            assertEq(uint256(_dualGovernance.currentState()), uint256(DualGovernanceStatus.VetoSignalling));

            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2 + 1);

            assertFalse(_timelock.canSchedule(proposalId));
            assertFalse(_timelock.canExecuteScheduled(proposalId));
            assertFalse(_timelock.canExecuteSubmitted(proposalId));

            vm.warp(block.timestamp + _config.SIGNALLING_MIN_DURATION() + 1);
            _dualGovernance.activateNextState();
            assertEq(uint256(_dualGovernance.currentState()), uint256(DualGovernanceStatus.VetoSignallingDeactivation));
        }

        // ---
        // ACT 3. THE VETO SIGNALLING DEACTIVATION DURATION EQUALS TO "SIGNALLING_DEACTIVATION_DURATION" DAYS
        // ---
        {
            vm.warp(block.timestamp + _config.SIGNALLING_DEACTIVATION_DURATION() + 1);
            _dualGovernance.activateNextState();
            assertEq(uint256(_dualGovernance.currentState()), uint256(DualGovernanceStatus.VetoCooldown));

            // and proposal can be scheduled and executed
            assertTrue(_timelock.canSchedule(proposalId));
            assertFalse(_timelock.canExecuteScheduled(proposalId));
            assertFalse(_timelock.canExecuteSubmitted(proposalId));
        }
    }

    function _submitProposalToDualGovernance(
        string memory description,
        ExecutorCall[] memory calls
    ) internal returns (uint256 proposalId) {
        uint256 proposalsCountBefore = _timelock.getProposalsCount();

        bytes memory script =
            Utils.encodeEvmCallScript(address(_dualGovernance), abi.encodeCall(_dualGovernance.submit, (calls)));
        uint256 voteId = Utils.adoptVote(DAO_VOTING, description, script);

        // The scheduled calls count is the same until the vote is enacted
        assertEq(_timelock.getProposalsCount(), proposalsCountBefore);

        // executing the vote
        Utils.executeVote(DAO_VOTING, voteId);

        proposalId = _timelock.getProposalsCount();
        // new call is scheduled but has not executable yet
        assertEq(proposalId, proposalsCountBefore + 1);
        _assertSubmittedProposal(proposalId, _config.ADMIN_EXECUTOR(), calls);
    }

    function _assertSubmittedProposal(uint256 proposalId, address executor, ExecutorCall[] memory calls) internal {
        Proposal memory proposal = _timelock.getProposal(proposalId);
        assertEq(proposal.id, proposalId, "unexpected proposal id");
        // assertFalse(proposal.isCanceled, "proposal is canceled");
        assertEq(proposal.executor, executor, "unexpected executor");
        assertEq(proposal.proposedAt, block.timestamp, "unexpected scheduledAt");
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
}
