// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

struct Proposer {
    address proposer;
    address executor;
}

library Proposers {
    using SafeCast for uint256;

    error ProposerNotRegistered(address proposer);
    error ProposerAlreadyRegistered(address proposer);

    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    struct ExecutorData {
        uint8 proposerIndexOneBased; // indexed from 1. We don't wanna have many executors
        address executor;
    }

    struct State {
        address[] proposers;
        mapping(address proposer => ExecutorData) executors;
    }

    function executor(State storage self, address proposer) internal view returns (address) {
        return self.executors[proposer].executor;
    }

    function get(
        State storage self,
        address proposer_
    ) internal view returns (Proposer memory proposer, bool isRegistered) {
        ExecutorData memory executorData = self.executors[proposer_];
        if (executorData.proposerIndexOneBased != 0) {
            isRegistered = true;
            proposer.proposer = proposer_;
            proposer.executor = executorData.executor;
        }
    }

    function all(State storage self) internal view returns (Proposer[] memory proposers) {
        proposers = new Proposer[](self.proposers.length);
        address proposer;
        for (uint256 i = 0; i < proposers.length; ) {
            proposer = self.proposers[i];
            proposers[i].proposer = proposer;
            proposers[i].executor = self.executors[proposer].executor;
        }
    }

    function count(State storage self) internal view returns (uint256) {
        return self.proposers.length;
    }

    function register(State storage self, address proposer, address executor_) internal {
        if (self.executors[proposer].proposerIndexOneBased != 0) {
            revert ProposerAlreadyRegistered(proposer);
        }
        self.proposers.push(proposer);
        self.executors[proposer] = ExecutorData(self.proposers.length.toUint8(), executor_);
        emit ProposerRegistered(proposer, executor_);
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

    function isProposer(State storage self, address proposer) internal view returns (bool) {
        return self.executors[proposer].proposerIndexOneBased != 0;
    }
}
