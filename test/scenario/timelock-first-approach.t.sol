// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Configuration} from "contracts/Configuration.sol";
import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {
    Timelock,
    EmergencyModeGuardian,
    ExecutorCall,
    Proposal,
    Proposals,
    ResetTimelockControllerGuardian,
    GovernanceState,
    TiebreakGuardian,
    GateSeal
} from "contracts/TimelockFirstApproachScratchpad.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";

import {Utils, TargetMock} from "../utils/utils.sol";
import {ExecutorCallHelpers} from "../utils/executor-calls.sol";
import {IWithdrawalQueue, IERC20} from "../utils/interfaces.sol";
import {DAO_AGENT, DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER} from "../utils/mainnet-addresses.sol";

interface IDangerousContract {
    function doRegularStaff(uint256 magic) external;
    function doRugPool() external;
    function doControversialStaff() external;
}

contract AgentFirstApproachTest is Test {
    address internal constant _ADMIN_PROPOSER = DAO_VOTING;
    uint256 internal constant _DELAY = 3 days;
    uint256 internal constant _EMERGENCY_COMMITTEE_LIFETIME = 90 days;
    uint256 internal constant _EMERGENCY_MODE_DURATION = 180 days;
    uint256 internal immutable _SEALING_DURATION = 14 days;
    uint256 internal immutable _SEALING_COMMITTEE_LIFETIME = 365 days;

    address internal immutable _SEALING_COMMITTEE = makeAddr("SEALING_COMMITTEE");
    address internal immutable _TIEBREAK_COMMITTEE = makeAddr("TIEBREAK_COMMITTEE");
    address internal immutable _EMERGENCY_COMMITTEE = makeAddr("EMERGENCY_COMMITTEE");

    TargetMock private _target;
    Timelock internal _timelock;

    GovernanceState internal _govState;
    Configuration internal _config;

    EmergencyModeGuardian internal _emergencyModeGuardian;

    GateSeal private _gateSeal;
    address[] private _sealables;

    function setUp() external {
        Utils.selectFork();

        _sealables.push(WITHDRAWAL_QUEUE);
        _target = new TargetMock();

        OwnableExecutor adminExecutor = new OwnableExecutor(address(this));
        _timelock = new Timelock(_ADMIN_PROPOSER, address(adminExecutor), _DELAY);

        // deploy emergency mode guardian
        _emergencyModeGuardian = new EmergencyModeGuardian(
            address(_timelock), _EMERGENCY_COMMITTEE, _EMERGENCY_COMMITTEE_LIFETIME, _EMERGENCY_MODE_DURATION
        );

        adminExecutor.execute(
            address(_timelock),
            0,
            abi.encodeCall(_timelock.grantRole, (_timelock.GUARDIAN_ROLE(), address(_emergencyModeGuardian)))
        );

        adminExecutor.transferOwnership(address(_timelock));
    }

    function testFork_ProofOfConcept() external {
        bytes memory regularStaffCalldata = abi.encodeCall(IDangerousContract.doRegularStaff, (42));
        ExecutorCall[] memory regularStaffCalls = ExecutorCallHelpers.create(address(_target), regularStaffCalldata);

        // ---
        // ACT 1. 📈 DAO OPERATES AS USUALLY
        // ---
        {
            uint256 proposalId = _scheduleViaVoting(
                "DAO does regular staff on potentially dangerous contract",
                _timelock.ADMIN_EXECUTOR(),
                regularStaffCalls
            );

            // wait until scheduled call becomes executable
            _waitFor(proposalId);

            // call successfully executed
            _timelock.execute(1);
            _assertTargetMockCalls(_timelock.ADMIN_EXECUTOR(), regularStaffCalls);
        }

        // ---
        // ACT 2. 😱 DAO IS UNDER ATTACK
        // ---
        uint256 maliciousProposalId;
        {
            // Malicious vote was proposed by the attacker with huge LDO wad (but still not the majority)
            ExecutorCall[] memory maliciousCalls =
                ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()));

            maliciousProposalId = _scheduleViaVoting("Rug Pool attempt", _timelock.ADMIN_EXECUTOR(), maliciousCalls);

            // the call isn't executable until the delay has passed
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));

            // some time required to assemble the emergency committee and activate emergency mode
            vm.warp(block.timestamp + _DELAY / 2);

            // malicious call still not executable
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));
            vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotExecutable.selector, maliciousProposalId));
            _timelock.execute(maliciousProposalId);

            // emergency committee activates emergency mode
            vm.prank(_EMERGENCY_COMMITTEE);
            _emergencyModeGuardian.activateEmergencyMode();

            // emergency mode was successfully activated
            uint256 expectedEmergencyModeEndTimestamp = block.timestamp + _EMERGENCY_MODE_DURATION;
            assertEq(_emergencyModeGuardian.getEmergencyModeEndsAfter(), expectedEmergencyModeEndTimestamp);

            // now only emergency committee may execute scheduled calls
            vm.warp(block.timestamp + _DELAY / 2 + 1);
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));
            vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
            _timelock.execute(maliciousProposalId);
        }

        // ---
        // ACT 3. 🔫 DAO STRIKES BACK (WITH DUAL GOVERNANCE SHIPMENT)
        // ---
        GovernanceState govState;
        ResetTimelockControllerGuardian resetTimelockControllerGuardian;
        EmergencyModeGuardian emergencyModeGuardian;
        TiebreakGuardian tiebreakGuardian;
        {
            // Lido contributors work hard to implement and ship the Dual Governance mechanism
            // before the emergency mode is over
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);

            // Time passes but malicious proposal still on hold
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));

            // Dual Governance delay strategy is deployed into mainnet
            (govState, resetTimelockControllerGuardian, emergencyModeGuardian, tiebreakGuardian) =
                _deployDualGovernance();

            address timelock = address(_timelock);
            ExecutorCall[] memory dualGovernanceLaunchCalls = ExecutorCallHelpers.create(
                [address(_emergencyModeGuardian), timelock, timelock, timelock, timelock, timelock, timelock],
                [
                    // 1. deactivate emergency mode
                    abi.encodeCall(_emergencyModeGuardian.deactivateEmergencyMode, ()),
                    // 2. set controller for the timelock
                    abi.encodeCall(_timelock.setController, (address(govState))),
                    // 3. grant GUARDIAN_ROLE to the resetTimelockControllerGuardian
                    abi.encodeCall(
                        _timelock.grantRole, (_timelock.GUARDIAN_ROLE(), address(resetTimelockControllerGuardian))
                    ),
                    // 4. grant MANAGER_ROLE to the resetTimelockControllerGuardian
                    abi.encodeCall(
                        _timelock.grantRole, (_timelock.CONTROLLER_MANAGER_ROLE(), address(resetTimelockControllerGuardian))
                    ),
                    // 5. grant GUARDIAN_ROLE to the new EmergencyModeGuardian
                    abi.encodeCall(_timelock.grantRole, (_timelock.GUARDIAN_ROLE(), address(emergencyModeGuardian))),
                    // 6. grant GUARDIAN_ROLE to the TiebreakGuardian
                    abi.encodeCall(_timelock.grantRole, (_timelock.GUARDIAN_ROLE(), address(tiebreakGuardian))),
                    // 7. revoke GUARDIAN_ROLE from the old EmergencyModeGuardian
                    abi.encodeCall(_timelock.revokeRole, (_timelock.GUARDIAN_ROLE(), address(_emergencyModeGuardian)))
                ]
            );

            // The vote to launch Dual Governance is launched and reached the quorum (the major part of LDO holder still have power)
            uint256 dualGovernanceLunchProposalId =
                _scheduleViaVoting("Launch the Dual Governance", _timelock.ADMIN_EXECUTOR(), dualGovernanceLaunchCalls);

            // Anticipated vote will be executed soon...
            vm.warp(block.timestamp + _DELAY + 1);

            // The malicious vote still on hold
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));

            // Emergency Committee executes vote and enables Dual Governance
            vm.prank(_EMERGENCY_COMMITTEE);
            _emergencyModeGuardian.execute(dualGovernanceLunchProposalId);

            assertFalse(_timelock.getIsExecutable(maliciousProposalId));
        }

        // ---
        // ACT 4 - DUAL GOVERNANCE WORKS PROPERLY (VETO SIGNALING CASE)
        // ---
        {
            uint256 snapshotId = vm.snapshot();
            ExecutorCall[] memory controversialCalls = ExecutorCallHelpers.create(
                address(_target), abi.encodeCall(IDangerousContract.doControversialStaff, ())
            );

            uint256 controversialProposalId =
                _scheduleViaVoting("Do some controversial staff", _timelock.ADMIN_EXECUTOR(), controversialCalls);

            vm.warp(block.timestamp + _DELAY / 2);

            assertFalse(_timelock.getIsExecutable(controversialProposalId));

            // dual governance escrow accumulates
            address stEthWhale = makeAddr("STETH_WHALE");
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(stEthWhale, 5 * 10 ** 16);
            uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

            Escrow escrow = Escrow(payable(govState.signallingEscrow()));
            vm.startPrank(stEthWhale);
            IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
            escrow.lockStEth(stEthWhaleBalance);
            vm.stopPrank();
            assertEq(uint256(govState.currentState()), uint256(GovernanceState.State.VetoSignalling));

            vm.warp(block.timestamp + _DELAY / 2 + 1);

            assertFalse(_timelock.getIsExecutable(controversialProposalId));

            // wait the dual governance returns to normal state
            vm.warp(block.timestamp + 14 days);
            govState.activateNextState();
            assertEq(uint256(govState.currentState()), uint256(GovernanceState.State.VetoSignallingDeactivation));
            vm.warp(block.timestamp + govState.CONFIG().signallingDeactivationDuration() + 1);
            govState.activateNextState();
            assertEq(uint256(govState.currentState()), uint256(GovernanceState.State.VetoCooldown));

            assertTrue(_timelock.getIsExecutable(controversialProposalId));

            // execute controversial decision
            _timelock.execute(controversialProposalId);
            _assertTargetMockCalls(_timelock.ADMIN_EXECUTOR(), controversialCalls);
            vm.revertTo(snapshotId);
        }

        // ---
        // ACT 5. RESET DELAY STRATEGY
        // ---
        {
            uint256 snapshotId = vm.snapshot();
            assertEq(_timelock.getController(), address(govState));
            vm.prank(_EMERGENCY_COMMITTEE);
            resetTimelockControllerGuardian.resetController();
            assertEq(_timelock.getController(), address(0));
            assertFalse(_timelock.hasRole(_timelock.GUARDIAN_ROLE(), address(resetTimelockControllerGuardian)));

            // emergency committee still may activate emergency mode
            assertFalse(_timelock.paused());
            vm.prank(_EMERGENCY_COMMITTEE);
            emergencyModeGuardian.activateEmergencyMode();

            assertTrue(_timelock.paused());
            // when the emergency period passed, anyone can deactivate emergency mode
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION + 1);
            emergencyModeGuardian.deactivateEmergencyMode();
            assertFalse(_timelock.paused());
            vm.revertTo(snapshotId);
        }

        // ---
        // ACT 6. TIEBREAK COMMITTEE FLOW
        // ---
        {
            uint256 snapshotId = vm.snapshot();

            // some regular proposal is launched
            uint256 proposalId = _scheduleViaVoting(
                "DAO does regular staff on potentially dangerous contract",
                _timelock.ADMIN_EXECUTOR(),
                regularStaffCalls
            );

            address stEthWhale = makeAddr("STETH_WHALE");
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(stEthWhale, 20 * 10 ** 16);
            uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

            Escrow escrow = Escrow(payable(govState.signallingEscrow()));
            vm.startPrank(stEthWhale);
            IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
            escrow.lockStEth(stEthWhaleBalance);
            vm.stopPrank();
            assertEq(uint256(govState.currentState()), uint256(GovernanceState.State.VetoSignalling));

            // before the RageQuit phase is entered tiebreak committee can't execute decisions
            vm.prank(_TIEBREAK_COMMITTEE);
            vm.expectRevert(TiebreakGuardian.DualGovernanceNotBlocked.selector);
            tiebreakGuardian.execute(proposalId);

            vm.warp(block.timestamp + govState.CONFIG().signallingMaxDuration() + 1);

            govState.activateNextState();
            assertEq(uint256(govState.currentState()), uint256(GovernanceState.State.RageQuit));

            // activate gate seal to enter deadlock
            vm.prank(_SEALING_COMMITTEE);
            _gateSeal.seal(_sealables);

            assertTrue(tiebreakGuardian.canExecute());
            assertTrue(tiebreakGuardian.isRageQuitAndGateSealTriggered());
            assertFalse(tiebreakGuardian.isDualGovernanceLocked());

            // proposal is not executable
            _timelock.getIsExecutable(proposalId);

            // now tiebreak committee may execute any dao decision
            vm.prank(_TIEBREAK_COMMITTEE);
            tiebreakGuardian.execute(proposalId);
            _assertTargetMockCalls(_timelock.ADMIN_EXECUTOR(), regularStaffCalls);

            vm.revertTo(snapshotId);
        }
    }

    function _scheduleViaVoting(
        string memory description,
        address executor,
        ExecutorCall[] memory calls
    ) internal returns (uint256 proposalId) {
        uint256 proposalsCountBefore = _timelock.getProposalsCount();

        bytes memory script = Utils.encodeEvmCallScript(address(_timelock), abi.encodeCall(_timelock.schedule, (calls)));
        uint256 voteId = Utils.adoptVote(DAO_VOTING, description, script);

        // The scheduled calls count is the same until the vote is enacted
        assertEq(_timelock.getProposalsCount(), proposalsCountBefore);

        // executing the vote
        Utils.executeVote(DAO_VOTING, voteId);

        proposalId = _timelock.getProposalsCount();
        // new call is scheduled but has not executable yet
        assertEq(proposalId, proposalsCountBefore + 1);
        _assertScheduledProposal(proposalId, executor, calls);
    }

    function _assertScheduledProposal(uint256 proposalId, address executor, ExecutorCall[] memory calls) internal {
        Proposal memory proposal = _timelock.getProposal(proposalId);
        assertEq(proposal.id, proposalId, "unexpected proposal id");
        // assertFalse(proposal.isCanceled, "proposal is canceled");
        assertEq(proposal.executor, executor, "unexpected executor");
        assertEq(proposal.scheduledAt, block.timestamp, "unexpected scheduledAt");
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

    function _assertTargetMockCalls(address executor, ExecutorCall[] memory calls) internal {
        TargetMock.Call[] memory called = _target.getCalls();
        assertEq(called.length, calls.length);

        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(called[i].sender, executor);
            assertEq(called[i].value, calls[i].value);
            assertEq(called[i].data, calls[i].payload);
            assertEq(called[i].blockNumber, block.number);
        }
        _target.reset();
    }

    function _waitFor(uint256 proposalId) internal {
        // the call is not executable until the delay has passed
        assertFalse(_timelock.getIsExecutable(proposalId), "proposal is executable");

        // wait until scheduled call becomes executable
        vm.warp(block.timestamp + _DELAY + 1);
        assertTrue(_timelock.getIsExecutable(proposalId), "proposal is not executable");
    }

    function _deployDualGovernance()
        internal
        returns (
            GovernanceState govState,
            ResetTimelockControllerGuardian resetTimelockControllerGuardian,
            EmergencyModeGuardian emergencyModeGuardian,
            TiebreakGuardian tiebreakGuardian
        )
    {
        // deploy initial config impl
        address configImpl = address(new Configuration(_ADMIN_PROPOSER));

        // deploy config proxy
        ProxyAdmin configAdmin = new ProxyAdmin(address(this));
        TransparentUpgradeableProxy config =
            new TransparentUpgradeableProxy(configImpl, address(configAdmin), new bytes(0));

        // deploy DG
        address escrowImpl = address(new Escrow(address(config), ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER));

        govState = new GovernanceState(address(config), address(0), escrowImpl);

        // deploy guardians
        resetTimelockControllerGuardian =
            new ResetTimelockControllerGuardian(address(_timelock), _EMERGENCY_COMMITTEE, _EMERGENCY_COMMITTEE_LIFETIME);

        emergencyModeGuardian = new EmergencyModeGuardian(
            address(_timelock), _EMERGENCY_COMMITTEE, _EMERGENCY_COMMITTEE_LIFETIME, _EMERGENCY_MODE_DURATION
        );

        _deployGateSeal(address(govState));
        tiebreakGuardian =
            new TiebreakGuardian(address(_timelock), address(_gateSeal), address(govState), _TIEBREAK_COMMITTEE);
    }

    function _deployGateSeal(address govState) internal {
        // deploy new gate seal instance
        _gateSeal =
            new GateSeal(govState, _SEALING_COMMITTEE, _SEALING_COMMITTEE_LIFETIME, _SEALING_DURATION, _sealables);

        // grant rights to gate seal to pause/resume the withdrawal queue
        vm.startPrank(DAO_AGENT);
        IWithdrawalQueue(WITHDRAWAL_QUEUE).grantRole(
            IWithdrawalQueue(WITHDRAWAL_QUEUE).PAUSE_ROLE(), address(_gateSeal)
        );
        IWithdrawalQueue(WITHDRAWAL_QUEUE).grantRole(
            IWithdrawalQueue(WITHDRAWAL_QUEUE).RESUME_ROLE(), address(_gateSeal)
        );
        vm.stopPrank();
    }
}
