methods {
	// envfrees
	function getProposer(address account) external returns (Proposers.Proposer memory) envfree;
    function getProposerIndexFromExecutor(address proposer) external returns (uint32) envfree;
	function getState() external returns (DualGovernanceStateMachine.State) envfree;

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

}

// Ideally we would return a ghost but then we run into the tool bug
// where a ghost declared bytes is actually given type "hashblob"
// and this bug won't be fixed :)
function CVLFunctionCallWithValue(address target, bytes data, uint256 value) returns bytes {
	bytes ret;
	return ret;
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
	assert false;
	uint256 proposal_id;
	scheduleProposal(proposalId);
	DualGovernanceStateMachine.State state = getState();
	assert state != state.VetoSignaling && state != state.RageQuit;
}

// Proposals cannot be submitted in the Veto Signaling Deactivation sub-state or in the Veto Cooldown state.
rule dg_kp_2_proposal_submission {
	assert false;
}

// If a proposal was submitted after the last time the Veto Signaling state was 
// activated, then it cannot be executed in the Veto Cooldown state.
rule dg_kp_3_cooldown_execution {
	assert false;
}

// One rage quit cannot start until the previous rage quit has finalized. In 
// other words, there can only be at most one active rage quit escrow at a time.
rule dg_kp_4_single_ragequit {
	assert false;
}