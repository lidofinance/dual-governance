// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Configuration} from "./Configuration.sol";
import {Agent} from "./Agent.sol";
import {Escrow} from "./Escrow.sol";
import {GovernanceState} from "./GovernanceState.sol";

interface IProxyAdmin {
    function upgradeAndCall(address proxy, address impl, bytes memory data) external;
}

contract DualGovernance {
    using SafeCast for uint256;

    event NewProposal(uint256 indexed proposerId, uint256 indexed id);
    event GovernanceReplaced(address governance, uint256 timelockDuration);
    event ConfigSet(address config);
    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    error ProposalSubmissionNotAllowed();
    error InvalidProposer(address proposer);
    error InvalidExecutor(address executor);
    error ProposerIsNotRegistered(address proposer);
    error ProposerAlreadyRegistered(address proposer);
    error InvalidProposalId();
    error UnknownProposalId();
    error ProposalIsNotExecutable();
    error ProposalAlreadyExecuted();
    error CannotCallOutsideExecution();
    error NestedExecutionProhibited();
    error NestedForwardingProhibited();
    error Unauthorized();
    error ProposalItemsLengthMismatch(
        uint256 targetsLength,
        uint256 valuesLength,
        uint256 payloadsLength
    );
    error UnregisteredProposer(address sender);

    struct Proposal {
        uint24 id;
        address proposer;
        uint40 submittedAt;
        bool isExecuted;
        address[] targets;
        uint256[] values;
        bytes[] payloads;
    }

    Configuration public immutable CONFIG;

    IProxyAdmin internal immutable CONFIG_ADMIN;
    GovernanceState internal immutable GOV_STATE;

    address[] internal _proposers;
    mapping(address proposer => address executor) internal _executors;

    uint256 public proposalsCount;
    mapping(uint256 => Proposal) internal _proposals;

    constructor(
        address config,
        address initialConfigImpl,
        address configAdmin,
        address escrowImpl,
        address adminProposer,
        address adminExecutor
    ) {
        CONFIG = Configuration(config);
        CONFIG_ADMIN = IProxyAdmin(configAdmin);
        GOV_STATE = new GovernanceState(address(CONFIG), address(this), escrowImpl);
        emit ConfigSet(initialConfigImpl);
        _registerProposer(adminProposer, adminExecutor);
    }

    function signallingEscrow() external returns (address) {
        return GOV_STATE.signallingEscrow();
    }

    function rageQuitEscrow() external returns (address) {
        return GOV_STATE.rageQuitEscrow();
    }

    function currentState() external returns (GovernanceState.State) {
        return GOV_STATE.currentState();
    }

    function activateNextState() external returns (GovernanceState.State) {
        return GOV_STATE.activateNextState();
    }

    function replaceDualGovernance(address newGovernance, uint256 timelockDuration) external {
        _assertExecutionByAdminExecutor();
        // TODO: implement governance replacement
        // AGENT.setGovernance(newGovernance, timelockDuration);
        emit GovernanceReplaced(newGovernance, timelockDuration);
    }

    function updateConfig(address newConfig) external {
        _assertExecutionByAdminExecutor();
        CONFIG_ADMIN.upgradeAndCall(address(CONFIG), newConfig, new bytes(0));
        emit ConfigSet(newConfig);
    }

    function hasProposer(address proposer) external view returns (bool) {
        return _executors[proposer] != address(0);
    }

    function getProposers()
        external
        view
        returns (address[] memory proposers, address[] memory executors)
    {
        proposers = new address[](_proposers.length);
        executors = new address[](proposers.length);
        for (uint256 i = 0; i < proposers.length; ++i) {
            proposers[i] = _proposers[i];
            executors[i] = _executors[proposers[i]];
        }
    }

    function registerProposer(address proposer, address executor) external {
        _assertExecutionByAdminExecutor();
        return _registerProposer(proposer, executor);
    }

    function unregisterProposer(address proposer) external {
        _assertExecutionByAdminExecutor();
        _unregisterProposer(proposer);
    }

    function killAllPendingProposals() external {
        GOV_STATE.activateNextState();
        if (CONFIG.adminProposer() != msg.sender) {
            revert Unauthorized();
        }
        GOV_STATE.killAllPendingProposals();
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        (proposal, ) = _loadProposal(proposalId);
    }

    function submitProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads
    ) external returns (uint256 newProposalId) {
        GOV_STATE.activateNextState();
        if (!GOV_STATE.isProposalSubmissionAllowed()) {
            revert ProposalSubmissionNotAllowed();
        }

        if (targets.length != values.length || targets.length != payloads.length) {
            revert ProposalItemsLengthMismatch(targets.length, values.length, payloads.length);
        }

        address executor = _executors[msg.sender];
        if (executor == address(0)) {
            revert UnregisteredProposer(msg.sender);
        }

        newProposalId = proposalsCount++;
        Proposal storage newProposal = _proposals[newProposalId];

        newProposal.id = newProposalId.toUint24();
        newProposal.isExecuted = false;
        newProposal.proposer = msg.sender;
        newProposal.submittedAt = block.timestamp.toUint40();
        newProposal.targets = targets;
        newProposal.payloads = payloads;
        newProposal.values = values;
    }

    // TODO: reentrance protection
    function executeProposal(uint256 proposalId) external {
        GOV_STATE.activateNextState();

        (Proposal storage proposal, uint256 submittedAt) = _loadProposal(proposalId);

        if (proposal.isExecuted) {
            revert ProposalAlreadyExecuted();
        }

        if (!GOV_STATE.isProposalExecutable(submittedAt, submittedAt)) {
            revert ProposalIsNotExecutable();
        }

        address proposer = proposal.proposer;
        if (!_isRegisteredProposer(proposer)) {
            revert InvalidProposer(proposer);
        }

        proposal.isExecuted = true;

        address executor = _executors[proposer];
        assert(executor != address(0));

        address[] memory targets = proposal.targets;
        bytes[] memory payloads = proposal.payloads;
        assert(targets.length == payloads.length);

        for (uint256 i = 0; i < targets.length; ++i) {
            Agent(executor).forwardCall(targets[i], payloads[i]);
        }
    }

    function _registerProposer(address proposer, address executor) internal {
        if (_isRegisteredProposer(proposer)) {
            revert ProposerAlreadyRegistered(proposer);
        }
        _proposers.push(proposer);
        _executors[proposer] = executor;

        emit ProposerRegistered(proposer, executor);
    }

    function _unregisterProposer(address proposer) internal {
        if (!_isRegisteredProposer(proposer)) {
            revert ProposerIsNotRegistered(proposer);
        }

        uint256 totalVotingSystems = _proposers.length;
        uint256 i = 0;

        for (; i < _proposers.length; ++i) {
            if (_proposers[i] == proposer) {
                break;
            }
        }
        for (++i; i < totalVotingSystems; ++i) {
            _proposers[i - 1] = _proposers[i];
        }

        address executor = _executors[proposer];
        _executors[proposer] = address(0);
        emit ProposerUnregistered(proposer, executor);
    }

    function _assertExecutionByAdminExecutor() internal view {
        address adminExecutor = _executors[CONFIG.adminProposer()];
        if (msg.sender != adminExecutor) {
            revert Unauthorized();
        }
    }

    function _loadProposal(
        uint256 proposalKey
    ) internal view returns (Proposal storage proposal, uint256 submittedAt) {
        proposal = _proposals[proposalKey];
        submittedAt = proposal.submittedAt;
        if (proposal.submittedAt == 0) {
            revert UnknownProposalId();
        }
    }

    function _isRegisteredProposer(address proposer) internal view returns (bool isProposer) {
        isProposer = _executors[proposer] != address(0);
    }

    function _getTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
