# Proofs

## Veto Signalling Maximum Timelock

### Property

Suppose that at time $t^S_{act}$ the Dual Governance protocol enters the Veto Signalling state. Then, if a rage quit isn't triggered, and assuming that state transitions are activated as soon as they becomes enabled, the protocol will transition to the Veto Cooldown state at a time $t^C_{act} > t^S_{act}$ such that
```math
t^C_{act} \leq t^S_{act} + T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 2
```
where $R_{max}$ is the maximum rage quit support between $t^S_{act}$ and $t^C_{act}$.

### Proof

**Observation 1:** First note that if we are in the Deactivation sub-state at any time after $t^S_{act} + T_{lock}(R_{max})$, we will not exit the sub-state until we transition to Veto Cooldown. To exit back to the parent state, one of the following would have to be true for some $t > t^S_{act} + T_{lock}(R_{max})$:
1. $t \leq t^S_{act} + T_{lock}(R(t))$. Since $R_{max} \geq R(t)$ for all $t$ between $t^S_{act}$ and $`t^{C}_{act}`$, and $T_{lock}(R)$ is monotonic, this is not possible once $t > t^S_{act} + T_{lock}(R_{max})$.
2. $R(t) > R_2$. This would imply $R_{max} \geq R(t) > R_2$, and therefore $T_{lock}(R_{max}) = L_{max}$. Since $t - t^S_{act} > T_{lock}(R_{max}) = L_{max}$ and $R(t) > R_2$, after exiting the Deactivation sub-state a rage quit would be immediately triggered. Since we are only considering scenarios where no rage quit happens, this case is also impossible.

Now, let $`t^{SD}_{act}`$ be the last time the Deactivation sub-state is entered before $t^C_{act}$. We will first prove that $`t^{SD}_{act} \leq t^S_{act} + T_{lock}(R_{max}) + T^{Sa}_{min} + 1`$:
* **Case 1:** If $`t^{SD}_{act} \leq t^S_{act} + T_{lock}(R_{max}) + 1`$, we are done.
* **Case 2:** Otherwise, $t^S_{act} + T_{lock}(R_{max}) + 1 < t^{SD}_{act}$.
    * Then, from Observation 1 above, at $t_1 = t^S_{act} + T_{lock}(R_{max}) + 1$ we cannot be in the Deactivation sub-state (since we wouldn't be able to exit the sub-state to enter again at $t^{SD}_{act}$).
    * Since this is the case even though $t_1 - t^S_{act} > T_{lock}(R(t_1))$, it must be because $`t_1 - \max \{ t^S_{act}, t^S_{react} \} \leq T^{Sa}_{min}`$, where $t^S_{react} < t_1$ was the last time the Deactivation sub-state was exited, or 0 if it has never been entered (note that $t_1$ must be strictly greater than $t^S_{react}$, since it would impossible to transition back to the parent state at $t^S_{act} + T_{lock}(R_{max}) + 1$).
    * In this case, as $t - t^S_{act} > T_{lock}(R(t))$ will remain true for any future $t > t_1$, the transition at $`t^{SD}_{act}`$ must happen as soon as $t - \max \{ t^S_{act}, t^S_{react} \} > T^{Sa}_{min}$ becomes true.
    * Since $t_1$ is strictly greater than $\max \{ t^S_{act}, t^S_{react} \}$, the latest this can happen is at $`t_1 + T^{Sa}_{min} = t^S_{act} + T_{lock}(R_{max}) + T^{Sa}_{min} + 1`$.

Finally, since the Deactivation sub-state does not return to the parent state after $`t^{SD}_{act}`$, and no rage quit is triggered, it will transition to Veto Cooldown as soon as $`t - t^{SD}_{act} > T^{SD}_{max}`$. Therefore, $`t^C_{act} = t^{SD}_{act} + T^{SD}_{max} + 1 \leq t^S_{act} + T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 2`$.

### Caveats

* This proof assumes that the transitions at $`t^{SD}_{act}`$ and $t^C_{act}$ happen immediately as soon as they are enabled. Any delay $d$ in performing either of these transitions gets added to the upper bound. For instance, if the last transition to the Deactivation sub-state is only performed at $`t^{SD}_{act} + d`$, then the earliest that Veto Cooldown can be entered is $`t^{SD}_{act} + d + T^{SD}_{max} + 1`$. On the other hand, any delay in performing previous transitions between the Deactivation sub-state and the parent state (before the last one at $`t^{SD}_{act}`$) does not increase the upper bound, since it does not change the time $t_0 + T_{lock}(R_{max}) + 1$.

## Staker Reaction Time

The following property can be interpreted to say that, regardless of the state in which a proposal is submitted, if the stakers are able to amass and maintain rage quit support $R_{min}$ before the `ProposalExecutionMinTimelock` expires, they can extend the timelock to at least $T_{lock}(R_{min})$.

### Property

Suppose that a proposal is submitted at time $t_{prop}$, and let $t_1$ and $t_2$ be such that

1. $t_{prop} \leq t_1 \leq t_{prop} + T_{min} \leq t_2$, where $T_{min}$ is `ProposalExecutionMinTimelock`.
2. Between $t_1$ and $t_2$, the rage quit support is never lower than some value $R_{min}$.
3. $t_2 \leq t_{prop} + T_{lock}(R_{min})$.

Then, assuming that $T_{min}$ is less than the minimum duration of the Veto Signalling state, the proposal cannot be executed at any time less than or equal to $t_2$.

### Proof

First, note that if $R_{min} \leq R_1$, then $T_{lock}(R_{min}) = 0$ and $t_2 = t_{prop}$. Since this cannot be the case when $t_{prop} + T_{min} \leq t_2$, we only need to consider cases where $R_{min} > R_1$.

At $t_{prop}$, the protocol must be in one of the three states that allow proposal submission. We'll consider each case individually.

**Normal state:** Since $T_{min}$ is less than the minimum duration of the Veto Signalling state, immediately before $t_1$ the protocol must be in either the Normal state or the Veto Signalling state. Regardless, since $R(t_1) \geq R_{min} > R_1$, at $t_1$ the protocol will be in the Veto Signalling state. Then, given that, for every $t_1 \leq t \leq t_2$,
* $t \leq t_{prop} + T_{lock}(R_{min})$
* $t_{prop} \leq t^S_{act}$
* $T_{lock}(R_{min}) \leq T_{lock}(R(t))$

we have that $t \leq t^S_{act} + T_{lock}(R(t))$, or $t - t^S_{act} \leq T_{lock}(R(t)$. Therefore, the protocol cannot be in the Deactivation sub-state at any $t$ between $t_1$ and $t_2$. Since $T_{lock}(R(t)) \leq L_{max}$, the Rage Quit state cannot be entered either. Therefore, the Veto Signalling state cannot be exited, and consequently the proposal is not executable during this time.

**Veto Signalling state:** If immediately before $t_1$ the protocol is either in the Normal state or the Veto Signalling state, the same reasoning as the previous case applies. Otherwise, it must be in either the Veto Cooldown or Rage Quit states. Since $T_{min}$ is less than the minimum duration of the Veto Signalling state, it cannot be the case that the Veto Signalling state was entered and exited again between $t_{prop}$ and $t_1$. Therefore, at $t_1$ the proposal is not executable in either the Veto Cooldown or Rage Quit state. Then, there are two cases:
* If we remain in the same state until $t_2$, the proposal remains not executable.
* If we transition to another state before $t_2$, it will be to the Veto Signalling state, since $R_{min} > R_1$. Using the same reasoning as above, we can conclude that we cannot exit the Veto Signalling state for any $t_1 \leq t \leq t_2$, and therefore the proposal will remain not executable until at least $t_2$ as well.

**Rage Quit state:** The same reasoning as the previous case applies.
