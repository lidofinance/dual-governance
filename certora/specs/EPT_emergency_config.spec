import "./Common.spec"; 

// Run link, all rules: https://prover.certora.com/output/37629/e62d7601635a4bee8aea30901d44d343?anonymousKey=10a0da2d3998beee19bf4ac93f6893083ae772cd
// Status, all rules: PASSING

// emergency mode can only be entered or exited as a result of one of the
// following calls: activateEmergencyMode, deactivateEmergencyMode,
// emergencyReset
rule EPT_EC1_only_specific_functions_can_enter_or_exit(method f) {
    env e;
    bool before = isEmergencyModeActive();
    calldataarg args;
    f(e, args);
    assert(
        (before != isEmergencyModeActive()) => (
            f.selector == sig:activateEmergencyMode().selector ||
            f.selector == sig:deactivateEmergencyMode().selector ||
            f.selector == sig:emergencyReset().selector
        )
    );
}

// emergency activation committee address can only be changed as a result of one
// of the following calls: setEmergencyProtectionActivationCommittee,
// deactivateEmergencyMode, emergencyReset
rule EPT_EC2_only_specific_functions_can_change_activation_committee(method f) {
    env e;
    address before = getEmergencyActivationCommittee();
    calldataarg args;
    f(e, args);
    assert(
        (before != getEmergencyActivationCommittee()) => (
            f.selector == sig:setEmergencyProtectionActivationCommittee(address).selector ||
            f.selector == sig:deactivateEmergencyMode().selector ||
            f.selector == sig:emergencyReset().selector
        )
    );
}

// emergency execution committee address can only be changed as a result of one
// of the following calls: setEmergencyProtectionExecutionCommittee,
// deactivateEmergencyMode, emergencyReset
rule EPT_EC3_only_specific_functions_can_change_execution_committee(method f) {
    env e;
    address before = getEmergencyExecutionCommittee();
    calldataarg args;
    f(e, args);
    assert(
        (before != getEmergencyExecutionCommittee()) => (
            f.selector == sig:setEmergencyProtectionExecutionCommittee(address).selector ||
            f.selector == sig:deactivateEmergencyMode().selector ||
            f.selector == sig:emergencyReset().selector
        )
    );
}

// emergency governance address can only be changed as a result of a
// setEmergencyGovernance call
rule EPT_EC4_only_specific_function_can_change_governance(method f) {
    env e;
    address before = getEmergencyGovernance();
    calldataarg args;
    f(e, args);
    assert(
        (before != getEmergencyGovernance()) =>
            f.selector == sig:setEmergencyGovernance(address).selector
    );
}

// emergency mode duration can only be changed as a result of one of the
// following calls: setEmergencyModeDuration, deactivateEmergencyMode,
// emergencyReset
rule EPT_EC5_only_specific_functions_can_change_duration(method f) {
    env e;
    uint32 before = getEmergencyProtectionDetails().emergencyModeDuration;
    calldataarg args;
    f(e, args);
    assert(
        (before != getEmergencyProtectionDetails().emergencyModeDuration) => (
            f.selector == sig:setEmergencyModeDuration(Durations.Duration).selector ||
            f.selector == sig:deactivateEmergencyMode().selector ||
            f.selector == sig:emergencyReset().selector
        )
    );
}

// emergency_protection end date can only be changed as a result of one of the
// following calls: setEmergencyProtectionEndDate, deactivateEmergencyMode,
// emergencyReset
rule EPT_EC6_only_specific_functions_can_change_protection_end(method f) {
    env e;
    uint40 before = getEmergencyProtectionDetails().emergencyProtectionEndsAfter;
    calldataarg args;
    f(e, args);
    assert(
        (before != getEmergencyProtectionDetails().emergencyProtectionEndsAfter) => (
            f.selector == sig:setEmergencyProtectionEndDate(Timestamps.Timestamp).selector ||
            f.selector == sig:deactivateEmergencyMode().selector ||
            f.selector == sig:emergencyReset().selector
        )
    );
}

// setEmergencyProtectionActivationCommittee,
// setEmergencyProtectionExecutionCommittee, setEmergencyGovernance,
// setEmergencyModeDuration, setEmergencyProtectionEndDate cannot be called by
// any address other than the admin executor address
rule EPT_EC7_only_admin_can_call(method f)
filtered { f ->
    f.selector == sig:setEmergencyProtectionActivationCommittee(address).selector ||
    f.selector == sig:setEmergencyProtectionExecutionCommittee(address).selector ||
    f.selector == sig:setEmergencyGovernance(address).selector ||
    f.selector == sig:setEmergencyModeDuration(Durations.Duration).selector ||
    f.selector == sig:setEmergencyProtectionEndDate(Timestamps.Timestamp).selector
} {
    env e;
    calldataarg args;
    address adminExecutor = getAdminExecutor();
    f(e, args);
    assert(e.msg.sender == adminExecutor);
}
