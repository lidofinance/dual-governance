import "./Common.spec";

// Run link, all rules: https://prover.certora.com/output/37629/1705ba0828dc4c11bfd084b7ce534f40?anonymousKey=d23c493ef1cdc4912b810020a5c426e877a5943f
// Status, all rules: PASSING

// admin executor address can only be changed as a result of setAdminExecutor
// call
rule EPT_GC1_only_set_admin_execute_can_change_admin_executor(method f) {
    env e;
    address before = getAdminExecutor();
    calldataarg args;
    f(e, args);
    assert(before != getAdminExecutor() =>
        f.selector == sig:setAdminExecutor(address).selector
    );
}

// governance address can only be changed as a result of setGovernance (or
// emergenceReset, see the "Emergency mode deactivation") call
rule EPT_GC2_only_set_governance_can_set_governance(method f) {
    env e;
    address before = getGovernance();
    calldataarg args;
    f(e, args);
    assert(before != getGovernance() =>
        (f.selector == sig:setGovernance(address).selector ||
        f.selector == sig:emergencyReset().selector)
    );
}

// post-submit delay can only be changed as a result of setAfterSubmitDelay call
rule EPT_GC3_only_set_after_submit_delay_can_set_delay(method f) {
    env e;
    Durations.Duration before = getAfterSubmitDelay();
    calldataarg args;
    f(e, args);
    assert(before != getAfterSubmitDelay() =>
        f.selector == sig:setAfterSubmitDelay(Durations.Duration).selector
    );
}

// post-schedule delay can only be changed as a result of setAfterScheduleDelay
// call
rule EPT_GC4_only_set_after_schedule_delay_can_set_delay(method f) {
    env e;
    Durations.Duration before = getAfterScheduleDelay();
    calldataarg args;
    f(e, args);
    assert(before != getAfterScheduleDelay() =>
        f.selector == sig:setAfterScheduleDelay(Durations.Duration).selector
    );
}

// setGovernance, setAdminExecutor, setAfterSubmitDelay, setAfterScheduleDelay,
// transferExecutorOwnership cannot be called by any address other than the
// admin executor address
rule EPT_GC5_only_admin_executor_can_call_some_functions(method f)
filtered { f ->
    f.selector == sig:setGovernance(address).selector ||
    f.selector == sig:setAdminExecutor(address).selector ||
    f.selector == sig:setAfterSubmitDelay(Durations.Duration).selector ||
    f.selector == sig:setAfterScheduleDelay(Durations.Duration).selector ||
    f.selector == sig:transferExecutorOwnership(address, address).selector
} {
    env e;
    address executor = getAdminExecutor();
    calldataarg args;
    f(e, args);
    assert(e.msg.sender == executor);
}
