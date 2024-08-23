using Configuration as CONFIG;

methods {
    function CONFIG.AFTER_SUBMIT_DELAY() external returns (Durations.Duration) envfree;
    function CONFIG.AFTER_SCHEDULE_DELAY() external returns (Durations.Duration) envfree;
    function getProposal(uint256) external returns (Proposals.Proposal) envfree;
    function getEmergencyState() external returns (EmergencyProtection.EmergencyState) envfree;

    // TODO: Improve this to instead resolving the inner unresolved calls to anything in EPT
    function Executor.execute(address, uint256, bytes) external returns (bytes) => NONDET;
}

// TODO: maybe we can get rid of the filter if we resolve the unresolved calls inside execute, 
//       right now we're just filtering to be in line with treating execute as a NONDET
/**
    @title Executed is a terminal state for a proposal, once executed it cannot transition to any other state
*/
rule W1_4_TerminalityOfExecuted(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    uint proposalId;
    require getProposal(proposalId).status == Proposals.Status.Executed;

    env e;
    calldataarg args;
    f(e, args);

    assert getProposal(proposalId).status == Proposals.Status.Executed;
}

/**
    @title A proposal cannot be scheduled for execution before at least ProposalExecutionMinTimelock has passed since its submission. 
*/
rule EPT_KP_1_SubmissionToSchedulingDelay {
    env e;
    uint proposalId;

    schedule(e, proposalId);

    assert getProposal(proposalId).submittedAt + CONFIG.AFTER_SUBMIT_DELAY() <= e.block.timestamp;
}

/**
    @title A proposal cannot be executed until the emergency protection timelock has passed since it was scheduled.
*/
rule EPT_KP_2_SchedulingToExecutionDelay {
    env e;
    uint proposalId;

    execute(e, proposalId);

    assert getProposal(proposalId).scheduledAt + CONFIG.AFTER_SCHEDULE_DELAY() <= e.block.timestamp;
}

/**
    @title Only governance can schedule proposals.
*/
rule EPT_2a_SchedulingGovernanceOnly {
    env e;
    uint proposalId;

    schedule(e, proposalId);

    assert e.msg.sender == currentContract._governance;
}

/**
    @title Only governance can submit proposals.
*/
rule EPT_2b_SubmissionGovernanceOnly {
    env e;
    calldataarg args;
    submit(e, args);

    assert e.msg.sender == currentContract._governance;
}

/**
    @title If emergency mode is active, only emergency execution committee can execute proposals
*/
rule EPT_3_EmergencyModeExecutionRestriction(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    uint proposalId;
    uint executedAtBefore = getProposal(proposalId).executedAt;

    bool isEmergencyModeActivated = getEmergencyState().isEmergencyModeActivated;
    address executionCommittee = getEmergencyState().executionCommittee;

    env e;
    calldataarg args;
    f(e, args);

    assert isEmergencyModeActivated && getProposal(proposalId).executedAt != executedAtBefore => e.msg.sender == executionCommittee;
}

// Helper for EPT_10_ProposalTimestampConsistency because Proposal contains some other not easily comparable data
function proposalTimestampsEqual (Proposals.Proposal a, Proposals.Proposal b) returns bool {
    return a.submittedAt == b.submittedAt && a.scheduledAt == b.scheduledAt && a.executedAt == b.executedAt;
}

/**
    @title Proposal timestamps reflect timelock actions
*/
rule EPT_10_ProposalTimestampConsistency(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    env e;
    require e.block.timestamp <= max_uint40;

    if (f.selector == sig:submit(address, Executor.ExecutorCall[]).selector) {
        uint proposalId;
        Proposals.Proposal proposal_before = getProposal(proposalId);
        calldataarg args;
        uint submittedId = submit(e, args);

        assert proposalId != submittedId && proposalTimestampsEqual(proposal_before, getProposal(proposalId)) 
            || proposalId == submittedId && getProposal(submittedId).submittedAt == e.block.timestamp;
    } else if (f.selector == sig:schedule(uint).selector) {
        uint proposalId;
        Proposals.Proposal proposal_before = getProposal(proposalId);
        uint proposalIdToSchedule;
        require proposalId != proposalIdToSchedule;
        schedule(e, proposalIdToSchedule);

        assert proposalTimestampsEqual(proposal_before, getProposal(proposalId))
            && getProposal(proposalIdToSchedule).scheduledAt == e.block.timestamp;
    } else if (f.selector == sig:execute(uint).selector) {
        uint proposalId;
        Proposals.Proposal proposal_before = getProposal(proposalId);
        uint proposalIdToExecute;
        require proposalId != proposalIdToExecute;
        execute(e, proposalIdToExecute);

        assert proposalTimestampsEqual(proposal_before, getProposal(proposalId))
            && getProposal(proposalIdToExecute).executedAt == e.block.timestamp;
    } else if (f.selector == sig:emergencyExecute(uint).selector) {
        uint proposalId;
        Proposals.Proposal proposal_before = getProposal(proposalId);
        uint proposalIdToExecute;
        require proposalId != proposalIdToExecute;
        emergencyExecute(e, proposalIdToExecute);

        assert proposalTimestampsEqual(proposal_before, getProposal(proposalId))
            && getProposal(proposalIdToExecute).executedAt == e.block.timestamp;
    } else {
        uint proposalId;
        Proposals.Proposal proposal_before = getProposal(proposalId);

        calldataarg args;
        f(e, args);

        assert proposalTimestampsEqual(proposal_before, getProposal(proposalId));
    }
}