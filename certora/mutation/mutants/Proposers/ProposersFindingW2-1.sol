// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IndexOneBased, IndicesOneBased} from "../types/IndexOneBased.sol";

/// @title Proposers Library
/// @dev This library manages proposers and their assigned executors in a governance system, providing functions to register,
/// unregister, and verify proposers and their roles. It ensures proper assignment and validation of proposers and executors.

// MUTATION
// At time of writing there is actually no mutation. This mutant
// is a placeholder saving version of Proposers when
// finding W2-1 was identified. At time of writing this
// finding has not yet been fixed.
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

    event AdminExecutorSet(address indexed adminExecutor);
    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    // ---
    // Data Types
    // ---

    /// @notice The info about the registered proposer and associated executor
    /// @param account Address of the proposer
    /// @param executor Address of the executor associated with proposer. When proposer submits proposals, they execution
    /// will be done with this address.
    struct Proposer {
        address account;
        address executor;
    }

    /// @notice The internal info about the proposer's executor data
    /// @param proposerIndex The one-based index of the proposer associated with the `executor` from
    /// the `Context.proposers` array
    /// @param executor The address of the executor associated with the proposer
    struct ExecutorData {
        /// @dev slot0: [0..31]
        IndexOneBased proposerIndex;
        /// @dev slot0: [32..191]
        address executor;
    }

    /// @notice The context of the Proposers library
    /// @param proposers The list of the registered proposers
    /// @param executors The mapping with the executor info of the registered proposers
    /// @param executorRefsCounts The mapping with the count of how many proposers is associated
    /// with given executor address
    struct Context {
        address[] proposers;
        mapping(address proposer => ExecutorData) executors;
        mapping(address executor => uint256 usagesCount) executorRefsCounts;
    }

    // ---
    // Main Functionality
    // ---

    /// @dev Registers a proposer with an assigned executor.
    /// @param self The storage state of the Proposers library.
    /// @param proposerAccount The address of the proposer to register.
    /// @param executor The address of the assigned executor.
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

    /// @dev Unregisters a proposer.
    /// @param self The storage state of the Proposers library.
    /// @param proposerAccount The address of the proposer to unregister.
    function unregister(Context storage self, address proposerAccount) internal {
        ExecutorData memory executorData = self.executors[proposerAccount];

        _checkRegisteredProposer(proposerAccount, executorData);

        IndexOneBased lastProposerIndex = IndicesOneBased.fromOneBasedValue(self.proposers.length);
        if (executorData.proposerIndex != lastProposerIndex) {
            self.proposers[executorData.proposerIndex.toZeroBasedValue()] =
                self.proposers[lastProposerIndex.toZeroBasedValue()];
        }

        self.proposers.pop();
        delete self.executors[proposerAccount];
        self.executorRefsCounts[executorData.executor] -= 1;

        emit ProposerUnregistered(proposerAccount, executorData.executor);
    }

    // ---
    // Getters
    // ---

    /// @dev Retrieves the details of a specific proposer.
    /// @param self The storage state of the Proposers library.
    /// @param proposerAccount The address of the proposer.
    /// @return proposer The struct representing the details of the proposer.
    function getProposer(
        Context storage self,
        address proposerAccount
    ) internal view returns (Proposer memory proposer) {
        ExecutorData memory executorData = self.executors[proposerAccount];
        _checkRegisteredProposer(proposerAccount, executorData);

        proposer.account = proposerAccount;
        proposer.executor = executorData.executor;
    }

    /// @dev Retrieves all registered proposers.
    /// @param self The storage state of the Proposers library.
    /// @return proposers An array of structs representing all registered proposers.
    function getAllProposers(Context storage self) internal view returns (Proposer[] memory proposers) {
        proposers = new Proposer[](self.proposers.length);
        for (uint256 i = 0; i < proposers.length; ++i) {
            proposers[i] = getProposer(self, self.proposers[i]);
        }
    }

    /// @dev Checks if an account is a registered proposer.
    /// @param self The storage state of the Proposers library.
    /// @param account The address to check.
    /// @return A boolean indicating whether the account is a registered proposer.
    function isProposer(Context storage self, address account) internal view returns (bool) {
        return _isRegisteredProposer(self.executors[account]);
    }

    /// @dev Checks if an account is an executor.
    /// @param self The storage state of the Proposers library.
    /// @param account The address to check.
    /// @return A boolean indicating whether the account is an executor.
    function isExecutor(Context storage self, address account) internal view returns (bool) {
        return self.executorRefsCounts[account] > 0;
    }

    /// @dev Checks that proposer with given executorData is registered proposer
    function _checkRegisteredProposer(address proposerAccount, ExecutorData memory executorData) internal pure {
        if (!_isRegisteredProposer(executorData)) {
            revert ProposerNotRegistered(proposerAccount);
        }
    }

    /// @dev Returns if the executorData belongs to registered proposer
    function _isRegisteredProposer(ExecutorData memory executorData) internal pure returns (bool) {
        return executorData.proposerIndex.isNotEmpty();
    }
}
