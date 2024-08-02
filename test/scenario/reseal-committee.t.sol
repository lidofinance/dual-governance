// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ScenarioTestBlueprint, ExternalCall, percents} from "../utils/scenario-test-blueprint.sol";
import {DualGovernance} from "../../contracts/DualGovernance.sol";
import {ResealManager} from "../../contracts/ResealManager.sol";
import {DAO_AGENT} from "../utils/mainnet-addresses.sol";

contract ResealCommitteeTest is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");
    uint256 public constant PAUSE_INFINITELY = type(uint256).max;

    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ true);
        _depositStETH(_VETOER, 1 ether);
    }

    function test_reseal_committees_happy_path() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        address[] memory members;

        address[] memory sealables = new address[](1);
        sealables[0] = address(_WITHDRAWAL_QUEUE);

        vm.prank(DAO_AGENT);
        _WITHDRAWAL_QUEUE.grantRole(0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d, address(this));

        // Reseal
        members = _resealCommittee.getMembers();
        for (uint256 i = 0; i < _resealCommittee.quorum() - 1; i++) {
            vm.prank(members[i]);
            _resealCommittee.voteReseal(sealables, true);
            (support, quorum, isExecuted) = _resealCommittee.getResealState(sealables);
            assert(support < quorum);
            assert(isExecuted == false);
        }

        vm.prank(members[members.length - 1]);
        _resealCommittee.voteReseal(sealables, true);
        (support, quorum, isExecuted) = _resealCommittee.getResealState(sealables);
        assert(support == quorum);
        assert(isExecuted == false);

        _assertNormalState();

        vm.expectRevert(abi.encodeWithSelector(DualGovernance.ResealIsNotAllowedInNormalState.selector));
        _resealCommittee.executeReseal(sealables);

        _lockStETH(_VETOER, percents(_config.FIRST_SEAL_RAGE_QUIT_SUPPORT()));
        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        assertEq(_WITHDRAWAL_QUEUE.isPaused(), false);
        vm.expectRevert(abi.encodeWithSelector(ResealManager.SealableWrongPauseState.selector));
        _resealCommittee.executeReseal(sealables);

        _WITHDRAWAL_QUEUE.pauseFor(3600 * 24 * 6);
        assertEq(_WITHDRAWAL_QUEUE.isPaused(), true);

        _resealCommittee.executeReseal(sealables);
    }
}
