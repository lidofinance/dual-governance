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
    error ExecutorNotRegistered(address account);
    error ProposerNotRegistered(address proposer);
    error ProposerAlreadyRegistered(address proposer);

    // ---
    // Events
    // ---

    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerExecutorSet(address indexed proposer, address indexed executor);
    event ProposerCanCancelProposalsSet(address indexed proposer, bool canCancelProposals);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    // ---
    // Data Types
    // ---

    /// @notice The info about the registered proposer and associated executor.
    /// @param account Address of the proposer.
    /// @param executor The address of the executor assigned to execute proposals submitted by the proposer.
    /// @param canCancelProposals Indicates whether the proposer has the authority to cancel all proposals that are
    ///     submitted or scheduled but not yet executed.
    struct Proposer {
        address account;
        address executor;
        bool canCancelProposals;
    }

    /// @notice Internal information about a proposer’s executor and proposal cancellation permissions.
    /// @param proposerIndex The one-based index of the proposer associated with the `executor` from
    ///     the `Context.proposers` array.
    /// @param executor The address of the executor associated with the proposer.
    /// @param canCancelProposals Indicates if the proposer has authority to cancel all proposals that are
    ///     submitted or scheduled but not yet executed.
    struct ProposerData {
        /// @dev slot0: [0..31]
        IndexOneBased proposerIndex;
        /// @dev slot0: [32..191]
        address executor;
        /// @dev slot0: [192..192]
        bool canCancelProposals;
    }

    /// @notice The context of the Proposers library.
    /// @param proposers List of all registered proposers.
    /// @param proposersData A mapping that associates each proposer’s address with their respective proposer data.
    /// @param executorRefsCounts Mapping of executors to the count of proposers associated with each executor.
    struct Context {
        address[] proposers;
        mapping(address proposer => ProposerData) proposersData;
        mapping(address executor => uint256 usagesCount) executorRefsCounts;
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Registers a proposer with an assigned executor.
    /// @param self The context of the Proposers library.
    /// @param proposerAccount The address of the proposer to register.
    /// @param executor The address of the executor to assign to the proposer.
    /// @param canCancelProposals Indicates if the proposer has authority to cancel all proposals that are
    ///     submitted or scheduled but not yet executed.
    function register(
        Context storage self,
        address proposerAccount,
        address executor,
        bool canCancelProposals
    ) internal {
        if (proposerAccount == address(0)) {
            revert InvalidProposerAccount(proposerAccount);
        }

        if (executor == address(0)) {
            revert InvalidExecutor(executor);
        }

        if (_isRegisteredProposer(self.proposersData[proposerAccount])) {
            revert ProposerAlreadyRegistered(proposerAccount);
        }

        self.proposers.push(proposerAccount);
        self.proposersData[proposerAccount] = ProposerData({
            executor: executor,
            canCancelProposals: canCancelProposals,
            proposerIndex: IndicesOneBased.fromOneBasedValue(self.proposers.length)
        });
        self.executorRefsCounts[executor] += 1;

        emit ProposerRegistered(proposerAccount, executor);
    }

    /// @notice Updates the cancellation permissions for a registered proposer.
    /// @param self The context storage of the Proposers library.
    /// @param proposerAccount The address of the proposer to update permission to cancel proposals.
    /// @param canCancelProposals A boolean indicating whether the proposer has permission to cancel proposals.
    function setCanCancelProposals(Context storage self, address proposerAccount, bool canCancelProposals) internal {
        ProposerData memory proposerData = self.proposersData[proposerAccount];
        _checkRegisteredProposer(proposerAccount, proposerData);

        if (proposerData.canCancelProposals != canCancelProposals) {
            self.proposersData[proposerAccount].canCancelProposals = canCancelProposals;
            emit ProposerCanCancelProposalsSet(proposerAccount, canCancelProposals);
        }
    }

    /// @notice Updates the executor for a registered proposer.
    /// @param self The context storage of the Proposers library.
    /// @param proposerAccount The address of the proposer to update.
    /// @param executor The new executor address to assign to the proposer.
    function setProposerExecutor(Context storage self, address proposerAccount, address executor) internal {
        ProposerData memory proposerData = self.proposersData[proposerAccount];
        _checkRegisteredProposer(proposerAccount, proposerData);

        if (executor == address(0) || proposerData.executor == executor) {
            revert InvalidExecutor(executor);
        }

        self.proposersData[proposerAccount].executor = executor;

        self.executorRefsCounts[executor] += 1;
        self.executorRefsCounts[proposerData.executor] -= 1;

        emit ProposerExecutorSet(proposerAccount, executor);
    }

    /// @notice Unregisters a proposer, removing its association with an executor.
    /// @param self The context of the Proposers library.
    /// @param proposerAccount The address of the proposer to unregister.
    function unregister(Context storage self, address proposerAccount) internal {
        ProposerData memory proposerData = self.proposersData[proposerAccount];

        _checkRegisteredProposer(proposerAccount, proposerData);

        IndexOneBased lastProposerIndex = IndicesOneBased.fromOneBasedValue(self.proposers.length);
        IndexOneBased proposerIndex = proposerData.proposerIndex;

        if (proposerIndex != lastProposerIndex) {
            address lastProposer = self.proposers[lastProposerIndex.toZeroBasedValue()];
            self.proposers[proposerIndex.toZeroBasedValue()] = lastProposer;
            self.proposersData[lastProposer].proposerIndex = proposerIndex;
        }

        self.proposers.pop();
        delete self.proposersData[proposerAccount];

        self.executorRefsCounts[proposerData.executor] -= 1;

        emit ProposerUnregistered(proposerAccount, proposerData.executor);
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
        ProposerData memory proposerData = self.proposersData[proposerAccount];
        _checkRegisteredProposer(proposerAccount, proposerData);

        proposer.account = proposerAccount;
        proposer.executor = proposerData.executor;
        proposer.canCancelProposals = proposerData.canCancelProposals;
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
        return _isRegisteredProposer(self.proposersData[account]);
    }

    /// @notice Checks if an account is an executor associated with any proposer.
    /// @param self The context of the Proposers library.
    /// @param account The address to check.
    /// @return bool `true` if the account is an executor, otherwise `false`.
    function isExecutor(Context storage self, address account) internal view returns (bool) {
        return self.executorRefsCounts[account] > 0;
    }

    // ---
    // Checks
    // ---

    /// @notice Checks that a given account is a registered executor.
    /// @param self The storage context of the Proposers library.
    /// @param account The address to verify as a registered executor.
    function checkRegisteredExecutor(Context storage self, address account) internal view {
        if (!isExecutor(self, account)) {
            revert ExecutorNotRegistered(account);
        }
    }

    // ---
    // Private Methods
    // ---

    function _checkRegisteredProposer(address proposerAccount, ProposerData memory proposerData) internal pure {
        if (!_isRegisteredProposer(proposerData)) {
            revert ProposerNotRegistered(proposerAccount);
        }
    }

    function _isRegisteredProposer(ProposerData memory proposerData) internal pure returns (bool) {
        return proposerData.proposerIndex.isNotEmpty();
    }
}
