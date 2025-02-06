import "Common.spec";
import "Timelock.spec";

// Run link, all rules: https://prover.certora.com/output/37629/d2a8516197bf4e17bd40759b59ff1715?anonymousKey=34a7057d43147f4e693e10411f95d7464af700c4
// Status, all rules: PASSING

// deactivateEmergencyMode and emergencyReset can only be called in emergency
// mode
rule EPT_ED1_only_in_emergency_mode(method f)
filtered { f ->
    f.selector == sig:deactivateEmergencyMode().selector ||
    f.selector == sig:emergencyReset().selector
} {
    env e;
    calldataarg args;
    bool emergencyMode = isEmergencyModeActive();
    f(e, args);
    assert(emergencyMode);
}

// deactivateEmergencyMode can be called by anyone if emergency mode max
// duration passed since emergency mode activation
rule EPT_ED2_anyone_can_deactivate_after_timeout() {
    // establish a time when the emergency mode is activated
    env e1;
    require(!isEmergencyModeActive());
    activateEmergencyMode(e1);

    // keep a copy of the current storage state
    storage state = lastStorage;

    // make sure that deactivate can be called somehow. This makes sure that the
    // storage state itself does not lead to some artificial reverts.
    env e2;
    require(e1.block.timestamp + MAX_EMERGENCY_MODE_DURATION() <= e2.block.timestamp);
    deactivateEmergencyMode(e2);

    // now we do another call on the same state (i.e. the previous call never
    // happened) and check that it never reverts: it works for every sender.
    deactivateEmergencyMode@withrevert(e2) at state;
    assert(!lastReverted);
}

// deactivateEmergencyMode cannot be called by any address other than the admin
// executor address if emergency mode max duration did not pass since emergency
// mode activation
rule EPT_ED3_only_admin_can_deactivate_before_timeout() {
    env e1;
    require(!isEmergencyModeActive());
    activateEmergencyMode(e1);

    env e2;
    uint32 duration = getEmergencyProtectionDetails().emergencyModeDuration;
    require(e1.block.timestamp < e2.block.timestamp);
    require(e1.block.timestamp + duration > e2.block.timestamp);
    deactivateEmergencyMode(e2);
    assert(e2.msg.sender == getAdminExecutor());
}

// emergencyReset cannot be called by any address other than the emergency
// execution committee address
rule EPT_ED4_only_execution_committee_can_reset() {
    env e;
    address committee = getEmergencyExecutionCommittee();
    emergencyReset(e);
    assert(e.msg.sender == committee);
}

// deactivateEmergencyMode and emergencyReset deactivate emergency mode
rule EPT_ED5_deactivate_and_reset_actually_deactivate(method f)
filtered { f ->
    f.selector == sig:deactivateEmergencyMode().selector ||
    f.selector == sig:emergencyReset().selector
} {
    env e;
    calldataarg args;
    f(e, args);
    assert(!isEmergencyModeActive());
}

// deactivateEmergencyMode and emergencyReset set emergency activation committee
// address, emergency execution committee address, emergency mode duration, and
// emergency protection end date to zero
rule EPT_ED6_deactivate_and_reset_nullify_context(method f)
filtered { f ->
    f.selector == sig:deactivateEmergencyMode().selector ||
    f.selector == sig:emergencyReset().selector
} {
    env e;
    calldataarg args;
    f(e, args);
    assert(getEmergencyActivationCommittee() == 0);
    assert(getEmergencyExecutionCommittee() == 0);
    assert(getEmergencyProtectionDetails().emergencyModeDuration == 0);
    assert(getEmergencyProtectionDetails().emergencyProtectionEndsAfter == 0);
}

// emergencyReset changes governance address to the emergency governance address
rule EPT_ED7_reset_changes_governance_address() {
    env e;
    address emergencyGovernance = getEmergencyGovernance();
    emergencyReset(e);
    assert(getGovernance() == emergencyGovernance);

}

// after deactivateEmergencyMode or emergencyReset is called, no previously
// submitted proposal (including scheduled ones) can be executed or emergency
// executed at any point in time
rule EPT_ED8_no_proposals_after_deactivate_or_reset(method f)
filtered { f ->
    f.selector == sig:deactivateEmergencyMode().selector ||
    f.selector == sig:emergencyReset().selector
} {
    env e1;
    uint256 proposalId;
    require(getProposalDetails(proposalId).submittedAt <= e1.block.timestamp);
    // require that proposal data structure is still consistent. Otherwise
    // proposalId will be beyond proposalsCount which breaks the cancellation.
    requireInvariant outOfBoundsProposalDoesNotExist(proposalId);

    calldataarg args;
    f(e1, args);

    env e2;
    require(e1.block.timestamp <= e2.block.timestamp);

    bool check;
    if (check) {
        execute@withrevert(e2, proposalId);
        assert(lastReverted);
    } else {
        emergencyExecute@withrevert(e2, proposalId);
        assert(lastReverted);
    }
}
