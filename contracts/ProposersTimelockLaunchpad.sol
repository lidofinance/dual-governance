// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITimelock} from "./interfaces/ITimelock.sol";
import {ExecutorCall} from "./interfaces/IExecutor.sol";

import {Proposers, Proposer} from "./libraries/Proposers.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

contract ProposersTimelockLaunchpad is ConfigurationProvider {
    using Proposers for Proposers.State;

    event ProposalLaunched(address indexed proposer, address indexed executor, uint256 indexed proposalId);

    ITimelock public immutable TIMELOCK;

    Proposers.State internal _proposers;

    constructor(address config, address timelock) ConfigurationProvider(config) {
        TIMELOCK = ITimelock(timelock);
    }

    function submit(ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _proposers.checkProposer(msg.sender);
        Proposer memory proposer = _proposers.get(msg.sender);
        newProposalId = TIMELOCK.submit(proposer.executor, calls);
        emit ProposalLaunched(proposer.account, proposer.executor, newProposalId);
    }

    function cancelAll() external {
        _proposers.checkAdminProposer(CONFIG, msg.sender);
        TIMELOCK.cancelAll();
    }

    // ---
    // Proposers & Executors Management
    // ---

    function registerProposer(address proposer, address executor) external {
        _checkAdminExecutor(msg.sender);
        _proposers.register(proposer, executor);
    }

    function unregisterProposer(address proposer) external {
        _checkAdminExecutor(msg.sender);
        _proposers.unregister(CONFIG, proposer);
    }

    function getProposer(address account) external view returns (Proposer memory proposer) {
        proposer = _proposers.get(account);
    }

    function getProposers() external view returns (Proposer[] memory proposers) {
        proposers = _proposers.all();
    }

    function isProposer(address account) external view returns (bool) {
        return _proposers.isProposer(account);
    }

    function isExecutor(address account) external view returns (bool) {
        return _proposers.isExecutor(account);
    }
}
