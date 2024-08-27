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

	// DualGovernanceConfig summaries
	// function _.isFirstSealRageQuitSupportCrossed(
	// 	DualGovernanceConfig.Context memory configContext, 
	// 	DualGovernanceHarness.PercentD16 rageQuitSupport) internal => 
	// isFirstRageQuitCrossedGhost(rageQuitSupport) expect bool;
	// function _.isSecondSealRageQuitSupportCrossed(
	// 	DualGovernanceConfig.Context memory configContext, 
	// 	DualGovernanceHarness.PercentD16 rageQuitSupport) internal => 
	// isSecondRageQuitCrossedGhost(rageQuitSupport) expect bool;

	function EscrowA.getRageQuitSupport() external returns (DualGovernanceHarness.PercentD16) => CVLRagequitSupport();
	function EscrowB.getRageQuitSupport() external returns (DualGovernanceHarness.PercentD16) => CVLRagequitSupport();

	// envfrees escrow
	function EscrowA.isRageQuitState() external returns (bool) envfree;
	function EscrowB.isRageQuitState() external returns (bool) envfree;

	// route escrow functions to implementations while
	// still allowing escrow addresses to vary
	function _.startRageQuit(DualGovernanceHarness.Duration, DualGovernance.Duration) external => DISPATCHER(true);
	function _.initialize(DualGovernanceHarness.Duration) external => DISPATCHER(true);
	function _.setMinAssetsLockDuration(DualGovernanceHarness.Duration newMinAssetsLockDuration) external => DISPATCHER(true);
	function _.getRageQuitSupport() external => DISPATCHER(true);

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

// function escrowAddressIsRageQuit(address escrow) returns bool {
// 	if (escrow == EscrowA) {
// 		return EscrowA.isRageQuitState();
// 	} else if (escrow == EscrowB) {
// 		return EscrowB.isRageQuitState();
// 	}
// 	return false;
// }

// Ghosts for support thresholds so we do not need to link
// in DualGovernanceConfig which has some nonlinear functions
// ghost uint256 rageQuitFirstSealGhost {
// 	init_state axiom rageQuitFirstSealGhost > 0;
// }
// ghost uint256 rageQuitSecondSealGhost {
// 	init_state axiom rageQuitSecondSealGhost > 0 && 
// 		rageQuitFirstSealGhost < rageQuitSecondSealGhost;
// }
// function isFirstRageQuitCrossedGhost(uint256 rageQuitSupport) returns bool {
// 	require rageQuitFirstSealGhost > 0;
// 	require rageQuitSecondSealGhost > 0;
// 	require rageQuitFirstSealGhost < rageQuitSecondSealGhost;
// 	return rageQuitSupport > rageQuitFirstSealGhost;
// }
// function isSecondRageQuitCrossedGhost(uint256 rageQuitSupport) returns bool {
// 	require rageQuitFirstSealGhost > 0;
// 	require rageQuitSecondSealGhost > 0;
// 	require rageQuitFirstSealGhost < rageQuitSecondSealGhost;
// 	return rageQuitSupport > rageQuitSecondSealGhost;
// }

persistent ghost uint256 ghost_ragequit_support;
function CVLRagequitSupport() returns uint256 {
	return ghost_ragequit_support;
}

// PP-1: Regardless of the state in which a proposal is submitted, if the 
// stakers are able to amass and maintain a certain amount of rage quit 
// support before the ProposalExecutionMinTimelock expires, they can extend 
// the timelock for a proportional time, according to the dynamic timelock 
// calculation.
// expected complexity: low
rule pp_kp_1_ragequit_extends_v2 {
	// Get proposal in submitted state
	env e1;
	uint256 proposalId;
	uint256 id;
	ExecutableProposals.Status proposal_status;
	address executor;
	DualGovernanceHarness.Timestamp submittedAt;
	DualGovernanceHarness.Timestamp scheduledAt;
	(id, proposal_status, executor, submittedAt, scheduledAt) =
		getProposalInfoHarnessed(e1, proposalId);
	// state is Submitted
	require assert_uint8(proposal_status) == 1;
	require submittedAt < e1.block.timestamp;

	// setup different rage quits for different executions
	uint256 firstSeal = getFirstSeal(e1);
	uint256 secondSeal = getSecondSeal(e1);
	require firstSeal > 0;
	require secondSeal > firstSeal;

	// 2 rageQuitSupport values both between the first and second seal
	uint256 rageQuitSupport1;
	uint256 rageQuitSupport2;
	require rageQuitSupport1 > firstSeal && rageQuitSupport1 < secondSeal;
	require rageQuitSupport2 > firstSeal && rageQuitSupport2 < secondSeal;
	require rageQuitSupport1 > rageQuitSupport2;


	storage initialState = lastStorage;

	// NOTE: I think the way this works I will get a sanity
	// failure by requesting 2 different values from getRageQuitSupport
	// instead I can move this to a separate file and use a summary to make
	// getRageQuitSupport return a ghost and then impose the requirements on
	// the ghost.

	// Execution 1: set R = rageQuitSupport1 then:
	// - take a state step from an arbitrary later timestamp
	// - advance to an arbitrary later timestamp after that and schedule
	env ex1_step;
	// Here assuming EscrowA is vetoSignalling Escrow 
	// require EscrowA.getRageQuitSupport(ex1_step) == rageQuitSupport1;
	ghost_ragequit_support = rageQuitSupport1;
	require ex1_step.block.timestamp > e1.block.timestamp;
	// advance state
	activateNextState(ex1_step);
	env ex1_schedule;
	require ex1_schedule.block.timestamp > ex1_step.block.timestamp;
	scheduleProposal@withrevert(ex1_schedule, proposalId);
	bool ex1_sched_reverted = lastReverted;

	// Execution 2: similar to Execution 1 but with R=rageQuitSupport2
	env ex2_step;
	// Here assuming EscrowA is vetoSignalling Escrow 
	// require EscrowA.getRageQuitSupport(ex2_step) at initialState == rageQuitSupport2;
	ghost_ragequit_support = rageQuitSupport2;
	require ex2_step.block.timestamp > e1.block.timestamp;
	// advance state
	activateNextState(ex2_step) at initialState;
	env ex2_schedule;
	require ex2_schedule.block.timestamp > ex2_step.block.timestamp;
	scheduleProposal@withrevert(ex2_schedule, proposalId);
	bool ex2_sched_reverted = lastReverted;

	// the Good one:
	// satisfy ex1_sched_reverted && !ex2_sched_reverted;
	// the bad one:
	satisfy !ex1_sched_reverted && ex2_sched_reverted;

}

// Alternative: maybe it's more useful to just prove that dynamicDelayDuration
// is monotonically increasing with increased rageQuitSupport.

// PP-2: It's not possible to prevent a proposal from being executed 
// indefinitely without triggering a rage quit.
// expected complexity: extra high

// One option: assume rageQuitSupport == max, show secondSealRageQuit support
// is crossed. Seems trivial though.

// PP-3: It's not possible to block proposal submission indefinitely.
// expected complexity: high

// PP-4: Until the Veto Signaling Deactivation sub-state transitions to Veto 
// Cooldown, there is always a possibility (given enough rage quit support) of 
// canceling Deactivation and returning to the parent state (possibly 
// triggering a rage quit immediately afterwards).