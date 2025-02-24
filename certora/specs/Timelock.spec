import "Common.spec";

// Run link, all rules: https://prover.certora.com/output/65266/0d6a23b06ec64de5b8c8f9a99d44b237?anonymousKey=5ffeef3cf04911c919cd40210c5fb686ac6cbdeb
// Status:
// - all rules except scheduled_proposals_above_schedule_delay, 
// executed_proposals_above_schedule_delay: PASSING
// - executed_proposals_above_schedule_delay: VIOLATED, 
// pending discusson on findings
// - scheduled_proposals_above_schedule_delay: VIOLATED
// pending discusson on findings

function getProposalDetailsNonReverting(uint proposalId) returns ITimelock.ProposalDetails {
        ITimelock.ProposalDetails defaultProposalDetails;
        // Note: this is written with requires clauses because
        // the prover will throw a syntax error if this is
        // written with assignments instead.
        require defaultProposalDetails.id == proposalId;
        require defaultProposalDetails.submittedAt == 0;
        require defaultProposalDetails.scheduledAt == 0;
        require defaultProposalDetails.executor == 0;
        require defaultProposalDetails.status == 
            ExecutableProposals.Status.NotExist;
        bool proposal_exists = currentContract._proposals.proposals[proposalId].data.status != ExecutableProposals.Status.NotExist;
        if (proposal_exists) {
            return getProposalDetails(proposalId);
        } else {
            return defaultProposalDetails;
        }
}

// This distinct function from getProposalDetailsNonReverting is needed
// to write the outOfBoundsProposalDoesNotExist invariant
function getProposalStatus(uint proposalId) returns ExecutableProposals.Status {
    return currentContract._proposals.proposals[proposalId].data.status;
}


function proposalIsExecuted(uint proposalId) returns bool {
    return getProposalDetailsNonReverting(proposalId).status == ExecutableProposals.Status.Executed;
}


// These functions model the deactivation of the committees after the emergency protection elapses,
// and are used in place of directly getting the committee addresses in our rules
// to make sure that anything we prove about the committee special actions is also guarded by the time
function effectiveEmergencyExecutionCommittee(env e) returns address {
    if (e.block.timestamp <= getEmergencyProtectionDetails().emergencyProtectionEndsAfter || isEmergencyModeActive()) {
        return getEmergencyExecutionCommittee(e);
    }
    return 0;
}

function effectiveEmergencyActivationCommittee(env e) returns address {
    if (e.block.timestamp <= getEmergencyProtectionDetails().emergencyProtectionEndsAfter) {
        return getEmergencyActivationCommittee();
    }
    return 0;
}

/**
    @title Executed is a terminal state for a proposal, once executed it cannot transition to any other state
    @notice Expected to fail due to an acknowledged bug whose fix is not merged yet
*/
rule W1_4_TerminalityOfExecuted(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    uint proposalId;
    requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
    require proposalIsExecuted(proposalId);

    env e;
    calldataarg args;
    f(e, args);

    assert proposalIsExecuted(proposalId);
}

invariant outOfBoundsProposalDoesNotExist(uint proposalId) proposalId == 0 || proposalId > getProposalsCount() => getProposalStatus(proposalId) == ExecutableProposals.Status.NotExist
    filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {}

invariant noProposalsSubmittedInFuture(uint proposalId, uint256 now) 
    getProposalStatus(proposalId) != ExecutableProposals.Status.NotExist =>
        getProposalDetailsNonReverting(proposalId).submittedAt <= now
{
    preserved with (env e) {
        // bind timestamp to now
        require e.block.timestamp == now;
        requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
    }
}
/**
    @title A proposal cannot be scheduled for execution before at least ProposalExecutionMinTimelock has passed since its submission. 
*/
rule EPT_KP_1_SubmissionToSchedulingDelay {
    env e;
    uint proposalId;

    schedule(e, proposalId);

    assert getProposalDetailsNonReverting(proposalId).submittedAt + getAfterSubmitDelay() <= e.block.timestamp;
}

/**
    @title A proposal cannot be executed until the emergency protection timelock has passed since it was scheduled.
*/
rule EPT_KP_2_SchedulingToExecutionDelay {
    env e;
    uint proposalId;

    execute(e, proposalId);

    assert getProposalDetailsNonReverting(proposalId).scheduledAt + getAfterScheduleDelay() <= e.block.timestamp;
}


/**
    @title Emergency protection configuration changes are guarded by committees or admin executor
    We check here that the part of the state that should only be alterable by the respective emergency committees 
    or through an admin proposal is indeed not changed on any method call other than ones correctly authorized  
*/
rule EPT_1_EmergencyProtectionConfigurationGuarded(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    IEmergencyProtectedTimelock.EmergencyProtectionDetails before = getEmergencyProtectionDetails();
    address emergencyGovBefore = getEmergencyGovernance();
    address emergencyActivationBefore = getEmergencyActivationCommittee();
    address emergencyExecutionBefore = getEmergencyActivationCommittee();
    
    env e;
    require e.block.timestamp <= max_uint40;
    bool isEmergencyModePassed = before.emergencyModeEndsAfter <= e.block.timestamp;
    address effectiveEmergencyActivationCommittee = effectiveEmergencyActivationCommittee(e);
    address effectiveEmergencyExecutionCommittee = effectiveEmergencyExecutionCommittee(e);

    calldataarg args;
    f(e, args);

    IEmergencyProtectedTimelock.EmergencyProtectionDetails after = getEmergencyProtectionDetails();
    address emergencyGovAfter = getEmergencyGovernance();
    address emergencyActivationAfter = getEmergencyActivationCommittee();
    address emergencyExecutionAfter = getEmergencyActivationCommittee();

    assert before == after 
        // emergency mode activation
        || (after.emergencyModeEndsAfter != 0 && 
            emergencyActivationBefore == emergencyActivationAfter &&
            before.emergencyProtectionEndsAfter == after.emergencyProtectionEndsAfter &&
            emergencyExecutionBefore == emergencyExecutionAfter &&
            before.emergencyModeDuration == after.emergencyModeDuration &&
            emergencyGovBefore == emergencyGovAfter &&
            e.msg.sender == effectiveEmergencyActivationCommittee)
        // emergency mode deactivation
        || (after.emergencyModeEndsAfter == 0 && 
            emergencyActivationAfter == 0 && 
            after.emergencyProtectionEndsAfter == 0 && 
            emergencyExecutionAfter == 0 &&
            after.emergencyModeDuration == 0 &&
            emergencyGovBefore == emergencyGovAfter &&
            // via time passing or execution committee
            (isEmergencyModePassed || e.msg.sender == effectiveEmergencyExecutionCommittee))
        // reconfiguration through proposal executed by admin executor
        || e.msg.sender == getAdminExecutor();

}

/**
    @title Only governance can schedule proposals.
*/
rule EPT_2a_SchedulingGovernanceOnly {
    env e;
    uint proposalId;

    schedule(e, proposalId);

    assert e.msg.sender == getGovernance();
}

/**
    @title Only governance can submit proposals.
*/
rule EPT_2b_SubmissionGovernanceOnly {
    env e;
    calldataarg args;
    submit(e, args);

    assert e.msg.sender == getGovernance();
}

/**
    @title If emergency mode is active, only emergency execution committee can execute proposals
*/
rule EPT_3_EmergencyModeExecutionRestriction(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    uint proposalId;
    requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
    bool executedBefore = proposalIsExecuted(proposalId);

    bool isEmergencyModeActivated = isEmergencyModeActive();

    env e;
    address effectiveEmergencyExecutionCommittee = effectiveEmergencyExecutionCommittee(e);
    
    calldataarg args;
    f(e, args);

    bool executedAfter = proposalIsExecuted(proposalId);

    assert isEmergencyModeActivated && !executedBefore && executedAfter => e.msg.sender == effectiveEmergencyExecutionCommittee;
}

/**
    @title Emergency Protection deactivation without emergency
    @notice This rule checks that our effectiveXXXCommittee functions correctly model the expected behaviour upon deactivating
            emergency mode by the timelock elapsing. It cannot directly catch any bugs in the solidity code, 
            but checks our helper functions which in turn make sure that other rules take the elapsing of the emergency protection into account.
            The usefullness of this rule depends on us using the effectiveXXXCommittee functions also in all other rules 
            where we check that something is guarded by a committee.
*/
rule EPT_5_EmergencyProtectionElapsed() {
    IEmergencyProtectedTimelock.EmergencyProtectionDetails context = getEmergencyProtectionDetails();
    // protected deployment mode was activated, but not emergency mode
    require context.emergencyProtectionEndsAfter != 0 && !isEmergencyModeActive();

    env e;
    // protection time has elapsed in our environment
    require e.block.timestamp > context.emergencyProtectionEndsAfter;

    assert effectiveEmergencyActivationCommittee(e) == 0 && effectiveEmergencyExecutionCommittee(e) == 0;
}

/**
    @title When emergency mode is active, the emergency execution committee can execute proposals successfully
*/
rule EPT_9_EmergencyModeLiveness {
    require isEmergencyModeActive();
    uint proposalId;
    requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
    require getProposalDetailsNonReverting(proposalId).status == ExecutableProposals.Status.Scheduled;
    env e;
    require e.msg.value == 0;
    require e.block.timestamp >= getProposalDetailsNonReverting(proposalId).scheduledAt;
    require e.block.timestamp >= getProposalDetailsNonReverting(proposalId).submittedAt;
    requireInvariant noProposalsSubmittedInFuture(proposalId, e.block.timestamp);
    require e.block.timestamp < max_uint40;

    // This function call here (crucially without withrevert) is here
    // just to introduce the constraint that the calls for the proposal
    // can be accessed without reverting -- otherwise we run into
    // uninteresting revert paths just on accessing this data structure.
    ExternalCalls.ExternalCall[] calls = getProposalCalls(e, proposalId);


    emergencyExecute@withrevert(e, proposalId);
    bool reverted = lastReverted;

    assert e.msg.sender == effectiveEmergencyExecutionCommittee(e) => !reverted;
}

// Helper for EPT_10_ProposalTimestampConsistency because Proposal contains some other not easily comparable data
function proposalTimestampsEqual (ITimelock.ProposalDetails a, ITimelock.ProposalDetails b) returns bool {
    return a.submittedAt == b.submittedAt && a.scheduledAt == b.scheduledAt;
}

/**
    @title Proposal timestamps reflect timelock actions
*/
rule EPT_10_ProposalTimestampConsistency(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    env e;
    require e.block.timestamp <= max_uint40;

    // For each function that should update a timestamp, we need to check that the correct timestamp of the correct proposal was updated,
    // while any proposal that was not the one the function acted on should remain unchanged.
    // For any other function, all proposals should have their timestamps unchanged.
    if (f.selector == sig:submit(address, ExternalCalls.ExternalCall[]).selector) {
        uint proposalId;
        requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
        ITimelock.ProposalDetails proposal_before = getProposalDetailsNonReverting(proposalId);
        calldataarg args;
        uint submittedId = submit(e, args);

        assert proposalId != submittedId && proposalTimestampsEqual(proposal_before, getProposalDetailsNonReverting(proposalId)) 
            || proposalId == submittedId && getProposalDetailsNonReverting(submittedId).submittedAt == e.block.timestamp;

    } else if (f.selector == sig:schedule(uint).selector) {
        uint proposalId;
        requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
        ITimelock.ProposalDetails proposal_before = getProposalDetailsNonReverting(proposalId);
        uint proposalIdToSchedule;
        require proposalId != proposalIdToSchedule;
        schedule(e, proposalIdToSchedule);

        assert proposalTimestampsEqual(proposal_before, getProposalDetailsNonReverting(proposalId))
            && getProposalDetailsNonReverting(proposalIdToSchedule).scheduledAt == e.block.timestamp;

    } else if (f.selector == sig:execute(uint).selector) {
        uint proposalId;
        requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
        ITimelock.ProposalDetails proposal_before = getProposalDetailsNonReverting(proposalId);
        uint proposalIdToExecute;
        require proposalId != proposalIdToExecute;
        execute(e, proposalIdToExecute);

        // for the execution methods we also check that they update the status, since executedAt is not longer included as a timestamp, 
        // but EPT_3_EmergencyModeExecutionRestriction depends on the execution status being recorded correctly to be meaningful
        assert proposalTimestampsEqual(proposal_before, getProposalDetailsNonReverting(proposalId))
            && proposalIsExecuted(proposalIdToExecute);
    } else if (f.selector == sig:emergencyExecute(uint).selector) {
        uint proposalId;
        requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
        ITimelock.ProposalDetails proposal_before = getProposalDetailsNonReverting(proposalId);
        uint proposalIdToExecute;
        require proposalId != proposalIdToExecute;
        emergencyExecute(e, proposalIdToExecute);

        assert proposalTimestampsEqual(proposal_before, getProposalDetailsNonReverting(proposalId))
            && proposalIsExecuted(proposalIdToExecute);
    } else {
        uint proposalId;
        requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
        ITimelock.ProposalDetails proposal_before = getProposalDetailsNonReverting(proposalId);

        calldataarg args;
        f(e, args);

        assert proposalTimestampsEqual(proposal_before, getProposalDetailsNonReverting(proposalId));
    }
}

/**
    @title Cancelled is a terminal state for a proposal, once cancelled it cannot transition to any other state
*/
rule EPT_11_TerminalityOfCancelled(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    uint proposalId;
    requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
    require getProposalDetailsNonReverting(proposalId).status == ExecutableProposals.Status.Cancelled;

    env e;
    calldataarg args;
    f(e, args);

    assert getProposalDetailsNonReverting(proposalId).status == ExecutableProposals.Status.Cancelled;
}

/*
 * All proposals are canceled after a governance change.
 * This is specified by showing that it is not possible to schedule any proposal
 * after a call to setGovernance
 */
rule EPT_12_GovChangeCancelsAll {
    env e;
    calldataarg args;
    address newGovernance;
    uint256 anyProposalId;
    requireInvariant outOfBoundsProposalDoesNotExist(anyProposalId);
    // To give more assurance about the quality of this property,
    // show that it is possible for a proposal to be schedulable
    // before the governance change given the setup of the rule.
    satisfy canSchedule(e, anyProposalId);
    ExecutableProposals.Status statusBefore = getProposalDetailsNonReverting(anyProposalId).status;
    setGovernance(e, newGovernance);

    // allow for time to pass between governance change
    // and an attempt to schedule
    env e2;
    require e2.block.timestamp >= e.block.timestamp;

    // It is not possible to schedule a proposal after a governance change
    assert !canSchedule(e2, anyProposalId);
    // And the status is cancelled (or it was already executed before the governance change)
    assert getProposalDetailsNonReverting(anyProposalId).status == ExecutableProposals.Status.Cancelled || 
        statusBefore == ExecutableProposals.Status.Executed ||
        statusBefore == ExecutableProposals.Status.NotExist;
}

invariant combined_delay_above_min_execution_delay()
    currentContract._timelockState.afterScheduleDelay + currentContract._timelockState.afterSubmitDelay >= MIN_EXECUTION_DELAY();

// This will not hold if setAfterSubmitDelay is called on a proposal that
// has already been executed, but this is an uninteresting case because
// the proposal was executed before the change.
invariant scheduled_proposals_above_submit_delay(uint256 proposalId,
    uint256 timestamp)
    getProposalDetailsNonReverting(proposalId).status == ExecutableProposals.Status.Scheduled =>
        getProposalDetailsNonReverting(proposalId).submittedAt + getAfterSubmitDelay() <= timestamp 
filtered { f -> f.selector != sig:setAfterSubmitDelay(EmergencyProtectedTimelock.Duration).selector }{
    preserved with (env e) {
        requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
        require e.block.timestamp == timestamp;
    }
}


// Note: we need to filter EmergencyProtectedTimelock.emergencyExecute(uint256)
// explicitly -- using a precondition that emergencyMode is not active
// will instead cause a break for the functions that step out of emergencyMode
// because this clause does not force the precondition to hold in the pre-state
// Similarly setAfterScheduleDelay is filtered because it will cause 
// uninteresting violations where the delay is changed on a proposal that
// was already executed
invariant executed_proposals_above_schedule_delay(uint256 proposalId,
    uint256 timestamp)
    getProposalDetailsNonReverting(proposalId).status == ExecutableProposals.Status.Executed =>
        getProposalDetailsNonReverting(proposalId).scheduledAt + getAfterScheduleDelay() <= timestamp 
filtered { f -> f.selector != sig:emergencyExecute(uint256).selector && 
    f.selector != sig:setAfterScheduleDelay(EmergencyProtectedTimelock.Duration).selector}{
    preserved with (env e) {
        requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
        require e.block.timestamp == timestamp;
    }
}

rule execute_waits_min_delay {
    env e;
    uint256 proposalId;
    uint256 submittedAt = getProposalDetailsNonReverting(proposalId).submittedAt;
    execute(e, proposalId);
    assert e.block.timestamp >= submittedAt + MIN_EXECUTION_DELAY();
}