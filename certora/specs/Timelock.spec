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

    // TODO: Improve this to instead resolving the inner unresolved calls to anything in EPT
    function Executor.execute(address, uint256, bytes) external returns (bytes) => NONDET;
}

// TODO: maybe we can get rid of the filter if we resolve the unresolved calls inside execute, 
//       right now we're just filtering to be in line with treating execute as a NONDET
/**
    @title Executed is a terminal state for a proposal, once executed it cannot transition to any other state
    @notice Expected to fail due to an acknowledged bug whose fix is not merged yet
*/
rule W1_4_TerminalityOfExecuted(method f) filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
    uint proposalId;
    requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
    require getProposal(proposalId).status == ExecutableProposals.Status.Executed;

    env e;
    calldataarg args;
    f(e, args);

    assert getProposal(proposalId).status == ExecutableProposals.Status.Executed;
}

// invariant proposalHasSubmissionTimeIfItExists(uint proposalId) getProposal(proposalId).status != ExecutableProposals.Status.NotExist <=> getProposal(proposalId).submittedAt != 0 
//     filtered { f -> f.selector != sig:Executor.execute(address, uint256, bytes).selector } {
//         preserved {
//             requireInvariant outOfBoundsProposalDoesNotExist(proposalId);
//         }
//     }
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
    bool executedBefore = getProposal(proposalId).status == ExecutableProposals.Status.Executed;

    bool isEmergencyModeActivated = isEmergencyModeActive();

    env e;
    address effectiveEmergencyExecutionCommittee = effectiveEmergencyExecutionCommittee(e);
    
    calldataarg args;
    f(e, args);

    bool executedAfter = getProposal(proposalId).status == ExecutableProposals.Status.Executed;

    assert isEmergencyModeActivated && !executedBefore && executedAfter => e.msg.sender == effectiveEmergencyExecutionCommittee;
}

/**
    @title Emergency Protection deactivation without emergency
    @notice The usefullness of this rule depends on us using the effectiveXXXCommittee functions also in all other rules 
            where we check that something is guarded by the committee.
*/
rule EPT_5_EmergencyProtectionElapsed(method f) {
    EmergencyProtection.Context context = getEmergencyProtectionContext();
    // protected deployment mode was activated, but not emergency mode
    require context.emergencyProtectionEndsAfter != 0 && !isEmergencyModeActive();

    env e;
    // protection time has elapsed in our environment
    require e.block.timestamp > context.emergencyProtectionEndsAfter;

    assert effectiveEmergencyActivationCommittee(e) == 0 && effectiveEmergencyExecutionCommittee(e) == 0;
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

    } else {
        uint proposalId;
        ITimelock.Proposal proposal_before = getProposal(proposalId);

        calldataarg args;
        f(e, args);

        assert proposalTimestampsEqual(proposal_before, getProposal(proposalId));
    }
}