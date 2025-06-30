import "./Common.spec";
import "./Timelock.spec";

// Run link, all rules: https://vaas-stg.certora.com/output/37629/cc02fdb61b6e41a4a51a211dee7fc633?anonymousKey=c7415609b7bc79ed4e543f81c12546ef6b33a920
// Status, all rules: PASSING

// cancelAllNonExecutedProposals cannot be called by any address other than the
// governance address
rule EPT_C1_only_governance_can_cancel() {
    env e;
    cancelAllNonExecutedProposals(e);
    assert(e.msg.sender == getGovernance());
}

// after cancelAllNonExecutedProposals is called, no previously submitted
// proposal can be scheduled at any point in time
rule EPT_C2_cant_schedule_after_cancelling() {
    env e1;
    uint256 proposalId;
    satisfy(getProposalDetails(proposalId).status == ExecutableProposals.Status.Submitted);
    require(getProposalDetails(proposalId).submittedAt <= e1.block.timestamp);
    // require that proposal data structure is still consistent. Otherwise
    // proposalId will be beyond proposalsCount which breaks the cancellation.
    requireInvariant outOfBoundsProposalDoesNotExist(proposalId);

    cancelAllNonExecutedProposals(e1);

    env e2;
    require(e1.block.timestamp <= e2.block.timestamp);

    assert(!canSchedule(e2, proposalId));
    schedule@withrevert(e2, proposalId);
    assert(lastReverted);

}

// after cancelAllNonExecutedProposals is called, no previously submitted
// proposal (including scheduled ones) can be executed or emergency executed at
// any point in time
rule EPT_C3_cant_execute_or_emergencyexecute_after_cancelling() {
    env e1;
    uint256 proposalId;
    satisfy(getProposalDetails(proposalId).status == ExecutableProposals.Status.Submitted);
    require(getProposalDetails(proposalId).submittedAt <= e1.block.timestamp);
    // require that proposal data structure is still consistent. Otherwise
    // proposalId will be beyond proposalsCount which breaks the cancellation.
    requireInvariant outOfBoundsProposalDoesNotExist(proposalId);

    cancelAllNonExecutedProposals(e1);

    env e2;
    require(e1.block.timestamp <= e2.block.timestamp);

    execute@withrevert(e2, proposalId);
    assert(lastReverted);

    emergencyExecute@withrevert(e2, proposalId);
    assert(lastReverted);
}