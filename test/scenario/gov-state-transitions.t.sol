// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";
import {Escrow} from "contracts/Escrow.sol";

import {DualGovernanceSetup} from "./setup.sol";
import {DualGovernanceUtils} from "./happy-path.t.sol";
import "../utils/utils.sol";

contract GovernanceStateTransitions is DualGovernanceSetup {
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
            timelockDuration,
            timelockEmergencyMultisig,
            timelockEmergencyMultisigActiveFor
        );

        dualGov = deployed.dualGov;
    }

    function test_normal_to_signalling_transition() public {
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        updateVetoSupportInBps(300);
        updateVetoSupport(1);

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);


        uint256 minProposalExecutionTimelock = dualGov.CONFIG().signallingMinDuration();

        vm.warp(block.timestamp + (minProposalExecutionTimelock / 2));
        updateVetoSupport(1);

        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        // vm.warp(block.timestamp + minProposalExecutionTimelock / 2);
        // updateVetoSupport(1);

        // assertEq(dualGov.currentState(), GovernanceState.State.VetoSignallingDeactivation);
    }

    function updateVetoSupportInBps(uint256 supportInBps) internal {
        Escrow signallingEscrow = Escrow(dualGov.signallingEscrow());

        uint256 newVetoSupport = (supportInBps * IERC20(ST_ETH).totalSupply()) / 10_000;
        (uint256 currentVetoSupport,) = signallingEscrow.getSignallingState();

        if (newVetoSupport > currentVetoSupport) {
            updateVetoSupport(newVetoSupport - currentVetoSupport);
        } else if (newVetoSupport < currentVetoSupport) {
            vm.prank(stEthWhale);
            signallingEscrow.unlockStEth();
            updateVetoSupport(newVetoSupport);
        }

        vm.stopPrank();

        (uint256 totalSupport, uint256 rageQuitSupport) = signallingEscrow.getSignallingState();
        // solhint-disable-next-line
        console.log("veto totalSupport %d, rageQuitSupport %d", totalSupport, rageQuitSupport);
    }

    function updateVetoSupport(uint256 amount) internal {
        Escrow signallingEscrow = Escrow(dualGov.signallingEscrow());
        vm.startPrank(stEthWhale);
        IERC20(ST_ETH).approve(address(signallingEscrow), amount);
        console.log('steth locked:', amount);
        signallingEscrow.lockStEth(amount);
        vm.stopPrank();
    }
}
