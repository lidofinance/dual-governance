// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Configuration} from "./Configuration.sol";
import {Escrow} from "./Escrow.sol";
import {GovernanceState} from "./GovernanceState.sol";
import {Timelock, Proposals, Proposal} from "./timelock/Timelock.sol";

interface IProxyAdmin {
    function upgradeAndCall(address proxy, address impl, bytes memory data) external;
}

contract DualGovernance {
    event ConfigSet(address config);
    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    error ProposalSubmissionNotAllowed();
    error ProposerIsNotRegistered(address proposer);
    error ProposerAlreadyRegistered(address proposer);
    error ProposalIsNotExecutable();
    error Unauthorized();

    error UnregisteredProposer(address sender);

    Configuration public immutable CONFIG;

    IProxyAdmin internal immutable CONFIG_ADMIN;
    GovernanceState internal immutable GOV_STATE;

    Timelock public immutable TIMELOCK;

    address[] internal _proposers;
    mapping(address proposer => address executor) internal _executors;

    constructor(
        address config,
        address initialConfigImpl,
        address configAdmin,
        address escrowImpl,
        address timelock
    ) {
        CONFIG = Configuration(config);
        CONFIG_ADMIN = IProxyAdmin(configAdmin);
        TIMELOCK = Timelock(timelock);
        GOV_STATE = new GovernanceState(address(CONFIG), address(this), escrowImpl);
        emit ConfigSet(initialConfigImpl);
        _registerProposer(CONFIG.adminProposer(), TIMELOCK.ADMIN_EXECUTOR());
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
        TIMELOCK.cancelAllProposals();
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        return TIMELOCK.getProposal(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads
    ) external returns (uint256 newProposalId) {
        GOV_STATE.activateNextState();
        if (!GOV_STATE.isProposalSubmissionAllowed()) {
            revert ProposalSubmissionNotAllowed();
        }

        if (!_isRegisteredProposer(msg.sender)) {
            revert UnregisteredProposer(msg.sender);
        }

        address executor = _executors[msg.sender];
        return TIMELOCK.propose(executor, targets, values, payloads);
    }

    // TODO: reentrance protection
    function enqueue(uint256 proposalId) external {
        GOV_STATE.activateNextState();

        if (!GOV_STATE.isExecutionEnabled()) {
            revert ProposalIsNotExecutable();
        }

        // TODO: the time must pass before enqueueing the proposal
        // must be computed dynamicly?
        TIMELOCK.enqueue(proposalId, CONFIG.minProposalExecutionTimelock());
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

    function _isRegisteredProposer(address proposer) internal view returns (bool isProposer) {
        isProposer = _executors[proposer] != address(0);
    }

    function _getTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
