pragma solidity 0.8.23;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Escrow} from "contracts/Escrow.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";
import {Configuration} from "contracts/Configuration.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {Timelock} from "contracts/timelock/Timelock.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

abstract contract DualGovernanceSetup is TestAssertions {
    struct Deployed {
        DualGovernance dualGov;
        TransparentUpgradeableProxy config;
        ProxyAdmin configAdmin;
        Timelock timelock;
    }

    uint256 internal constant ARAGON_VOTING_SYSTEM_ID = 1;

    function deployDG(
        address stEth,
        address wstEth,
        address withdrawalQueue,
        uint256 timelockDuration,
        address timelockEmergencyMultisig,
        uint256 timelockEmergencyMultisigActiveFor
    ) public returns (Deployed memory d) {
        // deploy initial config impl
        address configImpl = address(new Configuration(DAO_VOTING));

        // deploy config proxy
        d.configAdmin = new ProxyAdmin(address(this));
        d.config = new TransparentUpgradeableProxy(
            configImpl,
            address(d.configAdmin),
            new bytes(0)
        );

        d.timelock = new Timelock(
            address(this),
            DAO_AGENT,
            0, // MUST NOT be used in production. TODO: create better deployment process
            14 days,
            0,
            timelockEmergencyMultisig,
            block.timestamp + timelockEmergencyMultisigActiveFor
        );
        console.log("Agent deployed to %x", address(d.timelock));

        // deploy DG
        address escrowImpl = address(new Escrow(address(d.config), stEth, wstEth, withdrawalQueue));
        d.dualGov = new DualGovernance(
            address(d.config),
            configImpl,
            address(d.configAdmin),
            escrowImpl,
            address(d.timelock)
        );

        console.log("DG deployed to %x", address(d.dualGov));

        // point Timelock to the DG
        address[] memory targets = new address[](1);
        targets[0] = address(d.timelock);
        uint256[] memory values = new uint256[](1);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeCall(
            d.timelock.setAdmin,
            (address(d.dualGov), timelockDuration)
        );

        d.timelock.propose(d.timelock.ADMIN_EXECUTOR(), targets, values, payloads);

        d.timelock.enqueue(1, 0);
        d.timelock.execute(1);

        // pass config proxy ownership to the DG
        d.configAdmin.transferOwnership(address(d.dualGov));
    }

    function getAddress(bytes memory bytecode, uint256 salt) public view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))
        );
        return address(uint160(uint256(hash)));
    }
}
