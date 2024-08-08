// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

struct Proposer {
    bool isAdmin;
    address account;
    address executor;
}

/// @title Proposers Library
/// @dev This library manages proposers and their assigned executors in a governance system, providing functions to register,
/// unregister, and verify proposers and their roles. It ensures proper assignment and validation of proposers and executors.
library Proposers {
    using SafeCast for uint256;

    error CallerIsNotProposer(address caller);
    error CallerIsNotAdminProposer(address caller);
    error ProposerNotRegistered(address proposer);
    error ProposerAlreadyRegistered(address proposer);
    error LastAdminProposerRemoval();

    event AdminExecutorSet(address indexed adminExecutor);
    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    struct ExecutorData {
        uint8 proposerIndexOneBased; // indexed from 1. The count of executors is limited
        address executor;
    }

    struct State {
        address[] proposers;
        mapping(address proposer => ExecutorData) executors;
        mapping(address executor => uint256 usagesCount) executorRefsCounts;
    }

    /// @dev Registers a proposer with an assigned executor.
    /// @param self The storage state of the Proposers library.
    /// @param proposer The address of the proposer to register.
    /// @param executor The address of the assigned executor.
    function register(State storage self, address proposer, address executor) internal {
        if (self.executors[proposer].proposerIndexOneBased != 0) {
            revert ProposerAlreadyRegistered(proposer);
        }
        self.proposers.push(proposer);
        self.executors[proposer] = ExecutorData(self.proposers.length.toUint8(), executor);
        self.executorRefsCounts[executor] += 1;
        emit ProposerRegistered(proposer, executor);
    }

    /// @dev Unregisters a proposer.
    /// @param self The storage state of the Proposers library.
    /// @param adminExecutor The address of the admin executor.
    /// @param proposer The address of the proposer to unregister.
    function unregister(State storage self, address adminExecutor, address proposer) internal {
        uint256 proposerIndexToDelete;
        ExecutorData memory executorData = self.executors[proposer];
        unchecked {
            proposerIndexToDelete = executorData.proposerIndexOneBased - 1;
        }
        if (proposerIndexToDelete == type(uint256).max) {
            revert ProposerNotRegistered(proposer);
        }

        uint256 lastProposerIndex = self.proposers.length - 1;
        if (proposerIndexToDelete != lastProposerIndex) {
            self.proposers[proposerIndexToDelete] = self.proposers[lastProposerIndex];
        }
        self.proposers.pop();
        delete self.executors[proposer];

        address executor = executorData.executor;
        if (executor == adminExecutor && self.executorRefsCounts[executor] == 1) {
            revert LastAdminProposerRemoval();
        }

        self.executorRefsCounts[executor] -= 1;
        emit ProposerUnregistered(proposer, executor);
    }

    /// @dev Retrieves all registered proposers.
    /// @param self The storage state of the Proposers library.
    /// @return proposers An array of structs representing all registered proposers.
    function all(State storage self) internal view returns (Proposer[] memory proposers) {
        proposers = new Proposer[](self.proposers.length);
        for (uint256 i = 0; i < proposers.length; ++i) {
            proposers[i] = get(self, self.proposers[i]);
        }
    }

    /// @dev Retrieves the details of a specific proposer.
    /// @param self The storage state of the Proposers library.
    /// @param account The address of the proposer.
    /// @return proposer The struct representing the details of the proposer.
    function get(State storage self, address account) internal view returns (Proposer memory proposer) {
        ExecutorData memory executorData = self.executors[account];
        if (executorData.proposerIndexOneBased == 0) {
            revert ProposerNotRegistered(account);
        }
        proposer.account = account;
        proposer.executor = executorData.executor;
    }

    /// @dev Checks if an account is a registered proposer.
    /// @param self The storage state of the Proposers library.
    /// @param account The address to check.
    /// @return A boolean indicating whether the account is a registered proposer.
    function isProposer(State storage self, address account) internal view returns (bool) {
        return self.executors[account].proposerIndexOneBased != 0;
    }

    /// @dev Checks if an account is an admin proposer.
    /// @param self The storage state of the Proposers library.
    /// @param adminExecutor The address of the admin executor
    /// @param account The address to check.
    /// @return A boolean indicating whether the account is an admin proposer.
    function isAdminProposer(State storage self, address adminExecutor, address account) internal view returns (bool) {
        ExecutorData memory executorData = self.executors[account];
        return executorData.proposerIndexOneBased != 0 && executorData.executor == adminExecutor;
    }

    /// @dev Checks if an account is an executor.
    /// @param self The storage state of the Proposers library.
    /// @param account The address to check.
    /// @return A boolean indicating whether the account is an executor.
    function isExecutor(State storage self, address account) internal view returns (bool) {
        return self.executorRefsCounts[account] > 0;
    }

    /// @dev Checks if msg.sender is a registered proposer and reverts if not.
    /// @param self The storage state of the Proposers library.
    function checkCallerIsProposer(State storage self) internal view {
        if (!isProposer(self, msg.sender)) {
            revert CallerIsNotProposer(msg.sender);
        }
    }

    /// @dev Checks if msg.sender is an admin proposer and reverts if not.
    /// @param self The storage state of the Proposers library.
    /// @param adminExecutor The address of the admin executor.
    function checkCallerIsAdminProposer(State storage self, address adminExecutor) internal view {
        checkCallerIsProposer(self);
        if (!isAdminProposer(self, adminExecutor, msg.sender)) {
            revert CallerIsNotAdminProposer(msg.sender);
        }
    }
}
