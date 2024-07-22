# Overall Bounds on Proposal Execution

Using the bounds from the previous section on the duration of each Dual Governance state, we can now set bounds on the total time between when a proposal is submitted ($t_{sub}$) and when it becomes executable ($t_{exe}$). For this analysis, we need to take into account the following rules of the protocol:

1. Proposal submission is only allowed in the Normal, Veto Signalling (only the parent state, not the Deactivation sub-state) and Rage Quit states.
2. Proposal execution is only allowed in the Normal and Veto Cooldown states.
3. Regardless of state, a proposal can only be executed after `ProposalExecutionMinTimelock` ($T_{min}$) has passed since its submission.
4. In the Veto Cooldown state, a proposal can only be executed if it was submitted before the last time the Veto Signalling state was entered.

Rule 4 is meant to guarantee that if a proposal is submitted during the Veto Signalling or Rage Quit states, the stakers will have the time to react and the benefit of a full Veto Signalling dynamic timelock before the proposal becomes executable.

## Accounting for Rage Quits

Note that it is technically possible to delay execution of a proposal indefinitely if the protocol transitions continuously between the Veto Signalling and Rage Quit states. However, as mentioned above, triggering a Rage Quit is unlikely to be cost-efficient to an attacker. Furthermore, doing this repeatedly is even more unlikely to be viable, as after exiting the Rage Quit state the funds remain locked in the rage quit escrow for `RageQuitEthClaimTimelock`, which starts as a lengthy duration (60 days with the current proposed values) and increases quadratically with each subsequent rage quit until the protocol returns to the Normal state.

With this in mind, in the rest of this section we consider the bounds on proposal execution assuming no rage quit is triggered. If the Rage Quit state *is* entered, every entry will delay proposal execution for an additional $T^W + T^R + 1$ (keeping in mind that $T^W$ is a non-deterministic duration that depends on external factors and might be different each time the rage quit is triggered), plus a further delay between $`T^{Sa}_{min} + T^{SD}_{max} + 2`$ and $`T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 2`$ if the Rage Quit state then transitions back to Veto Signalling. However, note that, after this re-entry to Veto Signalling, if the protocol then transitions to Veto Cooldown, any proposals submitted during the previous Rage Quit state or the Veto Signalling state before that will become executable immediately, without needing another round of Veto Signalling.

More precisely, the following bounds apply to any proposal submitted in the Rage Quit state or the preceding Veto Signalling state, for the time between when the Rage Quit state is exited ($t^R_{exit}$) and when the proposal becomes executable (assuming no further rage quit happens and the minimum timelock $T_{min}$ has already passed):

* If the Rage Quit state exits to Veto Cooldown and then Normal (becomes executable as soon as the Normal state is entered):

$$
t_{exe} - t^R_{exit} = T^C + 1
$$

* If the Rage Quit state exits to Veto Cooldown, then Veto Signalling and Veto Cooldown again (becomes executable as soon as the Veto Cooldown state is entered for the second time):

```math
T^C + T^{Sa}_{min} + T^{SD}_{max} + 3 \leq t_{exe} - t^R_{exit} \leq T^C + T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 3
```

* If the Rage Quit state exits to Veto Signalling and then Veto Cooldown (becomes executable as soon as the Veto Cooldown state is entered):

```math
T^{Sa}_{min} + T^{SD}_{max} + 2 \leq t_{exe} - t^R_{exit} \leq T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 2
```

## Proposals Submitted in the Normal State

If a proposal is submitted in the Normal state and no transition happens before then, it become executable as soon as $T_{min} + 1$ passes:

$$
t_{exe} - t_{sub} = T_{min} + 1
$$

On the other hand, if the protocol transitions to Veto Signalling before this time due to rage quit support surpassing $R_1$, it will become subject to the Veto Signalling dynamic timelock. The shortest possible time for execution in this case happens if the transition happens immediately after the proposal is submitted (at the same timestamp), and soon after that the rage quit support drops below $R_1$ again, making the dynamic timelock 0. In this scenario, the Deactivation sub-state will be entered at $`T^{Sa}_{min} + 1`$, and then exited to the Veto Cooldown state at $`T^{SD}_{max} + 1`$, giving the previously-stated $`T^{Sa}_{min} + T^{SD}_{max} + 2`$ lower bound on the duration of the Veto Signalling state. Note, however, that it's possible, depending on the parameter values, that at this point the minimum timelock $T_{min}$ hasn't passed, so the true lower bound is the highest between the minimum timelock and the minimum duration of the Veto Signalling state:

```math
\max \{ T_{min} + 1, T^{Sa}_{min} + T^{SD}_{max} + 2 \} \leq t_{exe} - t_{sub}
```

Note that for the current proposed values, the minimum Veto Signalling duration is slightly higher:

* $T_{min}$ is 3 days.
* $T^{Sa}_{min}$ is 5 hours.
* $T^{SD}_{max}$ is 3 days.

For the upper bound, the longest possible delay happens when the Veto Signalling state is entered at $T_{min}$ (the last possible moment before the proposal becomes executable in the Normal state) and lasts as long as possible ($`T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 2`$, according to our previous analysis):

```math
t_{exe} - t_{sub} \leq T_{min} + T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 2
```

**Note:** With the current proposed values for the parameters, we have the guarantee that $T_{min}$ will have expired by the time the Veto Cooldown state is entered. However, if $T_{min}$ were greater than $`T^{Sa}_{min} + T^{SD}_{max}`$, it would be possible to enter and exit the Veto Signalling state before the minimum timelock expired. If it were greater than $`T^{Sa}_{min} + T^{SD}_{max} + T^C`$, it would even be possible to exit Veto Cooldown and re-enter Veto Signalling before it expired. Nevertheless, the above upper bound would still work in those cases. In the first case, the proposal would become executable in the Veto Cooldown state at $T_{min} + 1$, which is less than the upper bound. In the second case, the Veto Signalling state would have to be re-entered at $T_{min}$ at the latest, giving rise to the same bound as above.

## Proposals Submitted in the Veto Signalling State

Proposals submitted while in the Veto Signalling state are not immediately executable after transitioning to Veto Cooldown. Instead, they will either become executable when Veto Cooldown transitions to the Normal state, or, if it transitions back to Veto Signalling instead, once it exits that state again and returns to Veto Cooldown.

In the first case, the shortest time between proposal submission and execution happens in the following scenario:

1. The proposal is submitted immediately before entering the Deactivation sub-state (recall that submissions are only allowed in the parent state).
2. After $T^{SD}_{max} + 1$, the Deactivation sub-state transitions to Veto Cooldown.
3. After $T^C + 1$, Veto Cooldown transitions to the Normal state and the proposal becomes executable.

Meanwhile, the longest time to execution happens in the following scenario:

1. The proposal is submitted as soon as the Veto Signalling state is first entered.
2. The longest possible duration of $`T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 2`$ passes before transitioning to Veto Cooldown.
3. After $T^C + 1$, Veto Cooldown transitions to the Normal state and the proposal becomes executable.

However, if either of these scenarios takes less time than $T_{min}$ (again, not the case for the current proposed values), then we'll have to wait for the minimum timelock to pass before executing the proposal, giving us the following final bounds:

```math
\max \{ T_{min} + 1, T^{SD}_{max} + T^C + 2 \} \leq t_{exe} - t_{sub}
```

```math
t_{exe} - t_{sub} \leq \max \{ T_{min} + 1, T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + T^C + 3 \}
```

In the second case, where Veto Cooldown transitions back to Veto Signalling instead of the Normal state, we need to add the duration of the Veto Signalling state again to the bounds. For the lower bound, we add the minimum duration of $`T^{Sa}_{min} + T^{SD}_{max} + 2`$, giving us $`T^{Sa}_{min} + 2T^{SD}_{max} + T^C + 4`$. For the upper bound, we add the maximum duration of $`T_{lock}(R'_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 2`$, where $`R'_{max}`$, the maximum rage quit support during the second time through the Veto Signalling state, might be different from $R_{max}$. This leaves us with the following bounds:

```math
\max \{ T_{min} + 1, T^{Sa}_{min} + 2T^{SD}_{max} + T^C + 4 \} \leq t_{exe} - t_{sub}
```

```math
t_{exe} - t_{sub} \leq \max \{ T_{min} + 1, T_{lock}(R_{max}) + T_{lock}(R'_{max}) + 2T^{Sa}_{min} + 2T^{SD}_{max} + T^C + 5 \}
```
