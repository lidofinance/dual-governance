pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Agent} from "contracts/Agent.sol";
import {Escrow} from "contracts/Escrow.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";
import {Configuration} from "contracts/Configuration.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";


abstract contract DualGovernanceSetup {
    struct Deployed {
        Agent agent;
        DualGovernance dualGov;
        TransparentUpgradeableProxy config;
        ProxyAdmin configAdmin;
    }

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
        address configImpl = address(new Configuration());

        // deploy config proxy
        d.configAdmin = new ProxyAdmin(address(this));
        d.config = new TransparentUpgradeableProxy(configImpl, address(d.configAdmin), new bytes(0));

        // deploy agent and set its emergency multisig
        d.agent = new Agent(daoAgent, address(this));
        d.agent.forwardCall(
            address(d.agent),
            abi.encodeWithSelector(
                d.agent.setEmergencyMultisig.selector,
                agentEmergencyMultisig,
                agentEmergencyMultisigActiveFor
            )
        );

        // deploy DG
        address escrowImpl = address(new Escrow(address(d.config), stEth, wstEth, withdrawalQueue));
        d.dualGov = new DualGovernance(address(d.agent), address(d.config), configImpl, address(d.configAdmin), escrowImpl);

        // point Agent to the DG
        d.agent.forwardCall(
            address(d.agent),
            abi.encodeWithSelector(
                d.agent.setGovernance.selector,
                address(d.dualGov),
                agentTimelockDuration
            )
        );

        // pass config proxy ownership to the DG
        d.configAdmin.transferOwnership(address(d.dualGov));
    }

    function getAddress(bytes memory bytecode, uint256 salt) public view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

}

contract HappyPathTest is Test, DualGovernanceSetup {
    address constant DAO_AGENT = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
    address constant ST_ETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WST_ETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    Agent internal agent;
    DualGovernance internal dualGov;

    function setUp() external {
        DualGovernanceSetup.Deployed memory deployed = deployDG(
            DAO_AGENT,
            ST_ETH,
            WST_ETH,
            WITHDRAWAL_QUEUE,
            0,
            address(0),
            0
        );
        agent = deployed.agent;
        dualGov = deployed.dualGov;
    }

    function test_getGovernance() external {
        assertEq(agent.getGovernance(), address(dualGov));
    }

}
