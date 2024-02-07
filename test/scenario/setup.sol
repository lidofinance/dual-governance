// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Escrow} from "contracts/Escrow.sol";
import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";
import {Configuration} from "contracts/Configuration.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {BurnerVault} from "contracts/BurnerVault.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

abstract contract DualGovernanceSetup is TestAssertions {
    struct Deployed {
        DualGovernance dualGov;
        TransparentUpgradeableProxy config;
        ProxyAdmin configAdmin;
        EmergencyProtectedTimelock timelock;
        OwnableExecutor adminExecutor;
        BurnerVault burnerVault;
    }

    uint256 internal constant ARAGON_VOTING_SYSTEM_ID = 1;

    function deployDG(
        address stEth,
        address wstEth,
        address withdrawalQueue,
        address burner,
        uint256 timelockDuration,
        address timelockEmergencyMultisig,
        uint256 timelockEmergencyMultisigActiveFor
    ) public returns (Deployed memory d) {
        // deploy initial config impl
        address configImpl = address(new Configuration(DAO_VOTING));

        // deploy config proxy
        d.configAdmin = new ProxyAdmin(address(this));
        d.config = new TransparentUpgradeableProxy(configImpl, address(d.configAdmin), new bytes(0));

        // initially owner of the admin is set to the deployer
        // to configure setup
        d.adminExecutor = new OwnableExecutor(address(this));

        d.timelock = new EmergencyProtectedTimelock(
            address(d.adminExecutor),
            DAO_VOTING // maybe emergency governance should be Agent
        );

        // solhint-disable-next-line
        console.log("Timelock deployed to %x", address(d.timelock));

        address burner_vault = address(new BurnerVault(burner, stEth, wstEth));

        // deploy DG
        address escrowImpl = address(new Escrow(address(d.config), stEth, wstEth, withdrawalQueue, burner_vault));
        d.dualGov =
            new DualGovernance(address(d.config), configImpl, address(d.configAdmin), escrowImpl, address(d.timelock));

        // solhint-disable-next-line
        console.log("DG deployed to %x", address(d.dualGov));

        // configure Timelock
        d.adminExecutor.execute(
            address(d.timelock), 0, abi.encodeCall(d.timelock.setGovernance, (address(d.dualGov), timelockDuration))
        );

        // TODO: pass this value via args
        uint256 emergencyModeDuration = 0;
        d.adminExecutor.execute(
            address(d.timelock),
            0,
            abi.encodeCall(
                d.timelock.setEmergencyProtection,
                (timelockEmergencyMultisig, timelockEmergencyMultisigActiveFor, emergencyModeDuration)
            )
        );

        d.adminExecutor.transferOwnership(address(d.timelock));

        // pass config proxy ownership to the DG
        d.configAdmin.transferOwnership(address(d.dualGov));
    }

    function getAddress(bytes memory bytecode, uint256 salt) public view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
}
