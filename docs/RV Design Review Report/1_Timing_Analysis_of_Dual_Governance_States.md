# Timing Analysis of Dual Governance States

There are two opposing ways in which a malicious adversary might attack the protocol by manipulating proposal execution delays:

1. Delay the execution of a legitimate proposal for a significant amount of time or, in the worst case, indefinitely.
2. Trigger an early execution of a malicious proposal, without giving the stakers the chance to delay it or exit the protocol.

As these two attack vectors are diametrically opposed, any change in the protocol made to prevent one has the potential of enabling the other. Therefore, it's important to know both the minimum and maximum time that the execution of a proposal can be delayed for in the current version of the protocol. The first step is to analyze how much time can be spent inside each Dual Governance state, since the current state is one of the main factors that determine whether a proposal can be executed.

Below, we give upper and lower bounds on the time spent in each state, given as the difference between the time the state was entered ($t_{enter}$) and exited ($t_{exit}$).

**Note:** For simplicity, this analysis assumes that transitions happen immediately as soon as they are enabled. Since in practice they need to be triggered by a call to `activateNextState`, it's possible for there to be a delay between when the transition becomes enabled and when it actually happens. However, we can assume this delay will be small since any interested agent can call the function as soon as it becomes possible.

## Normal

The Normal state can only transition to the Veto Signalling state, and this transition happens immediately as soon as the rage quit support surpasses `FirstSealRageQuitSupport` ($R_1$). On the other hand, if this never happens the protocol can remain in the Normal state indefinitely. Therefore, the time between activating the Normal state and transitioning to the Veto Signalling state can have any duration:

$$
0 \leq t_{exit} - t_{enter} < \infty
$$

## Veto Signalling

Once the Veto Signalling state is entered, it can be exited in two ways: either to the Rage Quit state or the Veto Cooldown state. It also can enter and exit the Deactivation sub-state, making this the hardest state to analyze.

### To Veto Cooldown

While in the Veto Signalling state, the protocol can enter and exit the Deactivation sub-state depending on the current value of the dynamic timelock duration $T_{lock}(R)$, a monotonic function on the current rage quit support $R$.

When first entering the Veto Signalling state, and again whenever the Deactivation sub-state is exited, there is a waiting period of `VetoSignallingMinActiveDuration` ($`T^{Sa}_{min}`$) when the Deactivation sub-state cannot be entered. Outside of this window (as long as a rage quit is not triggered), the protocol will be in the Deactivation sub-state if the time $\Delta t$ since entering the Veto Signalling state is greater than the current value of $T_{lock}(R)$, and will be in the Veto Signalling parent state otherwise. If the Deactivation sub-state is not exited within `VetoSignallingDeactivationMaxDuration` ($T^{SD}_{max}$) of being entered, it transitions to the Veto Cooldown state.

With this, we can calculate bounds on the time spent in the Veto Signalling state (including the Deactivation sub-state) before transitioning into Veto Cooldown:

* For the lower bound, the earliest we can transition to the Deactivation sub-state is $`T^{Sa}_{min} + 1`$ after Veto Signalling is entered, and then the transition to Veto Cooldown happens $T^{SD}_{max} + 1$ after that, giving us $`T^{Sa}_{min} + T^{SD}_{max} + 2`$.
* For the upper bound, we can use the insight that, if $R_{max}$ is the highest rage quit support during the time we are in the Veto Signalling state, then it's impossible to exit the Deactivation sub-state (without triggering a rage quit) after $T_{lock}(R_{max})$ has passed since entering Veto Signalling (see "Veto Signalling Maximum Timelock" in the "Proofs" section for details). Therefore, for a given $R_{max}$, the longest delay happens in the following scenario:
    1. $R_{max}$ is locked in escrow, making the dynamic timelock duration $T_{lock}(R_{max})$.
    2. Shortly before $\Delta t = T_{lock}(R_{max})$ has passed, the rage quit support decreases, and the Deactivation sub-state is entered.
    3. At exactly $\Delta t = T_{lock}(R_{max})$, the rage quit support returns to $R_{max}$, and the Deactivation sub-state is exited.
    4. At $\Delta t = T_{lock}(R_{max}) + T^{Sa}_{min} + 1$, the waiting period ends and the Deactivation sub-state is entered again.
    5. At $`\Delta t = T_{lock}(R_{max}) + T^{Sa}_{min} + 1 + T^{SD}_{max} + 1`$, the state transitions to Veto Cooldown.

In summary, the above analysis gives us the following bounds:

```math
T^{Sa}_{min} + T^{SD}_{max} + 2 \leq t_{exit} - t_{enter} \leq T_{lock}(R_{max}) + T^{Sa}_{min} + T^{SD}_{max} + 2
```

Note that the maximum value of $T_{lock}(R)$ is `DynamicTimelockMaxDuration` ($L_{max}$), so the upper bound can be at most $`L_{max} + T^{Sa}_{min} + T^{SD}_{max} + 2`$. However, writing it in terms of $R_{max}$ highlights an important security property: the delay in deactivating the Veto Signalling state depends only on the *highest* value of the rage quit support, and cannot be increased further by locking and unlocking funds in the signalling escrow at different times. In other words, the amount of delay an attacker is able to achieve is limited by the amount of stETH they control.

### To Rage Quit

The Veto Signalling state can transition to the Rage Quit state at any point after $L_{max}$ has passed, as long as the rage quit support surpasses `SecondSealRageQuitSupport` ($R_2$). This gives us a lower bound of $L_{max}$. For the upper bound, we can adapt the analysis of the Veto Cooldown transition above. Note that if $R_{max} = R_2$, it's possible to delay the transition to the Veto Cooldown state for the maximum time of $`L_{max} + T^{Sa}_{min} + T^{SD}_{max} + 2`$ before triggering a rage quit at the last possible moment by increasing the rage quit support above $R_2$. Therefore,

```math
L_{max} < t_{exit} - t_{enter} \leq L_{max} + T^{Sa}_{min} + T^{SD}_{max} + 2
```

## Veto Cooldown

Depending on whether the rage quit support is above or below $R_1$, the Veto Cooldown state can transition to the Veto Signalling state or the Normal state, but regardless this transition always happens after `VetoCooldownDuration` ($T^C$) has passed. Therefore, the time between entering and exiting the state is always the same:

$$
t_{exit} - t_{enter} = T^C + 1
$$

## Rage Quit

The Rage Quit state differs from the others due to having a dependence on a mechanism external to the Dual Governance protocol, namely the withdrawal procedure for unstaking ETH. After transitioning to the Rage Quit state, anyone can call the `requestNextWithdrawalsBatch` function, sending a portion of the funds in the rage quit escrow to the Lido Withdrawal Queue. Once a withdrawal request is finalized, anyone can transfer the ETH from the queue to the rage quit escrow by calling the `claimNextWithdrawalsBatch` function. After all the withdrawals are claimed, a period lasting `RageQuitExtensionDelay` ($T^R$) starts, where any stakers who had submitted Withdrawal NFTs as rage quit support and haven't done so already can claim those as well before the Rage Quit state is exited.

Therefore, if $T^W$ is the time from when the Rage Quit state is entered until the last withdrawal request is claimed, then the total duration of the Rage Quit state is

$$
t_{exit} - t_{enter} = T^W + T^R + 1
$$

Unlike other values in this analysis, the time duration $T^W$ cannot be deterministically predicted or bounded based on the internal state of the Dual Governance protocol, as withdrawal time is dependent on a number of factors related to Ethereum's validator network and other parts of the Lido system. However, triggering a rage quit in bad faith would come at a higher cost than normal to an attacker, as it would not only require them to remove their stake from the protocol, but also keep their ETH locked in the rage quit escrow until a dynamic `RageQuitEthClaimTimelock` has passed after exiting the Rage Quit state.
