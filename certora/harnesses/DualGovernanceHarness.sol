// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../contracts/libraries/Proposers.sol";
import "../../contracts/DualGovernance.sol";
// This is to make a type available for a NONDET summary
import {IExternalExecutor} from "../../contracts/interfaces/IExternalExecutor.sol";
// import "../../contracts/libraries/DualGovernanceStateMachine.sol";

contract DualGovernanceHarness is DualGovernance {
    using Proposers for Proposers.Context;
    using Proposers for Proposers.Proposer;
    using Tiebreaker for Tiebreaker.Context;
    using DualGovernanceStateMachine for DualGovernanceStateMachine.Context;

    constructor(
        ExternalDependencies memory dependencies,
        SanityCheckParams memory sanityCheckParams
    ) DualGovernance(dependencies, sanityCheckParams) {}

    // Return is uint32 which is the same as IndexOneBased
    function getProposerIndexFromExecutor(address proposer) external view returns (uint32) {
        return IndexOneBased.unwrap(_proposers.executors[proposer].proposerIndex);
    }

    function getState() external view returns (State) {
        return _stateMachine.state;
    }
}
