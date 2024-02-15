// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Configuration} from "contracts/Configuration.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";

import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

contract DualGovernanceDeployScript {
    address public immutable STETH;
    address public immutable WSTETH;
    address public immutable BURNER;
    address public immutable VOTING;
    address public immutable WITHDRAWAL_QUEUE;

    constructor(address stETH, address wstETH, address burner, address voting, address withdrawalQueue) {
        STETH = stETH;
        WSTETH = wstETH;
        BURNER = burner;
        VOTING = voting;
        WITHDRAWAL_QUEUE = withdrawalQueue;
    }

    function deploy(
        address adminProposer,
        uint256 delay,
        address emergencyCommittee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration
    )
        external
        returns (DualGovernance dualGovernance, EmergencyProtectedTimelock timelock, OwnableExecutor adminExecutor)
    {
        (timelock, adminExecutor) =
            deployEmergencyProtectedTimelock(delay, emergencyCommittee, protectionDuration, emergencyModeDuration);
        dualGovernance = deployDualGovernance(address(timelock), adminProposer);
    }

    function deployDualGovernance(
        address timelock,
        address adminProposer
    ) public returns (DualGovernance dualGovernance) {
        // deploy initial config impl
        address configImpl = address(new Configuration(adminProposer));

        // deploy config proxy
        ProxyAdmin configAdmin = new ProxyAdmin(address(this));
        TransparentUpgradeableProxy config =
            new TransparentUpgradeableProxy(configImpl, address(configAdmin), new bytes(0));

        // deploy DG
        address escrowImpl = address(new Escrow(address(config), STETH, WSTETH, WITHDRAWAL_QUEUE, BURNER));
        dualGovernance = new DualGovernance(address(config), configImpl, address(configAdmin), escrowImpl, timelock);
        configAdmin.transferOwnership(address(dualGovernance));
    }

    function deployEmergencyProtectedTimelock(
        uint256 delay,
        address emergencyCommittee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration
    ) public returns (EmergencyProtectedTimelock timelock, OwnableExecutor adminExecutor) {
        adminExecutor = new OwnableExecutor(address(this));
        timelock = new EmergencyProtectedTimelock(address(adminExecutor), VOTING);

        adminExecutor.execute(address(timelock), 0, abi.encodeCall(timelock.setGovernanceAndDelay, (VOTING, delay)));
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setEmergencyProtection, (emergencyCommittee, protectionDuration, emergencyModeDuration)
            )
        );
        adminExecutor.transferOwnership(address(timelock));
    }
}
