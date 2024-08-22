// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../contracts/libraries/Proposers.sol";
import "../../contracts/DualGovernance.sol";

contract DualGovernanceHarness is DualGovernance {
    using Proposers for Proposers.Context;
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
}
