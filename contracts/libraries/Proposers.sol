// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

struct Proposer {
    address account;
    address executor;
}

library Proposers {
    using SafeCast for uint256;

    error ProposerNotRegistered(address proposer);
    error ProposerAlreadyRegistered(address proposer);

    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    struct ExecutorData {
        uint8 proposerIndexOneBased; // indexed from 1. The count of executors is limited
        address executor;
    }

    struct State {
        address[] proposers;
        mapping(address proposer => ExecutorData) executors;
    }

    function register(State storage self, address proposer, address executor) internal {
        if (self.executors[proposer].proposerIndexOneBased != 0) {
            revert ProposerAlreadyRegistered(proposer);
        }
        self.proposers.push(proposer);
        self.executors[proposer] = ExecutorData(self.proposers.length.toUint8(), executor);
        emit ProposerRegistered(proposer, executor);
    }

    function unregister(State storage self, address proposer) internal {
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
        emit ProposerUnregistered(proposer, executorData.executor);
    }

    function all(State storage self) internal view returns (Proposer[] memory proposers) {
        proposers = new Proposer[](self.proposers.length);
        for (uint256 i = 0; i < proposers.length; ++i) {
            proposers[i] = get(self, self.proposers[i]);
        }
    }

    function get(State storage self, address account) internal view returns (Proposer memory proposer) {
        ExecutorData memory executorData = self.executors[account];
        if (executorData.proposerIndexOneBased == 0) {
            revert ProposerNotRegistered(account);
        }
        proposer.account = account;
        proposer.executor = executorData.executor;
    }

    function isProposer(State storage self, address proposer) internal view returns (bool) {
        return self.executors[proposer].proposerIndexOneBased != 0;
    }
}
