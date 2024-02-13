// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";

import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

contract PlanBDeployScript is Script {
    address public immutable VOTING;

    constructor(address voting) {
        VOTING = voting;
    }

    function run(
        uint256 delay,
        address emergencyCommittee,
        uint256 emergencyModeDuration
    ) external returns (EmergencyProtectedTimelock timelock, OwnableExecutor adminExecutor) {
        adminExecutor = new OwnableExecutor(address(this));
        timelock = new EmergencyProtectedTimelock(address(adminExecutor), VOTING);

        adminExecutor.execute(address(timelock), 0, abi.encodeCall(timelock.setGovernanceAndDelay, (VOTING, delay)));
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setEmergencyProtection, (emergencyCommittee, emergencyModeDuration))
        );
        adminExecutor.transferOwnership(address(timelock));
    }
}
