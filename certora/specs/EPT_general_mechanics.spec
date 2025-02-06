import "./Common.spec";

// Run link, all rules: https://vaas-stg.certora.com/output/37629/6e0e18968c954f1b9bbe82a7dd0f5a38?anonymousKey=9d6b6f4027dde4ef92912614b73bac9969cf06af
// Status, all rules: PASSING

// submit cannot be called by any address other than the governance address
rule EPT_GM2_only_governance_can_call_submit() {
    env e;
    calldataarg args;
    submit(e, args);
    assert(e.msg.sender == getGovernance());
}

// schedule cannot be called by any address other than the governance address
rule EPT_GM3_only_governance_can_call_schedule() {
    env e;
    uint256 proposalId;
    schedule(e, proposalId);
    assert(e.msg.sender == getGovernance());
}

// a non-scheduled proposal cannot be executed or emergency executed at any
// point in time
rule EPT_GM4_non_scheduled_proposal_cant_be_executed() {
    env e;
    uint256 proposalId;
    ExecutableProposals.Status status = getProposalDetails(e, proposalId).status;
    
    // assume that "non-scheduled" means the status is not Scheduled
    require status != ExecutableProposals.Status.Scheduled;
    
    assert(!canExecute(e, proposalId));
    execute@withrevert(e, proposalId);
    assert(lastReverted);
    emergencyExecute@withrevert(e, proposalId);
    assert(lastReverted);
}

// an executed proposal cannot be re-executed or emergency re-executed at any
// point in time
rule EPT_GM5_executed_proposal_cant_be_executed() {
    env e;
    uint256 proposalId;
    require(getProposalDetails(e, proposalId).status == ExecutableProposals.Status.Executed);
    
    assert(!canExecute(e, proposalId));
    execute@withrevert(e, proposalId);
    assert(lastReverted);
    emergencyExecute@withrevert(e, proposalId);
    assert(lastReverted);
    
}

// a proposal cannot be scheduled before the post-submit delay passes since its
// submission
rule EPT_GM6_cant_schedule_before_post_submit_delay() {
    env e;
    uint256 proposalId;
    bool cur_time_is_before_afterSubmitDelay_elapsed = 
        e.block.timestamp < getProposalDetails(e, proposalId).submittedAt + getAfterSubmitDelay();
    require cur_time_is_before_afterSubmitDelay_elapsed;
    
    assert(!canSchedule(e, proposalId));
    schedule@withrevert(e, proposalId);
    assert(lastReverted);
}

// a scheduled proposal cannot be executed before the post-schedule delay passes
// since its scheduling
rule EPT_GM7_cant_execute_before_post_schedule_delay() {
    env e;
    uint256 proposalId;
    require(e.block.timestamp < getProposalDetails(e, proposalId).scheduledAt + getAfterScheduleDelay());
    
    assert(!canExecute(e, proposalId));
    execute@withrevert(e, proposalId);
    assert(lastReverted);
}
