methods {
    // envfrees
    function DualGovernanceHarness.getProposer(address proposerAccount) external returns (Proposers.Proposer memory) envfree;
    function DualGovernanceHarness.getProposerIndexFromExecutor(address proposer) external returns (uint32) envfree;
    function DualGovernanceHarness.getState() external returns (DualGovernanceHarness.DGHarnessState) envfree;
    function DualGovernanceHarness.isUnset(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
    function DualGovernanceHarness.isNormal(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
    function DualGovernanceHarness.isVetoSignalling(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
    function DualGovernanceHarness.isVetoSignallingDeactivation(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
    function DualGovernanceHarness.isVetoCooldown(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
    function DualGovernanceHarness.isRageQuit(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
    function DualGovernanceHarness.getVetoSignallingActivatedAt() external returns (DualGovernanceHarness.Timestamp) envfree;
    function DualGovernanceHarness.getRageQuitEscrow() external returns (address) envfree;
    function DualGovernanceHarness.getVetoSignallingEscrow() external returns (address) envfree;
    function DualGovernanceHarness.getFirstSeal() external returns (uint256) envfree;
    function DualGovernanceHarness.getSecondSeal() external returns (uint256) envfree;
    function DualGovernanceHarness.isExecutor(address) external returns (bool) envfree;
    
    function EmergencyProtectedTimelock.MAX_AFTER_SUBMIT_DELAY() external returns (Durations.Duration) envfree;
    function EmergencyProtectedTimelock.MAX_AFTER_SCHEDULE_DELAY() external returns (Durations.Duration) envfree;
    function EmergencyProtectedTimelock.MAX_EMERGENCY_MODE_DURATION() external returns (Durations.Duration) envfree;
    function EmergencyProtectedTimelock.MAX_EMERGENCY_PROTECTION_DURATION() external returns (Durations.Duration) envfree;
    function EmergencyProtectedTimelock.MIN_EXECUTION_DELAY() external returns (Durations.Duration) envfree;

    function EmergencyProtectedTimelock.getProposalDetails(uint256) external returns (ITimelock.ProposalDetails) envfree;
    function EmergencyProtectedTimelock.getProposalsCount() external returns (uint256) envfree;
    function EmergencyProtectedTimelock.getEmergencyProtectionDetails() external returns (IEmergencyProtectedTimelock.EmergencyProtectionDetails) envfree;
    function EmergencyProtectedTimelock.isEmergencyModeActive() external returns (bool) envfree;
    function EmergencyProtectedTimelock.getAdminExecutor() external returns (address) envfree;
    function EmergencyProtectedTimelock.getGovernance() external returns (address) envfree;
    function EmergencyProtectedTimelock.getAfterSubmitDelay() external returns (Durations.Duration) envfree;
    function EmergencyProtectedTimelock.getAfterScheduleDelay() external returns (Durations.Duration) envfree;

    function EmergencyProtectedTimelock.getEmergencyGovernance() external returns (address) envfree;
    function EmergencyProtectedTimelock.getEmergencyActivationCommittee() external returns (address) envfree;
    function EmergencyProtectedTimelock.getEmergencyExecutionCommittee() external returns (address) envfree;

    // We do not model the calls executed through proposals
    function _.execute(address, uint256, bytes) external => nondetBytes() expect bytes;
    
    // This is reached by ResealManager.reseal and makes a low-level call
    // on target which havocs all contracts. (And we can't NONDET functions
    // that return bytes). The implementation of Address is meant
    // to be a safer alternative to directly using call, according to its
    // comments.
    function Address.functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) => CVLFunctionCallWithValue(target, data, value);
    // This function belongs to ISealable which we do not have an implementation
    // of and it causes a havoc of all contracts. It is reached by 
    // ResealManager.reseal/resume and addSealableWithdrawalBlocker
	// This is a view function so it must be safe to summarize this as NONDET.
    function _.getResumeSinceTimestamp() external => NONDET;
    // This is summarized as an uninterpreted function. (As in, this is constrained to return the same value for the same parameters, but otherwise
    // the return values are unconstrained)
	function _.callGetResumeSinceTimestamp(address sealable) internal => CVLCallGetResumeSinceTimestamp(sealable) expect (bool, uint256);
    // This function belongs to IOwnable which we do not have an implementation
    // of and it causes a havoc of all contracts. It is reached by EPT.
    // transferExecutorOwnership. It is not a view function, 
    // but from the description it likely only affects its own state.
    function _.transferOwnership(address newOwner) external => NONDET;
    // This is reached by 2 calls in EPT and reaches a call to 
    // functionCallWithValue. 
    function Executor.execute(address target, uint256 value, bytes payload) external => NONDET;
}

ghost CVLCallGetResumeSinceTimestampBool(address) returns bool; 
ghost CVLCallGetResumeSinceTimestampStamp(address) returns uint256; 
function CVLCallGetResumeSinceTimestamp(address sealable) returns (bool, uint256) {
	return (CVLCallGetResumeSinceTimestampBool(sealable),
		CVLCallGetResumeSinceTimestampStamp(sealable));
}

function CVLFunctionCallWithValue(address target, bytes data, uint256 value) returns bytes {
	bytes ret;
	return ret;
}


// returns default empty bytes object, since we don't need to know anything about the returned value of execute in any of our rules
// specifying it like this instead of NONDET avoids a revert based on the returned value in EPT_9_EmergencyModeLiveness
function nondetBytes() returns bytes {
    bytes b;
    return b;
}
