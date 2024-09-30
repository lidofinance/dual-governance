// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DualGovernance} from "contracts/DualGovernance.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

import {ScenarioTestBlueprint, ExternalCall} from "../utils/scenario-test-blueprint.sol";
import {DAO_AGENT} from "../utils/mainnet-addresses.sol";

contract ResealCommitteeTest is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");
    uint256 public constant PAUSE_INFINITELY = type(uint256).max;

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: true});
        _setupStETHBalance(_VETOER, PercentsD16.fromBasisPoints(10_00));
        _lockStETH(_VETOER, 1 ether);
    }

    function test_reseal_committees_happy_path() external {
        uint256 quorum;
        uint256 support;
        bool isExecuted;

        address[] memory members;

        address sealable = address(_lido.withdrawalQueue);

        vm.prank(DAO_AGENT);
        _lido.withdrawalQueue.grantRole(
            0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d, address(this)
        );

        // Reseal
        members = _resealCommittee.getMembers();
        for (uint256 i = 0; i < _resealCommittee.quorum() - 1; i++) {
            vm.prank(members[i]);
            _resealCommittee.voteReseal(sealable, true);
            (support, quorum,) = _resealCommittee.getResealState(sealable);
            assert(support < quorum);
        }

        vm.prank(members[members.length - 1]);
        _resealCommittee.voteReseal(sealable, true);
        (support, quorum,) = _resealCommittee.getResealState(sealable);
        assert(support == quorum);

        _assertNormalState();

        vm.expectRevert(abi.encodeWithSelector(DualGovernance.ResealIsNotAllowedInNormalState.selector));
        _resealCommittee.executeReseal(sealable);

        _lockStETH(_VETOER, _dualGovernanceConfigProvider.FIRST_SEAL_RAGE_QUIT_SUPPORT());
        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        assertEq(_lido.withdrawalQueue.isPaused(), false);
        vm.expectRevert(abi.encodeWithSelector(ResealManager.SealableWrongPauseState.selector));
        _resealCommittee.executeReseal(sealable);

        _lido.withdrawalQueue.pauseFor(3600 * 24 * 6);
        assertEq(_lido.withdrawalQueue.isPaused(), true);

        _resealCommittee.executeReseal(sealable);
    }
}
