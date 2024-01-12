pragma solidity 0.8.23;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Agent} from "contracts/Agent.sol";
import {Escrow} from "contracts/Escrow.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";
import {Configuration} from "contracts/Configuration.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {AragonVotingSystem} from "contracts/voting-systems/AragonVotingSystem.sol";

import "forge-std/Test.sol";

import "./utils/mainnet-addresses.sol";
import "./utils/interfaces.sol";
import "./utils/utils.sol";


abstract contract DualGovernanceSetup {
    struct Deployed {
        Agent agent;
        AragonVotingSystem aragonVotingSystem;
        DualGovernance dualGov;
        TransparentUpgradeableProxy config;
        ProxyAdmin configAdmin;
    }

    uint256 internal constant ARAGON_VOTING_SYSTEM_ID = 1;

    function deployDG(
        address daoAgent,
        address daoVoting,
        address ldoToken,
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
        d.agent.forwardCall(address(d.agent), abi.encodeCall(
            d.agent.setEmergencyMultisig, (
                agentEmergencyMultisig,
                agentEmergencyMultisigActiveFor
            )
        ));

        // deploy aragon voting system facade
        d.aragonVotingSystem = new AragonVotingSystem(daoVoting, ldoToken);

        // deploy DG
        address escrowImpl = address(new Escrow(address(d.config), stEth, wstEth, withdrawalQueue));
        d.dualGov = new DualGovernance(
            address(d.agent),
            address(d.config),
            configImpl,
            address(d.configAdmin),
            escrowImpl,
            address(d.aragonVotingSystem)
        );

        // point Agent to the DG
        d.agent.forwardCall(address(d.agent), abi.encodeCall(
            d.agent.setGovernance, (
                address(d.dualGov),
                agentTimelockDuration
            )
        ));

        // pass config proxy ownership to the DG
        d.configAdmin.transferOwnership(address(d.dualGov));

        // grant the aragon voting adapter the permission to create aragon votes
        Utils.grantPermission(DAO_VOTING, IAragonVoting(DAO_VOTING).CREATE_VOTES_ROLE(), address(d.aragonVotingSystem));
    }

    function getAddress(bytes memory bytecode, uint256 salt) public view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

}

contract HappyPathTest is Test, DualGovernanceSetup {
    Agent internal agent;
    DualGovernance internal dualGov;
    Target internal target;

    address internal ldoWhale;

    function setUp() external {
        Utils.selectFork();

        ldoWhale = makeAddr("ldo_whale");
        Utils.setupLdoWhale(ldoWhale);

        uint256 agentTimelock = 0;
        address emergencyMultisig = address(0);
        uint256 agentEmergencyMultisigActiveFor = 0;

        DualGovernanceSetup.Deployed memory deployed = deployDG(
            DAO_AGENT,
            DAO_VOTING,
            LDO_TOKEN,
            ST_ETH,
            WST_ETH,
            WITHDRAWAL_QUEUE,
            agentTimelock,
            emergencyMultisig,
            agentEmergencyMultisigActiveFor
        );

        agent = deployed.agent;
        dualGov = deployed.dualGov;
        target = new Target(address(agent));
    }

    function test_setup() external {
        assertEq(agent.getGovernance(), address(dualGov));
    }

    function test_proposal() external {
        bytes memory targetCalldata = abi.encodeCall(target.doSmth, (42));
        bytes memory forwardCalldata = abi.encodeCall(dualGov.forwardCall, (address(target), targetCalldata));
        bytes memory script = Utils.encodeEvmCallScript(address(dualGov), forwardCalldata);

        uint256 voteId = dualGov.submitProposal(ARAGON_VOTING_SYSTEM_ID, script);
        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

        vm.expectRevert(DualGovernance.ProposalIsNotExecutable.selector);
        dualGov.executeProposal(ARAGON_VOTING_SYSTEM_ID, voteId);

        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());
        vm.expectCall(address(target), targetCalldata);
        dualGov.executeProposal(ARAGON_VOTING_SYSTEM_ID, voteId);
    }
}
