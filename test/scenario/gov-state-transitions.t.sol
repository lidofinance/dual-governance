// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";
import {Escrow} from "contracts/Escrow.sol";

import {DualGovernanceSetup} from "./setup.sol";
import {DualGovernanceUtils} from "./happy-path.t.sol";
import {TestHelpers} from './escrow.t.sol';
import "../utils/utils.sol";

contract GovernanceStateTransitions is TestHelpers {
    DualGovernance internal dualGov;

    address internal ldoWhale;
    address internal stEthWhale;

    function setUp() external {
        Utils.selectFork();
        Utils.removeLidoStakingLimit();

        ldoWhale = makeAddr("ldo_whale");
        Utils.setupLdoWhale(ldoWhale);

        stEthWhale = makeAddr("steth_whale");
        Utils.setupStEthWhale(stEthWhale);

        uint256 timelockDuration = 0;
        address timelockEmergencyMultisig = address(0);
        uint256 timelockEmergencyMultisigActiveFor = 0;

        DualGovernanceSetup.Deployed memory deployed = deployDG(
            ST_ETH,
            WST_ETH,
            WITHDRAWAL_QUEUE,
            BURNER,
            DAO_VOTING,
            timelockDuration,
            timelockEmergencyMultisig,
            timelockEmergencyMultisigActiveFor
        );

        dualGov = deployed.dualGov;
    }

    function test_signalling_state_min_duration() public {
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        updateVetoSupportInPercent(3 * 10 ** 16);
        updateVetoSupport(1);

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        uint256 signallingDuration = dualGov.CONFIG().signallingMinDuration();

        vm.warp(block.timestamp + (signallingDuration / 2));
        updateVetoSupport(1);

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        vm.warp(block.timestamp + signallingDuration / 2);
        updateVetoSupport(1);

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignallingDeactivation);
    }

    function test_signalling_state_max_duration() public {
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        updateVetoSupportInPercent(15 * 10 ** 16);

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        uint256 signallingDuration = dualGov.CONFIG().signallingMaxDuration();

        vm.warp(block.timestamp + (signallingDuration / 2));
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        vm.warp(block.timestamp + signallingDuration / 2 + 1000);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), GovernanceState.State.RageQuit);
    }

    function test_signalling_to_normal() public {
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        updateVetoSupportInPercent(3 * 10 ** 16 + 1);

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        uint256 signallingDuration = dualGov.CONFIG().signallingMinDuration();

        vm.warp(block.timestamp + signallingDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignallingDeactivation);

        uint256 signallingDeactivationDuration = dualGov.CONFIG().signallingDeactivationDuration();

        vm.warp(block.timestamp + signallingDeactivationDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), GovernanceState.State.VetoCooldown);

        uint256 signallingCooldownDuration = dualGov.CONFIG().signallingCooldownDuration();

        Escrow signallingEscrow = Escrow(payable(dualGov.signallingEscrow()));
        vm.prank(stEthWhale);
        signallingEscrow.unlockStEth();

        vm.warp(block.timestamp + signallingCooldownDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), GovernanceState.State.Normal);
    }

    function test_signalling_non_stop() public {
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        updateVetoSupportInPercent(3 * 10 ** 16 + 1);

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        uint256 signallingDuration = dualGov.CONFIG().signallingMinDuration();

        vm.warp(block.timestamp + signallingDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignallingDeactivation);

        uint256 signallingDeactivationDuration = dualGov.CONFIG().signallingDeactivationDuration();

        vm.warp(block.timestamp + signallingDeactivationDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), GovernanceState.State.VetoCooldown);

        uint256 signallingCooldownDuration = dualGov.CONFIG().signallingCooldownDuration();

        vm.warp(block.timestamp + signallingCooldownDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);
    }

    function test_signalling_to_rage_quit() public {
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        updateVetoSupportInPercent(15 * 10 ** 16);

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        uint256 signallingDuration = dualGov.CONFIG().signallingMaxDuration();

        vm.warp(block.timestamp + signallingDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), GovernanceState.State.RageQuit);
    }


    function updateVetoSupportInPercent(uint256 supportInPercent) internal {
        Escrow signallingEscrow = Escrow(payable(dualGov.signallingEscrow()));
        uint256 newVetoSupport = (supportInPercent * IERC20(ST_ETH).totalSupply()) / 10 ** 18;

        vm.prank(stEthWhale);
        // signallingEscrow.unlockStEth();

        updateVetoSupport(newVetoSupport);
        vm.stopPrank();

        (uint256 totalSupport, uint256 rageQuitSupport) = signallingEscrow.getSignallingState();
        // solhint-disable-next-line
        console.log("veto totalSupport %d, rageQuitSupport %d", totalSupport, rageQuitSupport);
    }

    function updateVetoSupport(uint256 amount) internal {
        Escrow signallingEscrow = Escrow(payable(dualGov.signallingEscrow()));
        vm.startPrank(stEthWhale);
        IERC20(ST_ETH).approve(address(signallingEscrow), amount);
        signallingEscrow.lockStEth(amount);
        vm.stopPrank();
    }
}
