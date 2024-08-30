using EscrowA as EscrowA;
using EscrowB as EscrowB;

methods {
	// envfrees
	function getProposer(address account) external returns (Proposers.Proposer memory) envfree;
    function getProposerIndexFromExecutor(address proposer) external returns (uint32) envfree;
	function getState() external returns (DualGovernanceHarness.DGHarnessState) envfree;
	function isUnset(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
	function isNormal(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
	function isVetoSignalling(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
	function isVetoSignallingDeactivation(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
	function isVetoCooldown(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
	function isRageQuit(DualGovernanceHarness.DGHarnessState state) external returns (bool) envfree;
	function getVetoSignallingActivatedAt() external returns (DualGovernanceHarness.Timestamp) envfree;
	function getRageQuitEscrow() external returns (address) envfree;
	function getVetoSignallingEscrow() external returns (address) envfree;
	function getFirstSeal() external returns (uint256) envfree;
	function getSecondSeal() external returns (uint256) envfree;

	// envfrees escrow
	function EscrowA.isRageQuitState() external returns (bool) envfree;
	function EscrowB.isRageQuitState() external returns (bool) envfree;

	// route escrow functions to implementations while
	// still allowing escrow addresses to vary
	function _.startRageQuit(DualGovernanceHarness.Duration, DualGovernance.Duration) external => DISPATCHER(true);
	function _.initialize(DualGovernanceHarness.Duration) external => DISPATCHER(true);
	function _.setMinAssetsLockDuration(DualGovernanceHarness.Duration newMinAssetsLockDuration) external => DISPATCHER(true);
	function _.getRageQuitSupport() external => DISPATCHER(true);
	function _.isRageQuitFinalized() external => DISPATCHER(true);


	// TODO check these NONDETs. So far they seem pretty irrelevant to the 
	// rules in scope for this contract.
	// This is reached by Escrow.withdrawETH() and makes a lowlevel 
	// call on amount causing a HAVOC. 
	function Address.sendValue(address recipient, uint256 amount) internal => NONDET;
	// This is reached by ResealManager.reseal and makes a low-level call
	// on target which havocs all contracts. (And we can't NONDET functions
	// that return bytes).
	function Address.functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) => CVLFunctionCallWithValue(target, data, value);
	// This function belongs to ISealble which we do not have an implementation
	// of and it causes a havoc of all contracts.
	// It is reached by ResealManager.reaseal/resume
	function _.getResumeSinceTimestamp() external => CONSTANT;
	// This function belongs to IOnable which we do not have an implementation
	// of and it causes a havoc of all contracts. It is reached by EPT.
	// transferExecutorOwnership
	function _.transferOwnership(address newOwner) external => NONDET;
	// This is in is reached by 2 calls in EPT and reaches a call to 
	// functionCallWithValue. (It may be subsumed by the summary to 
	// Address.functionCallWithValue)
	function Executor.execute(address, uint256, bytes) external returns (bytes) => NONDET;

	// This NONDET is meant to address a timeout of dg_kp_2
	// for which EPT is a significant bottleneck but not
	// really needed for verifying DG. We also have separate rules for EPT.
	function EmergencyProtectedTimelock.submit(address executor, 
		DualGovernanceHarness.ExternalCall[] calls) external returns (uint256) => NONDET;

	

}

// Ideally we would return a ghost but then we run into the tool bug
// where a ghost declared bytes is actually given type "hashblob"
// and this bug won't be fixed :)
function CVLFunctionCallWithValue(address target, bytes data, uint256 value) returns bytes {
	bytes ret;
	return ret;
}

function escrowAddressIsRageQuit(address escrow) returns bool {
	if (escrow == EscrowA) {
		return EscrowA.isRageQuitState();
	} else if (escrow == EscrowB) {
		return EscrowB.isRageQuitState();
	}
	return false;
}

function rageQuitThresholdAssumptions() returns bool {
	return getFirstSeal() > 0 && getSecondSeal() > getFirstSeal();
}

// for any registered proposer, his index should be ≤ the length of 
// the array of proposers
// “for each entry in the struct in the array, show that the index inside is the same as the real array index”
// NOTE: this has not been addressed by customer, so this should fail now.
rule w2_1a_indexes_match (method f) {
	env e;
	calldataarg args;
	Proposers.Proposer[] proposers = getProposers(e);
	require proposers.length <= 5; // loop unrolling
	uint256 idx;
	require idx <= proposers.length;
	mathint get_proposers_length = proposers.length;
	address proposer_addr = proposers[idx].account;
	require getProposerIndexFromExecutor(proposer_addr) - 1 < proposers.length;
	require getProposerIndexFromExecutor(proposer_addr) - 1 == idx;

	f(e, args);
	// Strategy 1: check proposerIndex is <= proposers array length
	assert getProposerIndexFromExecutor(proposer_addr) - 1 < proposers.length;
	// Strategy 2: check proposerIndex == real array index
	assert getProposerIndexFromExecutor(proposer_addr) - 1 == idx;
}

//  Proposals cannot be executed in the Veto Signaling (both parent state and
// Deactivation sub-state) and Rage Quit states.
rule dg_kp_1_proposal_execution {
	env e;
	uint256 proposal_id;
	scheduleProposal(e, proposal_id);
	DualGovernanceHarness.DGHarnessState state = getState();
	assert !isVetoSignalling(state) && !isRageQuit(state);
	// This throws a type error wherein CLV claims DGHarnessState.VetoSignaling
	// does not exist -- it seems like it starts to assume the type is a struct
	// if you nest more than one deep
	// DualGovernanceHarness.DGHarnessState.VetoSignaling && state != DualGovernanceHarness.DGHarnessState.RageQuit;
}

// NOTE: moved this to other spec file while fixing timeout
// Proposals cannot be submitted in the Veto Signaling Deactivation sub-state or in the Veto Cooldown state.
rule dg_kp_2_proposal_submission {
	env e;
	DualGovernanceHarness.ExternalCall[] calls;
	submitProposal(e, calls);
	DualGovernanceHarness.DGHarnessState state = getState();
	assert !isVetoSignallingDeactivation(state) && !isVetoCooldown(state);
}

// If a proposal was submitted after the last time the Veto Signaling state was 
// activated, then it cannot be executed in the Veto Cooldown state.
rule dg_kp_3_cooldown_execution (method f) {
	calldataarg args;
	env e;
	uint256 proposalId;
	uint256 id;
	ExecutableProposals.Status proposal_status;
	address executor;
	DualGovernanceHarness.Timestamp submittedAt;
	DualGovernanceHarness.Timestamp scheduledAt;
	(id, proposal_status, executor, submittedAt, scheduledAt) =
		getProposalInfoHarnessed(e, proposalId);

	scheduleProposal(e, proposalId);

	// This requires affects the state that was stepped into at the start of
	// the scheduleProposal call
	require isVetoCooldown(getState());
	DualGovernanceHarness.Timestamp vetoSignallingActivatedAt =
		getVetoSignallingActivatedAt();
	assert submittedAt <= vetoSignallingActivatedAt;
}

// One rage quit cannot start until the previous rage quit has finalized. In 
// other words, there can only be at most one active rage quit escrow at a time.
rule dg_kp_4_single_ragequit (method f) {
	env e;
	calldataarg args;
	require !escrowAddressIsRageQuit(getVetoSignallingEscrow());
	f(e, args);
	assert !escrowAddressIsRageQuit(getVetoSignallingEscrow());
}

// PP-1: Regardless of the state in which a proposal is submitted, if the 
// stakers are able to amass and maintain a certain amount of rage quit 
// support before the ProposalExecutionMinTimelock expires, they can extend 
// the timelock for a proportional time, according to the dynamic timelock 
// calculation.
// expected complexity: low
rule pp_kp_1_ragequit_extends {
	env e;
	// Assume not initially in VetoCooldown as we stay in this state
	// unless vetoCooldownDuration has passed
	require !isVetoCooldown(getState());

	activateNextState(e);

	// Note: the only two states where execution is possible are Normal 
	// and VetoCooldown
	// assuming there is enough ragequit support and the max timelock
	// has not exceeded:
	// - we do not transition into normal state
	// - if timelock is extended with ragequit support, we
	// cannot transition into VetoCooldown
	// require getVetoSignallingEscrow(e) == EscrowA;
	uint256 rageQuitSupport = getRageQuitSupportHarnessed(e);
	require !isDynamicTimelockPassed(e, rageQuitSupport);
	require rageQuitThresholdAssumptions();
	require getFirstSealRageQuitSupportCrossed(e);

	// we cannot transition to normal state above first seal ragequit support
	assert !isNormal(getState());
	assert !isVetoCooldown(getState());
}

// PP-2: It's not possible to prevent a proposal from being executed 
// indefinitely without triggering a rage quit.
// expected complexity: extra high
rule pp_kp_2_ragequit_trigger {
	env e;
	calldataarg args;

	uint256 rageQuitSupport = getRageQuitSupportHarnessed(e);
	require rageQuitThresholdAssumptions();
	require getFirstSealRageQuitSupportCrossed(e);

	// Assumptions about waiting long enough:
	// Assume we have waited long enough if in VetoSignalling
	require isDynamicTimelockPassed(e, rageQuitSupport);
	// Assume we wait enough time for deactivation if needed
	require isVetoSignallingReactivationPassed(e);
	// Assume we have waited enough time to exit deactivation if needed
	require isVetoSignallingDeactivationPassed(e);

	DualGovernanceHarness.DGHarnessState old_state = getState();
	activateNextState(e);
	DualGovernanceHarness.DGHarnessState new_state = getState();

	// from normal we eventually make forward progress into veto signalling
	assert isNormal(old_state) => isVetoSignalling(new_state);
	// from veto signalling we either make forward progress
	// into rageQuit or vetoSignallingDeactivation
	// (and we show forward progress is eventually made
	// from vetoSignallingDeactivation)
	assert isVetoSignalling(old_state) => 
		isRageQuit(new_state) || isVetoSignallingDeactivation(new_state);
	// From VetoSignallingDeactivation we make forward progress
	// into rageQuit or vetoSignallingCooldown
	// (and proposal execution is possible from cooldown)
	assert isVetoSignallingDeactivation(old_state) =>
		isRageQuit(new_state) || isVetoCooldown(new_state);
}

// PP-3: It's not possible to block proposal submission indefinitely.
// expected complexity: high
rule pp_kp_3_no_indefinite_proposal_submission_block {
	env e;

	uint256 rageQuitSupport = getRageQuitSupportHarnessed(e);
	// Assume we have waited long enough
	require rageQuitThresholdAssumptions();
	require isVetoSignallingDeactivationMaxDurationPassed(e) && isVetoCooldownDurationPassed(e);


	DualGovernanceHarness.DGHarnessState old_state = getState();
	activateNextState(e);
	DualGovernanceHarness.DGHarnessState new_state = getState();

	// Show that from any state in which proposal submission is disallowed, we must step on given our waiting time
	assert isVetoCooldown(old_state) => isNormal(new_state) || isVetoSignalling(new_state);
	assert isVetoSignallingDeactivation(old_state) => isVetoCooldown(new_state) || isVetoSignalling(new_state) || isRageQuit(new_state);
}

// PP-4: Until the Veto Signaling Deactivation sub-state transitions to Veto 
// Cooldown, there is always a possibility (given enough rage quit support) of 
// canceling Deactivation and returning to the parent state (possibly 
// triggering a rage quit immediately afterwards).
rule pp_kp_4_veto_signalling_deactivation_cancellable() {
	env e;
	require isVetoSignallingDeactivation(getState());
	require rageQuitThresholdAssumptions();
	require getSecondSealRageQuitSupportCrossed(e);
	activateNextState(e);

	// the only way out of veto signalling deactivation that does not go back to the parent is veto cooldown,
	// so if we can't go here, there is no way to bypass the rage quit support
	assert !isVetoCooldown(getState());
	// and we also don't want to be stuck in deactivation, but have a way back to the parent
	satisfy isVetoSignalling(getState());
}

// If proposal submission succeeds, the system was in on of these states: Normal, Veto Signalling, Rage Quit
rule dg_states_1_proposal_submission_states() {
	env e;
	calldataarg args;
	submitProposal(e, args);
	// we take the state after and not before, because state transitions are triggered at the start of actions,
	// not at the end of the ones that caused them to become possible
	DualGovernanceHarness.DGHarnessState state = getState();

	assert isNormal(state) || isVetoSignalling(state) || isRageQuit(state);
}

// If proposal scheduling succeeds, the system was in one of these states: Normal, Veto Cooldown
rule dg_states_2_proposal_scheduling_states() {
	env e;
	calldataarg args;
	scheduleProposal(e, args);
	// we take the state after and not before, because state transitions are triggered at the start of actions,
	// not at the end of the ones that caused them to become possible
	DualGovernanceHarness.DGHarnessState state = getState();

	assert isNormal(state) || isVetoCooldown(state);
}

// Only specified transitions are possible 
rule dg_transitions_1_only_legal_transitions() {
	env e;
	DualGovernanceHarness.DGHarnessState old_state = getState();
	activateNextState(e);
	DualGovernanceHarness.DGHarnessState new_state = getState();
	// we are not interested in the cases where no transition happened
	require old_state != new_state;

	require rageQuitThresholdAssumptions();

	if(isNormal(old_state)) {
		assert isVetoSignalling(new_state);
	} else if(isVetoSignalling(old_state)) {
		assert isRageQuit(new_state) || isVetoSignallingDeactivation(new_state);
	} else if(isVetoSignallingDeactivation(old_state)) {
		assert isVetoSignalling(new_state) || 
			isVetoCooldown(new_state) ||
			isRageQuit(new_state);
	} else if(isVetoCooldown(old_state)) {
		assert isNormal(new_state) || isVetoSignalling(new_state);
	} else if(isRageQuit(old_state)) {
		assert isVetoSignalling(new_state) || isVetoCooldown(new_state);
	} else {
		// unset state should not be reachable
		assert false;
	}
}