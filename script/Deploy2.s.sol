// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {Escrow} from "contracts/Escrow.sol";
import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {ControllerEnhancedTimelock} from "contracts/Timelock.sol";
import {DualGovernanceTimelockController, DualGovernanceConfig} from "contracts/DualGovernanceTimelockController.sol";

contract DualGovernanceDeployScript {
    address public immutable STETH;
    address public immutable WSTETH;
    address public immutable BURNER;
    address public immutable VOTING;
    address public immutable WITHDRAWAL_QUEUE;
    uint256 public immutable MIN_DELAY_DURATION;
    uint256 public immutable MAX_DELAY_DURATION;

    constructor(
        address stETH,
        address wstETH,
        address burner,
        address voting,
        address withdrawalQueue,
        uint256 minDelayDuration,
        uint256 maxDelayDuration
    ) {
        STETH = stETH;
        WSTETH = wstETH;
        BURNER = burner;
        VOTING = voting;
        WITHDRAWAL_QUEUE = withdrawalQueue;

        MIN_DELAY_DURATION = minDelayDuration;
        MAX_DELAY_DURATION = maxDelayDuration;
    }

    function deploy(
        uint256 adoptionDelay,
        uint256 executionDelay,
        address emergencyCommittee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration,
        DualGovernanceConfig memory config
    )
        external
        returns (
            ControllerEnhancedTimelock timelock,
            DualGovernanceTimelockController dualGovernance,
            OwnableExecutor adminExecutor
        )
    {
        (timelock, adminExecutor) = _deployEmergencyProtectedTimelock(
            adoptionDelay, executionDelay, emergencyCommittee, protectionDuration, emergencyModeDuration
        );
        dualGovernance = deployDualGovernanceTimelockController(address(timelock), config);
    }

    function deployDualGovernanceTimelockController(
        address timelock,
        DualGovernanceConfig memory config
    ) public returns (DualGovernanceTimelockController dualGovernance) {
        // deploy DG
        address escrowImpl = address(new Escrow(address(0), STETH, WSTETH, WITHDRAWAL_QUEUE, BURNER));
        address escrowProxy = Clones.clone(escrowImpl);
        dualGovernance = new DualGovernanceTimelockController(timelock, escrowProxy, config);
        Escrow(payable(escrowProxy)).initialize(address(dualGovernance));
    }

    function deployEmergencyProtectedTimelock(
        uint256 adoptionDelay,
        uint256 executionDelay,
        address emergencyCommittee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration
    ) public returns (ControllerEnhancedTimelock timelock, OwnableExecutor adminExecutor) {
        (timelock, adminExecutor) = _deployEmergencyProtectedTimelock(
            adoptionDelay, executionDelay, emergencyCommittee, protectionDuration, emergencyModeDuration
        );
        adminExecutor.transferOwnership(address(timelock));
    }

    function _deployEmergencyProtectedTimelock(
        uint256 adoptionDelay,
        uint256 executionDealy,
        address emergencyCommittee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration
    ) internal returns (ControllerEnhancedTimelock timelock, OwnableExecutor adminExecutor) {
        adminExecutor = new OwnableExecutor(address(this));
        timelock = new ControllerEnhancedTimelock(
            VOTING, address(adminExecutor), MIN_DELAY_DURATION, MAX_DELAY_DURATION, adoptionDelay, executionDealy
        );

        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setEmergencyProtection, (emergencyCommittee, protectionDuration, emergencyModeDuration)
            )
        );
    }
}
