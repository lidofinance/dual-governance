# Key Properties of Dual Governance

## Implementation Properties

These are properties that must be guaranteed by the implementation of the contracts that comprise the Dual Governance mechanism.

### DualGovernance

* Proposals cannot be executed in the Veto Signalling (both parent state and Deactivation sub-state) and Rage Quit states.
* Proposals cannot be submitted in the Veto Signalling Deactivation sub-state or in the Veto Cooldown state.
* If a proposal was submitted after the last time the Veto Signalling state was activated, then it cannot be executed in the Veto Cooldown state.
* One rage quit cannot start until the previous rage quit has finalized. In other words, there can only be at most one active rage quit escrow at a time.

### EmergencyProtectedTimelock

* A proposal cannot be scheduled for execution before at least `ProposalExecutionMinTimelock` has passed since its submission.
* A proposal cannot be executed until the emergency protection timelock has passed since it was scheduled.
* The emergency protection timelock is greater than 0 if and only if the protocol is in protected deployment mode.

### Escrow

* Ignoring imprecisions due to fixed-point arithmetic, the rage quit support of an escrow is equal to $$\frac{(S + W + U + F)}{(T + F)}$$ where
    * $S$ is the ETH amount locked in the escrow in the form of stETH.
    * $W$ is the ETH amount locked in the escrow in the form of wstETH.
    * $U$ is the ETH amount locked in the escrow in the form of unfinalized Withdrawal NFTs.
    * $F$ is the ETH amount locked in the escrow in the form of finalized Withdrawal NFTs.
    * $T$ is the total supply of stETH.
* The amount of each token accounted for in the above calculation must be less than or equal to the balance of the escrow in the token.
* It's not possible to lock funds in or unlock funds from an escrow that is already in the rage quit state.
* An agent cannot unlock their funds from the signalling escrow until `SignallingEscrowMinLockTime` has passed since this user last locked funds.

## Protocol Properties

These are emergent properties that are derived from the design of the protocol, and give guarantees of protection against certain attacks.

* Regardless of the state in which a proposal is submitted, if the stakers are able to amass and maintain a certain amount of rage quit support before the `ProposalExecutionMinTimelock` expires, they can extend the timelock for a proportional time, according to the dynamic timelock calculation.

The proof for this property is presented in the "Proofs" section, under "Staker Reaction Time". However, note that it depends on the assumption that the minimum duration of the Veto Signalling state is greater than or equal to `ProposalExecutionMinTimelock` (which, as pointed out in the previous section, is true for the current proposed parameter values).

* It's not possible to prevent a proposal from being executed indefinitely without triggering a rage quit.

This property is guaranteed by the upper bounds on proposal execution presented in the previous section, "Overall Bounds on Proposal Execution".

* It's not possible to block proposal submission indefinitely.

This property is guaranteed by the fact that the only states that forbid proposal submission (Veto Cooldown and Veto Signalling Deactivation) have a fixed maximum duration, and that they cannot transition back-and-forth without a period in between when proposal submission is allowed: if the Veto Cooldown state transitions to the Veto Signalling state, it must remain in the parent state for at least `VetoSignallingMinActiveDuration` before it can transition to the Deactivation sub-state.

* Until the Veto Signalling Deactivation sub-state transitions to Veto Cooldown, there is always a possibility (given enough rage quit support) of cancelling Deactivation and returning to the parent state (possibly triggering a rage quit immediately afterwards).

This property is guaranteed by the transition function of the Deactivation sub-state, which always exits to the parent state when the current rage quit support is greater than `SecondSealRageQuitSupport`, regardless of how much time has passed. However, if `DynamicTimelockMaxDuration` has passed since the Veto Signalling state was entered, it will immediately trigger a transition from Veto Signalling to the Rage Quit state.
