// Run link, all rules: https://prover.certora.com/output/37629/767560f4481c46368354f87bdd7d114a?anonymousKey=cc526f2e7597b55862233fd51cce8db4c120e56f
// Status, all rules: PASSING

// submitProposal cannot be called by any address other than the
// TimelockedGovernance.GOVERNANCE() address.
rule TG1_only_governance_can_submit_proposal() {
    env e;
    calldataarg args;
    submitProposal(e, args);
    assert(e.msg.sender == GOVERNANCE(e));
}

// cancelAllPendingProposals cannot be called by any address other than the
// TimelockedGovernance.GOVERNANCE() address.
rule TG2_only_governance_can_cancel_proposals() {
    env e;
    calldataarg args;
    cancelAllPendingProposals(e, args);
    assert(e.msg.sender == GOVERNANCE(e));
}