methods {
    function MAX_AFTER_SUBMIT_DELAY() external returns (Durations.Duration) envfree;
    function MAX_AFTER_SCHEDULE_DELAY() external returns (Durations.Duration) envfree;
    function MAX_EMERGENCY_MODE_DURATION() external returns (Durations.Duration) envfree;
    function MAX_EMERGENCY_PROTECTION_DURATION() external returns (Durations.Duration) envfree;

    function getProposal(uint256) external returns (ITimelock.Proposal) envfree;
    function getProposalsCount() external returns (uint256) envfree;
    function getEmergencyProtectionContext() external returns (EmergencyProtection.Context) envfree;
    function isEmergencyModeActive() external returns (bool) envfree;
    function getAdminExecutor() external returns (address) envfree;
    function getGovernance() external returns (address) envfree;
    function getAfterSubmitDelay() external returns (Durations.Duration) envfree;
    function getAfterScheduleDelay() external returns (Durations.Duration) envfree;

    // We do not model the calls executed through proposals
    function _.execute(address, uint256, bytes) external => nondetBytes() expect bytes;
}

// returns default empty bytes object, since we don't need to know anything about the returned value of execute in any of our rules
// specifying it like this instead of NONDET avoids a revert based on the returned value in EPT_9_EmergencyModeLiveness
function nondetBytes() returns bytes {
    bytes b;
    return b;
}

function proposalIsExecuted(uint proposalId) returns bool {
    return getProposal(proposalId).status == ExecutableProposals.Status.Executed;
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

invariant outOfBoundsProposalDoesNotExist(uint proposalId) proposalId == 0 || proposalId > getProposalsCount() => getProposal(proposalId).status == ExecutableProposals.Status.NotExist
    filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {}

/**
    @title A proposal cannot be scheduled for execution before at least ProposalExecutionMinTimelock has passed since its submission. 
*/
rule EPT_KP_1_SubmissionToSchedulingDelay {
    env e;
    uint proposalId;

    schedule(e, proposalId);

    assert getProposal(proposalId).submittedAt + getAfterSubmitDelay() <= e.block.timestamp;
}

/**
    @title A proposal cannot be executed until the emergency protection timelock has passed since it was scheduled.
*/
rule EPT_KP_2_SchedulingToExecutionDelay {
    env e;
    uint proposalId;

    execute(e, proposalId);

    assert getProposal(proposalId).scheduledAt + getAfterScheduleDelay() <= e.block.timestamp;
}

// These functions model the deactivation of the committees after the emergency protection elapses,
// and are used in place of directly getting the committee addresses in our rules 
// to make sure that anything we prove about the committee special actions is also guarded by the time
function effectiveEmergencyExecutionCommittee(env e) returns address {
    if (e.block.timestamp <= getEmergencyProtectionContext().emergencyProtectionEndsAfter || isEmergencyModeActive()) {
        return getEmergencyProtectionContext().emergencyExecutionCommittee;
    }
    return 0;
}

function effectiveEmergencyActivationCommittee(env e) returns address {
    if (e.block.timestamp <= getEmergencyProtectionContext().emergencyProtectionEndsAfter) {
        return getEmergencyProtectionContext().emergencyActivationCommittee;
    }
    return 0;
}

/**
    @title Emergency protection configuration changes are guarded by committees or admin executor
    We check here that the part of the state that should only be alterable by the respective emergency committees 
    or through an admin proposal is indeed not changed on any method call other than ones correctly authorized  
*/
rule EPT_1_EmergencyProtectionConfigurationGuarded(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    EmergencyProtection.Context before = getEmergencyProtectionContext();
    
    env e;
    require e.block.timestamp <= max_uint40;
    bool isEmergencyModePassed = before.emergencyModeEndsAfter <= e.block.timestamp;
    address effectiveEmergencyActivationCommittee = effectiveEmergencyActivationCommittee(e);
    address effectiveEmergencyExecutionCommittee = effectiveEmergencyExecutionCommittee(e);

    calldataarg args;
    f(e, args);

    EmergencyProtection.Context after = getEmergencyProtectionContext();

    assert before == after 
        // emergency mode activation
        || (after.emergencyModeEndsAfter != 0 && 
            before.emergencyActivationCommittee == after.emergencyActivationCommittee && 
            before.emergencyProtectionEndsAfter == after.emergencyProtectionEndsAfter &&
            before.emergencyExecutionCommittee == after.emergencyExecutionCommittee &&
            before.emergencyModeDuration == after.emergencyModeDuration &&
            before.emergencyGovernance == after.emergencyGovernance && 
            e.msg.sender == effectiveEmergencyActivationCommittee)
        // emergency mode deactivation
        || (after.emergencyModeEndsAfter == 0 && 
            after.emergencyActivationCommittee == 0 && 
            after.emergencyProtectionEndsAfter == 0 && 
            after.emergencyExecutionCommittee == 0 &&
            after.emergencyModeDuration == 0 &&
            after.emergencyGovernance == before.emergencyGovernance &&
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
    EmergencyProtection.Context context = getEmergencyProtectionContext();
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
    require getProposal(proposalId).status == ExecutableProposals.Status.Scheduled;
    env e;
    require e.msg.value == 0;
    require e.block.timestamp >= getProposal(proposalId).scheduledAt;
    require e.block.timestamp < max_uint40;
    emergencyExecute@withrevert(e, proposalId);
    bool reverted = lastReverted;

    assert e.msg.sender == effectiveEmergencyExecutionCommittee(e) => !reverted;
}

// Helper for EPT_10_ProposalTimestampConsistency because Proposal contains some other not easily comparable data
function proposalTimestampsEqual (ITimelock.Proposal a, ITimelock.Proposal b) returns bool {
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
        ITimelock.Proposal proposal_before = getProposal(proposalId);
        calldataarg args;
        uint submittedId = submit(e, args);

        assert proposalId != submittedId && proposalTimestampsEqual(proposal_before, getProposal(proposalId)) 
            || proposalId == submittedId && getProposal(submittedId).submittedAt == e.block.timestamp;

    } else if (f.selector == sig:schedule(uint).selector) {
        uint proposalId;
        ITimelock.Proposal proposal_before = getProposal(proposalId);
        uint proposalIdToSchedule;
        require proposalId != proposalIdToSchedule;
        schedule(e, proposalIdToSchedule);

        assert proposalTimestampsEqual(proposal_before, getProposal(proposalId))
            && getProposal(proposalIdToSchedule).scheduledAt == e.block.timestamp;

    } else if (f.selector == sig:execute(uint).selector) {
        uint proposalId;
        ITimelock.Proposal proposal_before = getProposal(proposalId);
        uint proposalIdToExecute;
        require proposalId != proposalIdToExecute;
        execute(e, proposalIdToExecute);

        // for the execution methods we also check that they update the status, since executedAt is not longer included as a timestamp, 
        // but EPT_3_EmergencyModeExecutionRestriction depends on the execution status being recorded correctly to be meaningful
        assert proposalTimestampsEqual(proposal_before, getProposal(proposalId))
            && proposalIsExecuted(proposalIdToExecute);
    } else if (f.selector == sig:emergencyExecute(uint).selector) {
        uint proposalId;
        ITimelock.Proposal proposal_before = getProposal(proposalId);
        uint proposalIdToExecute;
        require proposalId != proposalIdToExecute;
        emergencyExecute(e, proposalIdToExecute);

        assert proposalTimestampsEqual(proposal_before, getProposal(proposalId))
            && proposalIsExecuted(proposalIdToExecute);
    } else {
        uint proposalId;
        ITimelock.Proposal proposal_before = getProposal(proposalId);

        calldataarg args;
        f(e, args);

        assert proposalTimestampsEqual(proposal_before, getProposal(proposalId));
    }
}

/**
    @title Cancelled is a terminal state for a proposal, once cancelled it cannot transition to any other state
*/
rule EPT_11_TerminalityOfCancelled(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    uint proposalId;
    requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
    require getProposal(proposalId).status == ExecutableProposals.Status.Cancelled;

    env e;
    calldataarg args;
    f(e, args);

    assert getProposal(proposalId).status == ExecutableProposals.Status.Cancelled;
}