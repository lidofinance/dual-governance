// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {percents, ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";

import {GateSealMock} from "../mocks/GateSealMock.sol";
import {ResealExecutor} from "contracts/ResealExecutor.sol";
import {ResealCommittee} from "contracts/committees/ResealCommittee.sol";
import {IGateSeal} from "contracts/interfaces/IGateSeal.sol";

import {DAO_AGENT} from "../utils/mainnet-addresses.sol";

contract ResealExecutorScenarioTest is ScenarioTestBlueprint {
    uint256 private immutable _RELEASE_DELAY = 5 days;
    uint256 private immutable _SEAL_DURATION = 14 days;
    uint256 private constant _PAUSE_INFINITELY = type(uint256).max;

    address private immutable _VETOER = makeAddr("VETOER");

    IGateSeal private _gateSeal;
    address[] private _sealables;
    ResealExecutor private _resealExecutor;
    ResealCommittee private _resealCommittee;

    uint256 private _resealCommitteeMembersCount = 5;
    uint256 private _resealCommitteeQuorum = 3;
    address[] private _resealCommitteeMembers = new address[](0);

    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);

        _sealables.push(address(_WITHDRAWAL_QUEUE));

        _gateSeal = new GateSealMock(_SEAL_DURATION, _SEALING_COMMITTEE_LIFETIME);

        _resealExecutor = new ResealExecutor(address(this), address(_dualGovernance), address(this));
        for (uint256 i = 0; i < _resealCommitteeMembersCount; i++) {
            _resealCommitteeMembers.push(makeAddr(string(abi.encode(i + 65))));
        }
        _resealCommittee = new ResealCommittee(
            address(this), _resealCommitteeMembers, _resealCommitteeQuorum, address(_resealExecutor)
        );

        _resealExecutor.setResealCommittee(address(_resealCommittee));

        // grant rights to gate seal to pause/resume the withdrawal queue
        vm.startPrank(DAO_AGENT);
        _WITHDRAWAL_QUEUE.grantRole(_WITHDRAWAL_QUEUE.PAUSE_ROLE(), address(_gateSeal));
        _WITHDRAWAL_QUEUE.grantRole(_WITHDRAWAL_QUEUE.PAUSE_ROLE(), address(_resealExecutor));
        _WITHDRAWAL_QUEUE.grantRole(_WITHDRAWAL_QUEUE.RESUME_ROLE(), address(_resealExecutor));
        vm.stopPrank();
    }

    function testFork_resealingWithLockedGovernance() external {
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
        _assertNormalState();

        _lockStETH(_VETOER, percents("10.0"));
        _assertVetoSignalingState();

        // sealing committee seals Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // validate Withdrawal Queue was paused
        assertTrue(_WITHDRAWAL_QUEUE.isPaused());

        // validate the dual governance still in the veto signaling state
        _assertVetoSignalingState();

        //Committee votes for resealing WQ
        for (uint256 i = 0; i < _resealCommitteeQuorum; i++) {
            vm.prank(_resealCommitteeMembers[i]);
            _resealCommittee.voteReseal(_sealables, true);
        }
        (uint256 support, uint256 quorum, bool isExecuted) = _resealCommittee.getResealState(_sealables);
        assert(support == quorum);
        assert(isExecuted == false);

        // WQ is paused for limited time before resealing
        assert(_WITHDRAWAL_QUEUE.getResumeSinceTimestamp() < _PAUSE_INFINITELY);

        // Reseal execution
        _resealCommittee.executeReseal(_sealables);

        // WQ is paused for infinite time after resealing
        assert(_WITHDRAWAL_QUEUE.getResumeSinceTimestamp() == _PAUSE_INFINITELY);
        assert(_WITHDRAWAL_QUEUE.isPaused());
    }

    function testFork_resealingWithActiveGovernance() external {
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
        _assertNormalState();

        // sealing committee seals Withdrawal Queue
        vm.prank(_SEALING_COMMITTEE);
        _gateSeal.seal(_sealables);

        // validate Withdrawal Queue was paused
        assertTrue(_WITHDRAWAL_QUEUE.isPaused());

        //Committee votes for resealing WQ
        for (uint256 i = 0; i < _resealCommitteeQuorum; i++) {
            vm.prank(_resealCommitteeMembers[i]);
            _resealCommittee.voteReseal(_sealables, true);
        }
        (uint256 support, uint256 quorum, bool isExecuted) = _resealCommittee.getResealState(_sealables);
        assert(support == quorum);
        assert(isExecuted == false);

        // WQ is paused for limited time before resealing
        assert(_WITHDRAWAL_QUEUE.getResumeSinceTimestamp() < _PAUSE_INFINITELY);

        // Reseal exection reverts
        vm.expectRevert();
        _resealCommittee.executeReseal(_sealables);
    }

    function testFork_resealingWithLockedGovernanceAndActiveWQ() external {
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());
        _assertNormalState();

        _lockStETH(_VETOER, percents("10.0"));
        _assertVetoSignalingState();

        // validate Withdrawal Queue is Active
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());

        // validate the dual governance still in the veto signaling state
        _assertVetoSignalingState();

        //Committee votes for resealing WQ
        for (uint256 i = 0; i < _resealCommitteeQuorum; i++) {
            vm.prank(_resealCommitteeMembers[i]);
            _resealCommittee.voteReseal(_sealables, true);
        }
        (uint256 support, uint256 quorum, bool isExecuted) = _resealCommittee.getResealState(_sealables);
        assert(support == quorum);
        assert(isExecuted == false);

        // validate Withdrawal Queue is Active
        assertFalse(_WITHDRAWAL_QUEUE.isPaused());

        // Reseal exection reverts
        vm.expectRevert();
        _resealCommittee.executeReseal(_sealables);
    }
}
