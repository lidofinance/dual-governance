pragma solidity 0.8.23;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Agent} from "contracts/Agent.sol";
import {Escrow} from "contracts/Escrow.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";
import {Configuration} from "contracts/Configuration.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";


abstract contract DualGovernanceSetup is TestAssertions {
    struct Deployed {
        Agent agent;
        DualGovernance dualGov;
        TransparentUpgradeableProxy config;
        ProxyAdmin configAdmin;
    }

    uint256 internal constant ARAGON_VOTING_SYSTEM_ID = 1;

    function deployDG(
        address daoAgent,
        address stEth,
        address wstEth,
        address withdrawalQueue,
        uint256 agentTimelockDuration,
        address agentEmergencyMultisig,
        uint256 agentEmergencyMultisigActiveFor
    )
        public
        returns (Deployed memory d)
    {
        // deploy initial config impl
        address configImpl = address(new Configuration(DAO_VOTING));

        // deploy config proxy
        d.configAdmin = new ProxyAdmin(address(this));
        d.config = new TransparentUpgradeableProxy(configImpl, address(d.configAdmin), new bytes(0));

        // deploy agent and set its emergency multisig
        d.agent = new Agent(daoAgent, address(this));
        d.agent.forwardCall(address(d.agent), abi.encodeCall(
            d.agent.setEmergencyMultisig, (
                agentEmergencyMultisig,
                agentEmergencyMultisigActiveFor
            )
        ));

        console.log("Agent deployed to %x", address(d.agent));

        // deploy DG
        address escrowImpl = address(new Escrow(address(d.config), stEth, wstEth, withdrawalQueue));
        d.dualGov = new DualGovernance(
            address(d.config),
            configImpl,
            address(d.configAdmin),
            escrowImpl,
            DAO_VOTING,
            address(d.agent)
        );

        console.log("DG deployed to %x", address(d.dualGov));

        // point Agent to the DG
        d.agent.forwardCall(address(d.agent), abi.encodeCall(
            d.agent.setGovernance, (
                address(d.dualGov),
                agentTimelockDuration
            )
        ));

        // pass config proxy ownership to the DG
        d.configAdmin.transferOwnership(address(d.dualGov));
    }

    function getAddress(bytes memory bytecode, uint256 salt) public view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

}
