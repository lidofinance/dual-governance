// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    Utils,
    Escrow,
    IERC20,
    ST_ETH,
    console,
    ExecutorCall,
    DualGovernance,
    IDangerousContract,
    ExecutorCallHelpers,
    DualGovernanceStatus,
    ScenarioTestBlueprint
} from "../utils/scenario-test-blueprint.sol";

contract GovernanceStateTransitions is ScenarioTestBlueprint {
    address internal stEthWhale;
    DualGovernance internal dualGov;

    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);
        dualGov = _dualGovernance;

        Utils.removeLidoStakingLimit();
        stEthWhale = makeAddr("steth_whale");
        Utils.setupStEthWhale(stEthWhale);
    }

    function test_signalling_state_min_duration() public {
        assertEq(dualGov.currentState(), DualGovernanceStatus.Normal);

        updateVetoSupportInPercent(3 * 10 ** 16);
        updateVetoSupport(1);

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignalling);

        uint256 signallingDuration = _config.SIGNALLING_MIN_DURATION();

        vm.warp(block.timestamp + (signallingDuration / 2));
        updateVetoSupport(1);

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignalling);

        vm.warp(block.timestamp + signallingDuration / 2);
        updateVetoSupport(1);

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignallingDeactivation);
    }

    function test_signalling_state_max_duration() public {
        assertEq(dualGov.currentState(), DualGovernanceStatus.Normal);

        updateVetoSupportInPercent(15 * 10 ** 16);

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignalling);

        uint256 signallingDuration = _config.SIGNALLING_MAX_DURATION();

        vm.warp(block.timestamp + (signallingDuration / 2));
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignalling);

        vm.warp(block.timestamp + signallingDuration / 2 + 1000);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), DualGovernanceStatus.RageQuit);
    }

    function test_signalling_to_normal() public {
        assertEq(dualGov.currentState(), DualGovernanceStatus.Normal);

        updateVetoSupportInPercent(3 * 10 ** 16 + 1);

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignalling);

        uint256 signallingDuration = _config.SIGNALLING_MIN_DURATION();

        vm.warp(block.timestamp + signallingDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignallingDeactivation);

        uint256 signallingDeactivationDuration = _config.SIGNALLING_DEACTIVATION_DURATION();

        vm.warp(block.timestamp + signallingDeactivationDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoCooldown);

        uint256 signallingCooldownDuration = _config.SIGNALLING_COOLDOWN_DURATION();

        Escrow signallingEscrow = Escrow(payable(dualGov.signallingEscrow()));
        vm.prank(stEthWhale);
        signallingEscrow.unlockStEth();

        vm.warp(block.timestamp + signallingCooldownDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), DualGovernanceStatus.Normal);
    }

    function test_signalling_non_stop() public {
        assertEq(dualGov.currentState(), DualGovernanceStatus.Normal);

        updateVetoSupportInPercent(3 * 10 ** 16 + 1);

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignalling);

        uint256 signallingDuration = _config.SIGNALLING_MIN_DURATION();

        vm.warp(block.timestamp + signallingDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignallingDeactivation);

        uint256 signallingDeactivationDuration = _config.SIGNALLING_DEACTIVATION_DURATION();

        vm.warp(block.timestamp + signallingDeactivationDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoCooldown);

        uint256 signallingCooldownDuration = _config.SIGNALLING_COOLDOWN_DURATION();

        vm.warp(block.timestamp + signallingCooldownDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignalling);
    }

    function test_signalling_to_rage_quit() public {
        assertEq(dualGov.currentState(), DualGovernanceStatus.Normal);

        updateVetoSupportInPercent(15 * 10 ** 16);

        assertEq(dualGov.currentState(), DualGovernanceStatus.VetoSignalling);

        uint256 signallingDuration = _config.SIGNALLING_MAX_DURATION();

        vm.warp(block.timestamp + signallingDuration);
        dualGov.activateNextState();

        assertEq(dualGov.currentState(), DualGovernanceStatus.RageQuit);
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
