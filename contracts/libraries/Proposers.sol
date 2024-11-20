// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IndexOneBased, IndicesOneBased} from "../types/IndexOneBased.sol";

/// @title Proposers Library
/// @dev Manages proposers and their assigned executors in a governance system.
library Proposers {
    // ---
    // Errors
    // ---
    error InvalidExecutor(address executor);
    error InvalidProposerAccount(address account);
    error ProposerNotRegistered(address proposer);
    error ProposerAlreadyRegistered(address proposer);

    // ---
    // Events
    // ---

    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    // ---
    // Data Types
    // ---

    /// @notice The info about the registered proposer and associated executor.
    /// @param account Address of the proposer.
    /// @param executor The address of the executor assigned to execute proposals submitted by the proposer.
    struct Proposer {
        address account;
        address executor;
    }

    /// @notice Internal information about a proposer’s executor.
    /// @param proposerIndex The one-based index of the proposer associated with the `executor` from
    ///     the `Context.proposers` array.
    /// @param executor The address of the executor associated with the proposer.
    struct ExecutorData {
        /// @dev slot0: [0..31]
        IndexOneBased proposerIndex;
        /// @dev slot0: [32..191]
        address executor;
    }

    /// @notice The context of the Proposers library.
    /// @param proposers List of all registered proposers.
    /// @param executors Mapping of proposers to their executor data.
    /// @param executorRefsCounts Mapping of executors to the count of proposers associated
    ///     with each executor.
    struct Context {
        address[] proposers;
        mapping(address proposer => ExecutorData) executors;
        mapping(address executor => uint256 usagesCount) executorRefsCounts;
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Registers a proposer with an assigned executor.
    /// @param self The context of the Proposers library.
    /// @param proposerAccount The address of the proposer to register.
    /// @param executor The address of the executor to assign to the proposer.
    function register(Context storage self, address proposerAccount, address executor) internal {
        if (proposerAccount == address(0)) {
            revert InvalidProposerAccount(proposerAccount);
        }

        if (executor == address(0)) {
            revert InvalidExecutor(executor);
        }

        if (_isRegisteredProposer(self.executors[proposerAccount])) {
            revert ProposerAlreadyRegistered(proposerAccount);
        }

        self.proposers.push(proposerAccount);
        self.executors[proposerAccount] =
            ExecutorData({proposerIndex: IndicesOneBased.fromOneBasedValue(self.proposers.length), executor: executor});
        self.executorRefsCounts[executor] += 1;

        emit ProposerRegistered(proposerAccount, executor);
    }

    /// @notice Unregisters a proposer, removing its association with an executor.
    /// @param self The context of the Proposers library.
    /// @param proposerAccount The address of the proposer to unregister.
    function unregister(Context storage self, address proposerAccount) internal {
        ExecutorData memory executorData = self.executors[proposerAccount];

        _checkRegisteredProposer(proposerAccount, executorData);

        IndexOneBased lastProposerIndex = IndicesOneBased.fromOneBasedValue(self.proposers.length);
        IndexOneBased proposerIndex = executorData.proposerIndex;

        if (proposerIndex != lastProposerIndex) {
            address lastProposer = self.proposers[lastProposerIndex.toZeroBasedValue()];
            self.proposers[proposerIndex.toZeroBasedValue()] = lastProposer;
            self.executors[lastProposer].proposerIndex = proposerIndex;
        }

        self.proposers.pop();
        delete self.executors[proposerAccount];

        self.executorRefsCounts[executorData.executor] -= 1;

        emit ProposerUnregistered(proposerAccount, executorData.executor);
    }

    // ---
    // Getters
    // ---

    /// @notice Retrieves the details of a specific proposer.
    /// @param self The context of the Proposers library.
    /// @param proposerAccount The address of the proposer to retrieve.
    /// @return proposer A struct containing the proposer’s address and associated executor address.
    function getProposer(
        Context storage self,
        address proposerAccount
    ) internal view returns (Proposer memory proposer) {
        ExecutorData memory executorData = self.executors[proposerAccount];
        _checkRegisteredProposer(proposerAccount, executorData);

        proposer.account = proposerAccount;
        proposer.executor = executorData.executor;
    }

    /// @notice Retrieves all registered proposers.
    /// @param self The context of the Proposers library.
    /// @return proposers An array of `Proposer` structs representing all registered proposers.
    function getAllProposers(Context storage self) internal view returns (Proposer[] memory proposers) {
        proposers = new Proposer[](self.proposers.length);
        for (uint256 i = 0; i < proposers.length; ++i) {
            proposers[i] = getProposer(self, self.proposers[i]);
        }
    }

    /// @notice Checks if an account is a registered proposer.
    /// @param self The context of the Proposers library.
    /// @param account The address to check.
    /// @return bool `true` if the account is a registered proposer, otherwise `false`.
    function isProposer(Context storage self, address account) internal view returns (bool) {
        return _isRegisteredProposer(self.executors[account]);
    }

    /// @notice Checks if an account is an executor associated with any proposer.
    /// @param self The context of the Proposers library.
    /// @param account The address to check.
    /// @return bool `true` if the account is an executor, otherwise `false`.
    function isExecutor(Context storage self, address account) internal view returns (bool) {
        return self.executorRefsCounts[account] > 0;
    }

    /// @notice Checks that the given proposer is registered.
    function _checkRegisteredProposer(address proposerAccount, ExecutorData memory executorData) internal pure {
        if (!_isRegisteredProposer(executorData)) {
            revert ProposerNotRegistered(proposerAccount);
        }
    }

    /// @notice Checks if the given executor data belongs to a registered proposer.
    function _isRegisteredProposer(ExecutorData memory executorData) internal pure returns (bool) {
        return executorData.proposerIndex.isNotEmpty();
    }
}
