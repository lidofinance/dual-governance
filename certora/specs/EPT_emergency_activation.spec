import "Common.spec";

// Run link, all rules: https://prover.certora.com/output/37629/fc008fd51f794201b67951e561e86d9b?anonymousKey=02e8017f8ae49872c44b7b4f62ad65b0bff5ee34
// Status, all rules: PASSING

// emergencyExecute cannot be called in normal mode
rule EPT_EA1_execute_not_in_normal() {
    env e;
    uint256 proposalId;
    bool inNormalMode = !isEmergencyModeActive();
    emergencyExecute(e, proposalId);
    assert(!inNormalMode);
}

// activateEmergencyMode cannot be called by any address other than the
// emergency activation committee address
rule EPT_EA2_activate_only_by_committee() {
    env e;
    activateEmergencyMode(e);
    assert(e.msg.sender == getEmergencyActivationCommittee());
}

// activateEmergencyMode cannot be called in emergency mode
rule EPT_EA3_activate_not_in_emergency_mode() {
    env e;
    bool inEmergencyMode = isEmergencyModeActive();
    activateEmergencyMode(e);
    assert(!inEmergencyMode);

}

// activateEmergencyMode changes mode from normal mode to emergency mode
rule EPT_EA4_activate_changes_to_emergency() {
    env e;

    // this only makes sense if emergency mode is activate for a non-zero time
    require(getEmergencyProtectionDetails().emergencyModeDuration > 0);

    activateEmergencyMode(e);
    assert(isEmergencyModeActive());
}

// activateEmergencyMode cannot be called after emergency protection end date
// passes
rule EPT_EA5_activate_not_after_protection_end() {
    env e;

    // avoids an overflow of Timestamp, check the comment in Timestamps.now()
    require(e.block.timestamp < 2^40);

    activateEmergencyMode(e);
    assert(e.block.timestamp <= getEmergencyProtectionDetails(e).emergencyProtectionEndsAfter);
}

// a proposal cannot be emergency executed by any address other than the
// emergency execution committee address
rule EPT_EA6_only_committee_can_emergency_execute() {
    env e;
    uint256 proposalId;
    address committee = getEmergencyExecutionCommittee();
    emergencyExecute(e, proposalId);
    assert(e.msg.sender == committee);
}

// a scheduled proposal can be emergency executed before the post-schedule delay
// passes
rule EPT_EA7_can_emergency_execute_before_delay_passes() {
    env e;
    uint256 proposalId;
    require(getProposalDetails(e, proposalId).status == ExecutableProposals.Status.Scheduled);
    uint40 scheduledAt = getProposalDetails(e, proposalId).scheduledAt;
    emergencyExecute(e, proposalId);
    satisfy(e.block.timestamp < scheduledAt + getAfterScheduleDelay());
}
