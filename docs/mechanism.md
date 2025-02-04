# Dual Governance mechanism design

A proposal by [sam](https://twitter.com/_skozin), [pshe](https://twitter.com/PsheEth), [kadmil](https://twitter.com/kadmil_eth), [sacha](https://twitter.com/sachayve), [psirex](https://twitter.com/psirex_), [Hasu](https://twitter.com/hasufl), [Izzy](https://twitter.com/IsdrsP), and [Vasiliy](https://twitter.com/_vshapovalov).

Currently, the Lido protocol governance consists of the Lido DAO that uses LDO voting to approve DAO proposals, along with an optimistic voting subsystem called Easy Tracks that is used for routine changes of low-impact parameters and falls back to LDO voting given any objection from LDO holders.

Additionally, there is a Gate Seal emergency committee that allows pausing certain protocol functionality (e.g. withdrawals) for a pre-configured amount of time sufficient for the DAO to vote on and execute a proposal. The Gate Seal committee can only enact a pause once before losing its power (so it has to be re-elected by the DAO after that).

The Dual governance mechanism (DG) is an iteration on the protocol governance that gives stakers a say by allowing them to block DAO decisions and providing a negotiation device between stakers and the DAO.

Another way of looking at dual governance is that it implements:
1) a dynamic user-extensible timelock on DAO decisions
2) a rage quit mechanism for stakers taking into account the specifics of how Ethereum withdrawals work.


## Navigation

* [Definitions](#definitions)
* [Mechanism description](#mechanism-description)
  + [Proposal lifecycle](#proposal-lifecycle)
  + [Signalling Escrow](#signalling-escrow)
  + [Global governance state](#global-governance-state)
  + [Normal state](#normal-state)
  + [Veto Signalling state](#veto-signalling-state)
  + [Veto Cooldown state](#veto-cooldown-state)
  + [Rage Quit state](#rage-quit-state)
  + [Contracts pausability and Tiebreaker Committee](#contracts-pausability-and-tiebreaker-committee)
* [Dual governance scope](#dual-governance-scope)
* [Changelog](#changelog)


## Definitions

* **Lido protocol:** code deployed on the Ethereum blockchain implementing:
    1. a middleware between the parties willing to delegate ETH for validating the Ethereum blockchain in exchange for staking rewards (stakers) and the parties willing to run Ethereum validators in exchange for a fee taken from staking rewards (node operators);
    2. a fungibility layer distributing ETH between node operators and issuing stakers a fungible deposit receipt token (stETH).
* **Protocol governance:** the mechanism allowing to change the Lido protocol parameters and upgrade non-ossified (mutable) parts of the protocol code.
* **LDO:** the fungible governance token of the Lido DAO.
* **Lido DAO:** code deployed on the Ethereum blockchain implementing a DAO that receives a fee taken from the staking rewards to its treasury and allows LDO holders to collectively vote on spending the treasury, changing parameters of the Lido protocol and upgrading the non-ossified parts of the Lido protocol code. Referred to as just **DAO** throughout this document.
* **DAO proposal:** a specific change in the onchain state of the Lido protocol or the Lido DAO proposed by LDO holders. Proposals have to be approved via onchain voting between LDO holders to become executable.
* **stETH:** the fungible deposit receipt token of the Lido protocol. Allows the holder to withdraw the deposited ETH plus all accrued rewards (minus the fees) and penalties. Rewards/penalties accrual is expressed by periodic rebases of the token balances.
* **wstETH:** a non-rebasable, immutable, and trustless wrapper around stETH deployed as an integral part of the Lido protocol. At any moment in time, there is a fixed wstETH/stETH rate effective for wrapping and unwrapping. The rate changes on each stETH rebase.
* **Withdrawal NFT:** a non-fungible token minted by the Lido withdrawal queue contract as part of the (w)stETH withdrawal to ETH, parametrized by the underlying (w)stETH amount and the position in the queue. Gives the holder the right to claim the corresponding ETH amount after the withdrawal is complete. Doesn't entitle the holder to receive staking rewards.
* **Stakers:** EOAs and smart contract wallets that hold stETH, wstETH tokens, and withdrawal NFTs or deposit them into various deFi protocols and ceFi platforms: DEXes, CEXes, lending and stablecoin protocols, custodies, etc.
* **Node operators:** parties registered in the Lido protocol willing to run Ethereum validators using the delegated ETH in exchange for a fee taken from the staking rewards. Node operators generate validator keys and at any time remain their sole holders, having full and exclusive control over Ethereum validators. Node operators are required to set their validators' withdrawal credentials to point to the specific Lido protocol smart contract.

## Mechanism description

### Proposal lifecycle

The DG assumes that any permissions [protected by the subsystem](#Dual-governance-scope) (which we will call the in-scope permissions) are assigned to the DG contracts, in contrast to being assigned to the DAO voting systems. Thus, it's impossible for the DAO to execute any in-scope changes bypassing the DG.

Instead of making the in-scope changes directly, the DAO voting script should submit them as a proposal to the DG subsystem upon execution of the approved DAO vote.

![image](https://github.com/lidofinance/dual-governance/assets/1699593/5130780d-edb5-4210-ac16-2f76a0dfd5b8)

After submission to the DG, a proposal can exist in one of the following states:

* **Pending**: a proposal approved by the DAO was submitted to the DG subsystem, starting the dynamic execution timelock.
* **Cancelled**: the DAO votes for canceling the pending proposal. This is the terminal state.
* **Executed**: the dynamic timelock of a pending proposal has elapsed and the proposal was executed. This is the terminal state.


### Signalling Escrow

At any point in time, stakers can signal their opposition to the DAO by locking their stETH, wstETH, and [unfinalized](https://docs.lido.fi/contracts/withdrawal-queue-erc721#finalization) withdrawal NFTs into a dedicated smart contract called **veto signalling escrow**. A staker can also lift this signal by unlocking their tokens from the escrow given that at least `SignallingEscrowMinLockTime` passed since this staker locked token(s) the last time. This creates an onchain oracle for measuring stakers' disagreement with the DAO decisions.

While stETH or wstETH tokens are locked in the signalling escrow, they still generate staking rewards and are still subject to potential slashings.

An address having stETH or wstETH locked in the signalling escrow can trigger an immediate withdrawal of the locked tokens to ETH while keeping the resulting withdrawal NFT locked in the signalling escrow.

Let's define the **rage quit support** $R$ as a dimensionless quantity calculated as follows:

```math
R = \frac{1}{ S_{st} + \text{eth}_f } \left(
  \text{st} + \text{eth}_f +
  R_{wst}^{st} ( \text{wst} + \text{shares}_u )
\right)
```

```math
\text{eth}_f = \sum_{N_i \in \text{WR}_f} \text{eth}(N_i)
```

```math
\text{shares}_u = \sum_{N_i \in \text{WR}_u} \text{shares}(N_i)
```

where

* $S_{st}$ is the current stETH total supply,
* $\text{st}$ is the total amount of stETH locked in the signalling escrow,
* $R_{wst}^{st}$ is the current conversion rate from wstETH to stETH (the result of the `stETH.getPooledEthByShares(10**18) / 10**18` call),
* $\text{wst}$ is the total amount of wstETH locked in the signalling escrow,
* $\text{WR}_f$ is the set of finalized withdrawal NFTs locked in the signalling escrow,
* $\text{WR}_u$ is the set of non-finalized withdrawal NFTs locked in the escrow,
* $\text{shares}(N_i)$ is the stETH shares amount corresponding to the unfinalized withdrawal NFT $N_i$,
* $\text{eth}(N_i)$ is the withdrawn ETH amount associated with the finalized withdrawal NFT $N_i$.

All of the above values implicitly depend on the **current block time** $t$, thus $R = R(t)$. Changes of $R$ act as the main driver for the global governance state transitions.

```env
# Proposed values, to be modeled and refined
SignallingEscrowMinLockTime = 5 hours
```


### Global governance state

The DG mechanism can be described as a state machine defining the global governance state, with each particular state imposing different limitations on the actions the DAO can perform, and state transitions being driven by stakers' actions and (w)stETH withdrawals processing.

|State |DAO can submit proposals|DAO can execute proposals|
|-------------------------------|---|---|
|Normal                         | ✓ | ✓ |
|Veto Signalling                | ✓ |   |
|Veto Signalling (deactivation) |   |   |
|Veto Cooldown                  |   | ✓ |
|Rage Quit                      | ✓ |   |

![image](https://github.com/lidofinance/dual-governance/assets/1699593/862b3f11-ea79-4e75-8c56-ff56f94d0a6f)

When a state has multiple outgoing transitions, their conditions are evaluated in the order they're listed in the text. If a condition evaluates to true, the further evaluation stops and the corresponding transition is triggered.

If a state transition A, being triggered, makes a condition for state transition B from the new state hold true at the same timestamp, the transition B must be triggered together with A. In other words, **if there's a sequence of state transitions where each preceding transition enables each subsequent one, the whole sequence must be triggered atomically**.

Let's now define these states and transitions.


### Normal state

The Normal state is the state the mechanism is designed to spend the most time within. The DAO can submit the approved proposals to the DG and execute them provided that the proposal being executed is not cancelled and was submitted more than `ProposalExecutionMinTimelock` days ago.

**Transition to Veto Signalling**. If, while the state is active, the following expression becomes true:

```math
R \geq R_1
```

where $R_1$ is `FirstSealRageQuitSupport`, the Normal state is exited and the Veto Signalling state is entered.

```env
# Proposed values, to be modeled and refined
ProposalExecutionMinTimelock = 3 days
FirstSealRageQuitSupport = 0.01
```


### Veto Signalling state

The Veto Signalling state's purpose is two-fold:

1. Reduce information asymmetry by allowing an active minority of stakers to block the execution of a controversial DAO decision until it can be inspected and acted upon by the less active majority of stakers.
2. Provide a negotiation vehicle between stakers and the DAO.

In this state, the DAO can submit approved proposals to the DG but cannot execute them, including the proposals that were pending prior to the governance entering this state, effectively extending the timelock on all such proposals.

The only proposal that can be executed by the DAO is the special $CancelAllPendingProposals$ action that cancels all proposals that were pending at the moment of this execution, making them forever unexecutable. This mechanism provides a way for the DAO and stakers to negotiate and de-escalate if a consensus is reached.

To define transitions from this state, let's first introduce several time values.

The **time of activation** of the Veto Signalling state  $t^S_{act}$ is the time the state was entered. Entering and exiting the Deactivation sub-state doesn't affect this value.

The **time of re-activation** of the Veto Signalling state  $t^S_{react}$ is the time the Deactivation sub-state was last exited without exiting the parent Veto Signalling state.

The **dynamic timelock duration** $T_{lock}(R)$ depends on the current rage quit support $R = R(t)$ and can be calculated as follows:

```math
T_{lock}(R) =
\left\{ \begin{array}{lr}
    0, & \text{if } R < R_1 \\
    L(R), & \text{if } R_1 \leq R < R_2 \\
    L_{max}, & \text{if } R \geq R_2
\end{array} \right.
```

```math
L(R) = L_{min} + \frac{(R - R_1)} {R_2 - R_1} (L_{max} - L_{min})
```

where $R_1$ is `FirstSealRageQuitSupport`, $R_2$ is `SecondSealRageQuitSupport`, $L_{min}$ is `DynamicTimelockMinDuration`, $L_{max}$ is `DynamicTimelockMaxDuration`. The dependence of the dynamic timelock on the rage quit support $R$ can be illustrated by the following graph:

![image](https://github.com/user-attachments/assets/15cb6cdb-68a6-41ce-8d47-c34da19b84f1)


When the current rage quit support changes due to stakers locking or unlocking tokens into/out of the signalling escrow or the total stETH supply changing, the dynamic timelock duration is re-evaluated.

Let's now define the outgoing transitions.

**Transition to Rage Quit**. If, while Veto Signalling is active and the Deactivation sub-state is not active, the following expression becomes true:

```math
\big( t - t^S_{act} > L_{max} \big) \, \land \, \big( R \geq R_2 \big)
```

the Veto Signalling state is exited and the Rage Quit state is entered.

**Transition to Deactivation**. If, while Veto Signalling is active and the Deactivation sub-state is not active, the following expression becomes true:

```math
\left( t - t^S_{act} > T_{lock}(R) \right) \, \land \, \left( t - \max \left\{ t^S_{act} \,,\, t^S_{react} \right\} > T^{Sa}_{min} \right)
```

where $T^{Sa}_{min}$ is `VetoSignallingMinActiveDuration`, then the Deactivation sub-state of the Veto Signalling state is entered without exiting the parent Veto Signalling state.

The right part of the condition limits how fast the Deactivation sub-state can be entered and re-entered. It's needed to make it impossible to keep the governance in the Deactivation sub-state (where the DAO cannot submit proposals) by front-running state transitions and locking/unlocking tokens from the signalling escrow.

```env
# Proposed values, to be modeled and refined
DynamicTimelockMinDuration = 5 days
DynamicTimelockMaxDuration = 45 days
VetoSignallingMinActiveDuration = 5 hours
SecondSealRageQuitSupport = 0.1
```

#### Deactivation sub-state

The sub-state's purpose is to allow all stakers to observe the Veto Signalling being deactivated and react accordingly before non-cancelled proposals can be executed. In this sub-state, the DAO cannot submit proposals to the DG or execute pending proposals.

**Transition to the parent state**. If, while the sub-state is active, the following condition becomes true:

```math
t - t^S_{act} \leq \, T_{lock}(R)
```

then the Deactivation sub-state is exited so only the parent Veto Signalling state remains active.

**Transition to Rage Quit**. If, while the sub-state is active, the following condition becomes true:
```math
\big( t - t^S_{act} > L_{max} \big) \, \land \, \big( R \geq R_2 \big)
```
then the Deactivation sub-state is exited along with its parent Veto Signalling state and the Rage Quit state is entered.

**Transition to Veto Cooldown**. If, while the sub-state is active, the following condition becomes true:

```math
t - t^{SD}_{act} > \, T^{SD}_{max}
```

where $`t^{SD}_{act}`$ is the time the Deactivation sub-state was entered and $`T^{SD}_{max}`$ is `VetoSignallingDeactivationMaxDuration`, then the Deactivation sub-state is exited along with its parent Veto Signalling state and the Veto Cooldown state is entered.

```env
# Proposed values, to be modeled and refined
VetoSignallingDeactivationMaxDuration = 3 days
```

### Veto Cooldown state

In the Veto Cooldown state, the DAO cannot submit proposals to the DG but can execute pending non-cancelled proposals, provided that the proposal being executed was submitted more than `ProposalExecutionMinTimelock` days ago and before the Veto Signalling state was entered the last time. This state exists to guarantee that no staker possessing enough stETH to generate `FirstSealRageQuitSupport` can lock the governance indefinitely without rage quitting the protocol.

**Transition to Veto Signalling**. If, while the state is active, the following condition becomes true:

```math
\big( t - t^C_{act} > T^C \big) \,\land\, \big( R(t) \geq R_1 \big)
```

where $t^{C}_{act}$ is the time the Veto Cooldown state was entered and $T^{C}$ is `VetoCooldownDuration`, then the Veto Cooldown state is exited and the Veto Signalling state is entered.

**Transition to Normal**. If, while the state is active, the following condition becomes true:

```math
\big( t - t^C_{act} > T^C \big) \,\land\, \big( R(t) < R_1 \big)
```

then the Veto Cooldown state is exited and the Normal state is entered.

```env
# Proposed values, to be modeled and refined
VetoCooldownDuration = 5 hours
```


### Rage Quit state

The Rage Quit state allows all stakers who elected to leave the protocol via rage quit to fully withdraw their ETH without being subject to any new or pending DAO decisions. Entering this state means that the stakers and the DAO weren't able to resolve the dispute so the DAO is misaligned with a significant part of the stakers.

Upon entry into the Rage Quit state, three things happen:

1. The veto signalling escrow is irreversibly transformed into the **rage quit escrow**, an immutable smart contract that holds all tokens that are part of the rage quit withdrawal process, i.e. stETH, wstETH, withdrawal NFTs, and the withdrawn ETH, and allows stakers to retrieve the withdrawn ETH after a certain timelock following the completion of the withdrawal process (with the timelock being determined at the moment of the Rage Quit state entry).
2. All stETH and wstETH held by the rage quit escrow will be processed for withdrawals through the regular Lido Withdrawal Queue mechanism, generating a set of batch withdrawal NFTs held by the rage quit escrow.
3. A new instance of the veto signalling escrow smart contract is deployed. This way, at any point in time, there is only one veto signalling escrow but there may be multiple rage quit escrows from previous rage quits.

In this state, the DAO is allowed to submit proposals to the DG but cannot execute any pending proposals. Stakers are not allowed to lock (w)stETH or withdrawal NFTs into the rage quit escrow so joining the ongoing rage quit is not possible. However, they can lock their tokens that are not part of the ongoing rage quit process to the newly-deployed veto signalling escrow to potentially trigger a new rage quit later.

The state lasts until the withdrawal started in 2) is complete, i.e. until all batch withdrawal NFTs generated from (w)stETH that was locked in the escrow are fulfilled and claimed, plus `RageQuitExtensionPeriodDuration` days.

If a staker locks a withdrawal NFT into the signalling escrow before the Rage Quit state is entered, this NFT remains locked in the rage quit escrow. When such an NFT becomes fulfilled, the staker is allowed to burn this NFT and convert it to plain ETH, although still locked in the escrow. This allows stakers to derisk their ETH as early as possible by removing any dependence on the DAO-controlled code (remember that the withdrawal NFT contract is potentially upgradeable by the DAO but the rage quit escrow is immutable).

Since batch withdrawal NFTs are generated after the NFTs that were locked by stakers into the escrow directly, the withdrawal queue mechanism (external to the DG) guarantees that by the time batch NFTs are fulfilled, all individually locked NFTs are fulfilled as well and can be claimed. Together with the extension period, this guarantees that any staker having a withdrawal NFT locked in the rage quit escrow has at least `RageQuitExtensionPeriodDuration` days to convert it to escrow-locked ETH before the DAO execution is unblocked.

When the withdrawal is complete and the extension period elapses, two things happen simultaneously:

1. A timelock lasting $W(i)$ days is started, during which the withdrawn ETH remains locked in the rage quit escrow. After the timelock elapses, stakers who participated in the rage quit can obtain their ETH from the rage quit escrow.
2. The Rage Quit state is exited.

**Transition to Veto Signalling**. If, at the moment of the Rage Quit state exit, $R(t) \geq R_1$, the Veto Signalling state is entered.

**Transition to Veto Cooldown**. If, at the moment of the Rage Quit state exit, $R(t) < R_1$, the Veto Cooldown state is entered.

The duration of the ETH withdraw timelock $W(i)$ is a linear function that depends on the rage quit sequence number $i$ (see below):

```math
W(i) =  \min \left\{ W_{min} + i * W_{growth} \,,\, W_{max}  \right\}
```

where $W_{min}$ is `RageQuitEthWithdrawalsMinDelay`, $W_{max}$ is `RageQuitEthWithdrawalsMaxDelay`, $W_{growth}$ is `rageQuitEthWithdrawalsDelayGrowth`.

The rage quit sequence number is calculated as follows: each time the VetoCooldown state is entered, the sequence number is set to 0; each time the Rage Quit state is entered, the number is incremented by 1.

```env
# Proposed values, to be modeled and refined
RageQuitExtensionPeriodDuration = 7 days
RageQuitEthWithdrawalsMinDelay = 60 days
RageQuitEthWithdrawalsMaxDelay = 180 days
rageQuitEthWithdrawalsDelayGrowth = 15 days
```


### Contracts pausability and Tiebreaker Committee

#### Gate Seal

The [Gate Seal](https://docs.lido.fi/contracts/gate-seal) is an existing circuit breaker mechanism designed to be activated in the event of a zero-day vulnerability in the protocol contracts being found or exploited and empowering a DAO-elected committee to pause certain protocol functionality, including withdrawals, for a predefined duration enough for the DAO to vote for and execute a remediation (let's call this state an "ephemeral pause"). When this happens, the committee immediately loses its power. If this never happens, the committee's power also expires after a pre-configured amount of time passes since its election.

The pre-defined pause duration currently works since all DAO proposals have a fixed execution timelock so it's possible to configure the pause in a way that would ensure the DAO has enough time to vote on a fix, wait until the execution timelock expires, and execute the proposal before the pause ends.

The DG mechanism introduces a dynamic timelock on DAO proposals dependent on stakers' actions and protocol withdrawals processing which, in turn, requires either modifying the Gate Seal mechanism to make its pause dynamic or introducing an additional mechanism for extending the pause.

Making the Gate Seal pause dynamic has several downsides. First, it significantly increases the damage a malicious Gate Seal committee can do to the protocol, from pausing contracts for a few days to potentially pausing them for a very long duration. Second, the dynamic pause would require an explicit unpause transaction, making the mechanism significantly more complex and fragile. Thus, the Gate Seal mechanism is kept intact but an additional Reseal Committee is introduced.

#### Reseal Committee

The **Reseal Committee** is a multisig that has exactly one right: given the DAO proposal submission or execution is currently blocked by the Dual Governance mechanism, the committee is allowed to turn an ephemeral pause of a protocol contract into a full one, i.e. until the DAO explicitly unpases the contract.

Specifically, the Reseal Committee has the right to pause an [ephemerally pausable contract](https://github.com/lidofinance/lido-dao/blob/master/contracts/0.8.9/utils/PausableUntil.sol) for an indefinite duration if two conditions become true simultaneously:

1. the contract is ephemerally paused, i.e. its unpause time is above the current block timestamp and below the `PAUSE_INFINITELY` value ($2^{256} - 1$);
2. the current governance state is different from Normal.

The committee should have more members and a higher quorum value than the Gate Seal committee due to the higher potential damage to the protocol in the case of misuse.

The intended scenario for this committee is the following:

1. A vulnerability in a protocol contract is discovered and communicated to the Gate Seal and Reseal committees.
2. The Gate Seal committee pauses the contract for a fixed duration.
3. The governance occurs in a non-Normal state, either because it was in a non-Normal state at the moment the pause was triggered or because it exited the Normal state during the pause.
4. The Reseal committee pauses the contract for an indefinite duration.
5. When the DAO execution is unblocked, the DAO votes for and executes a proposal that fixes the vulnerability and unpauses the contract.

#### Tiebreaker Committee

Given the pausability of protocol contracts, the system allows for reaching a deadlock state: if the protocol withdrawals functionality gets permanently paused before the Rage Quit state is entered or while it's active, the rage quit process won't be able to finish until the pause is lifted. But a permanently paused contract can only be unpaused by the DAO, and the DAO execution is blocked until the rage quit process is finished and the Rage Quit state is exited.

Apart from being paused, withdrawals can become dysfunctional due to a bug in the protocol code. If this happens while the Rage Quit state is active, it would also trigger the deadlock since a DAO proposal fixing the bug cannot be executed until the Rage Quit state is exited.

To resolve the potential deadlock, the mechanism contains a third-party arbiter **Tiebreaker Committee** elected by the DAO. The committee gains its power only under the specific conditions of the deadlock (see below), and can only perform the following actions:

* Execute any pending proposal submitted by the DAO to DG (i.e. bypass the DG dynamic timelock).
* Unpause any of the paused protocol contracts.

The Tiebreaker committee can perform the above actions, subject to a timelock of `TiebreakerExecutionTimelock` days, if any of the following two conditions is true:

* **Tiebreaker Condition A**: (governance state is Rage Quit) $\land$ (protocol withdrawals are paused for a duration exceeding `TiebreakerActivationTimeout`).
* **Tiebreaker Condition B**: the last time governance exited Normal or Veto Cooldown state was more than `TiebreakerActivationTimeout` days ago.

The Tiebreaker committee should be composed of multiple sub-committees covering different interest groups within the Ethereum community (e.g. largest DAOs, EF, L2s, node operators, OGs) and should require approval from a supermajority of sub-committees to execute a pending proposal. The approval by each sub-committee should require the majority support within the sub-committee. No sub-committee should contain more than $1/4$ of the members that are also members of the Reseal committee.

The composition of the Tiebreaker committee should be set by a DAO vote (subject to DG) and reviewed at least once a year.

```env
# Proposed values, to be modeled and refined
TiebreakerExecutionTimelock = 1 month
TieBreakerActivationTimeout = 1 year
```


## Dual governance scope

Dual governance should cover any DAO proposal that could potentially affect the protocol users, including:

* Upgrading, adding, and removing any protocol code.
* Changing the global protocol parameters and safety limits.
* Changing the parameters of:
  * The withdrawal queue.
  * The staking router, including the addition and removal of staking modules.
  * Staking modules, including addition and removal of node operators within the curated staking module.
* Adding, removing, and replacing the oracle committee members.
* Adding, removing, and replacing the deposit security committee members.

Importantly, any change to the parameters of the dual governance contracts (including managing the tiebreaker committee structure) should be also in the scope of dual governance.

Dual governance should not cover:

* Emergency actions triggered by circuit breaker committees and contracts, including activation of any Gate Seal. These actions must be limited in scope and time and must be unable to change any protocol code.
* DAO decisions related to spending and managing the DAO treasury.


## Changelog
### 2024-12-04
- Updated calculations of Rage Quit support first/second threshold's reaching. The transition to VetoSignalling state now starts when the amount of locked funds reaches the first seal threshold (including the exact threshold value), and the transition to RageQuit state appropriately starts when the amount of locked funds reaches the second seal threshold (including the exact threshold value; the appropriate duration of time in VetoSignalling state still should pass).

### 2024-11-15
- The rage quit sequence number is now reset in the `VetoCooldown` state instead of the `Normal` state. This adjustment ensures that the ETH withdrawal timelock does not increase unnecessarily in cases where, after a Rage Quit, Dual Governance cycles through `VetoSignalling` → `VetoSignallingDeactivation` → `VetoCooldown` without entering the `Normal` state, as the DAO remains operational and can continue submitting and executing proposals in this scenario.

### 2024-09-12
- Explicitly described the `VetoSignallingDeactivation` -> `RageQuit` state transition.
- Renamed `RageQuitExtensionDelay` to `RageQuitExtensionPeriodDuration`.
- Replaced the quadratic function for the ETH withdrawal timelock $W(i)$ with a linear function.
- Renamed `RageQuitEthWithdrawalsMinTimelock` to `RageQuitEthWithdrawalsMinDelay`.
- Removed the `RageQuitEthWithdrawalsTimelockGrowthStartSeqNumber` and `RageQuitEthWithdrawalsTimelockGrowthCoeffs` parameters.
- Introduced the `RageQuitEthWithdrawalsMaxDelay` and `RageQuitEthWithdrawalsDelayGrowth` parameters to calculate the $W(i)$ duration.
- Removed the requirement **"governance state is Rage Quit"** from **Tiebreaker Condition B**.

### 2024-06-25
- Instead of using the "wNFT" shortcut for the "Lido: stETH Withdrawal NFT" token, the official symbol "unstETH" is now used.
- For the consistency with the codebase, the `RageQuitEthClaimMinTimelock`, `RageQuitEthClaimTimelockGrowthStartSeqNumber`, `RageQuitEthClaimTimelockGrowthCoeffs` parameters were renamed into `RageQuitEthWithdrawalsMinTimelock`, `RageQuitEthWithdrawalsTimelockGrowthStartSeqNumber`, `RageQuitEthWithdrawalsTimelockGrowthCoeffs`.

### 2024-04-24

* Removed the logic with the extension of the Veto Signalling duration upon new proposal submission.
* Added new condition for proposal execution in the Veto Cooldown state: the proposal must be submitted before the Veto Signalling state was entered for the last time.

    > This change simplifies the transition conditions for Veto Signalling and mitigates the main disadvantage of the extendable Veto Signalling approach: the potentially "unexpected" transition from Veto Signalling to the Rage Quit state.
    A possible scenario how such transition may be triggered:
    > - A malicious DAO submits a "non-malicious" proposal and transitions the DG into the Veto Signalling state, locking the `SecondSealRageQuitSupport` amount of the funds.
    > - Before the end of the `DynamicTimelockMaxDuration`, the malicious DAO submits a malicious proposal and withdraws funds from the Veto Signalling Escrow.
    >
    > Previously, the submission of any proposal during the Veto Signalling phase would prolong this phase, allowing up to `DynamicTimelockMaxDuration` for users to gather the `SecondSealRageQuitSupport` amount. However, the transition to the Rage Quit state may occur before the `DynamicTimelockMaxDuration` time has passed, as soon as the `SecondSealRageQuitSupport` is accumulated. This potentially decreases the number of users who may join the initiated Rage Quit round but still allows for the accumulation of stETH in the veto signalling escrow contract to begin a new Rage Quit after the current one ends.
    >
    > With the new approach, after the submission of a malicious proposal, it will not be executable after the end of the Veto Signalling initiated by the malicious DAO due to the addition of new restriction on proposals that may be executed in the Veto Cooldown state.
    >
    > In the new design, users will still have a `max(SignallingEscrowMinLockTime, VetoSignallingDeactivationMaxDuration + VetoCooldownDuration)` to accumulate enough funds to transfer the system into the Veto Signalling state and eventually trigger the Rage Quit. In contrast to the previous approach, the Rage Quit will not start before the `DynamicTimelockMaxDuration` time has passed, allowing more users to join the Rage Quit.
    >
    > A notable limitation identified with this new approach is the potential to double the maximum delay of proposal execution, facilitated by the combined duration of `DynamicTimelockMaxDuration` and `VetoDeactivationMaxDuration`. A malicious actor with a significant portion of the stETH total supply may lock at least the `FirstSealRageQuitSupport` in the Veto Signalling Escrow just before the proposal is submitted to DualGovernance. After this, the submitted proposal will be affected by two sequences of transitions: Veto Signalling -> Veto Signalling Deactivation -> Veto Cooldown. Such an action may effectively increase the duration of the DualGovernance lock with the same amount of funds. Therefore, it must be considered during the parameter selection process.
    >
    > Considering the limitations and benefits of both approaches, the newer model was chosen as it provides better guarantees for Lido stakers to exit the protocol during Rage Quit, a more crucial factor than the potential delay in proposal execution, which can be partially mitigated by optimizing system parameters.

### 2024-04-19

* Replaced the dynamic Gate Seal pause mechanism with the Reseal Committee.

    > A dynamic Gate Seal pause has several issues, including the conflict between the requirement for a very fast committee reaction time and the requirement for its increased safety due to higher potential damage under the DG, as well as increased complexity and operational fragility of the resulting mechanism. Keeping the Gate Seal pause static and introducing the additional committee provides for both the quick and impact-limited Gate Seal committee and a safer Reseal Committee by allowing the latter for a slower reaction time (and thus a larger quorum value) and imposing limitations on the conditions under which it can be activated.

### 2024-04-12

* Allowed the Tiebreaker committee to unpause protocol contracts.

    > Without this, a collusion between a malicious DAO and the Gate Seal committee (which has to be fast and thus limited in the number of participants) would allow them to indefinitely delay a rage quit by pausing certain contracts (e.g. withdrawal queue or validator exit bus) and blackmail rage quit participants.

* Limited the time between Veto Signalling state entrance and the Deactivation sub-state entrance to prevent the front-running attack allowing to keep the governance in the Deactivation sub-state (`T` is `FirstSealRageQuitSupport` and `P` is `SignallingEscrowMinLockTime`):

     ```
     1. t = 0: lock T/2, initiate unlock
     2. t = P: execute bundle:
          - lock T/2, initiate unlock => Veto Signalling is entered
          - unlock T/2 =>  Deactivation is entered
     3. t = 2P: unlock T/2
     4. t = [Veto Cooldown end] - P: lock T/2, initiate unlock
     5. t = X = [Veto Cooldown end]: execute bundle:
          - state transition: Normal is entered
          - lock T/2, initiate unlock => Veto Signalling is entered
          - unlock T/2 from prev lock => Deactivation is entered
     6. t = X + P: unlock T/2

     repeat from 4
     ```

* Removed the lower boundary on the Normal state duration since it's not needed anymore: flash loan attacks are prevented by the signalling escrow min lock time and governance liveliness is ensured by the Veto Cooldown.

### 2024-04-10

* Redesigned the Veto Signalling exit conditions and the Deactivation phase transitions: the Deactivation duration is now constant but the Veto Signalling duration gets extended each time a new proposal is submitted.

    > The extension of Veto Signalling better expresses one of the first design principles of the DG: stakers should have adequate time to react to any DAO proposal, disagree with the DAO, and potentially exit the protocol, and the more stakers disagree with the DAO, the longer the allowed reaction time should be.
    >
    > Also, these changes prevent the following DoS attack:
    >
    > 1. A malicious actor front-runs submission of a proposal to the DG with a transaction that locks enough tokens in the signalling escrow to generate `FirstSealRageQuitSupport`, and immediately initiates the unlock. The governance is transitioned into the Veto Signalling state.
    > 2. As soon as the `SignallingEscrowMinLockTime` passes, the actor unlocks their tokens from the escrow. This transitions the governance into the Veto Signalling Deactivation state that lasts `VetoSignallingMaxDuration`.

    > As one can see, the actor was able to delay the governance execution by `VetoSignallingMaxDuration` while controlling tokens only enough to generate `FirstSealRageQuitSupport` and locking them for only the `SignallingEscrowMinLockTime` which makes for a rather cheap and efficient DoS attack.

* Specified the transition conditions more rigorously.

### 2024-04-02

* Added a minimum lock time of (w)stETH/wNFTs in the signalling escrow to prevent triggering state transitions using flash loans.

    > An example attack:
    > 1. Take a flash loan of `FirstSealRageQuitSupport` stETH, lock into the signalling escrow, and unlock in the same transaction.
    > 2. This triggers the Veto Signalling state that will last for `VetoSignallingMinDuration` followed by the Veto Cooldown.
    > 3. At the block the Veto Cooldown transitions to Normal, frontrun any transition-triggering transaction with a bundle that performs the transition and includes the transaction from step 1. Go to 2.

* Added a lower limit on the Normal state duration to prevent `Veto Signalling -> Normal -> Veto Signalling` cycling attacks by front-running the DAO execution.

    > An example attack: the same steps as in the previous item but use own/borrowed capital instead of the flash-borrowed one.

* Added a lower limit on the time between exiting the Veto Signalling Deactivation sub-state and re-entering it (as well as transitioning to the Rage Quit) to prevent `(Veto Signalling, Deactivation) -> Veto Signalling -> (Veto Signalling, Deactivation)` cycling attacks by gradually locking stETH in the signalling escrow and thus blocking submission of new DAO proposals.

    > An example attack:
    > 1. An attacker controls `SecondSealRageQuitSupport` stETH. They divide these tokens into N parts so that the first part generates the `FirstSealRageQuitSupport` rage quit support and with each next part added, the Veto Signalling duration is increased by exactly `VetoSignallingDeactivationMinDuration` plus one block.
    > 2. The attacker locks the first part of stETH into signalling escrow, triggering transition to Veto Signalling.
    > 3. The attacker waits until the Veto Signalling Deactivation sub-state gets entered, and then waits for `VetoSignallingDeactivationMinDuration` minus one block.
    > 4. The attacker locks the next stETH part into the signalling escrow, exiting the Deactivation state. After one block, the Deactivation state gets entered once again. Go to 3 (if not all stETH parts are locked yet).

    > This way, the attacker can deprive the DAO of the ability to submit proposals (which is impossible in the Deactivation sub-state) for almost the whole `VetoSignallingMaxDuration` except a limited number of blocks.

* Replaced the `Rage Quit -> Normal` transition with the `Rage Quit -> Veto Cooldown` transition to prevent front-running the DAO to sequentially enter Veto Signalling without incrementing the rage quit sequence number and thus increasing the rage quit ETH claim lock time.

    > An example attack:
    >
    > 1. An attacker controls `2 * SecondSealRageQuitSupport` stETH. They lock the first half into the signalling escrow, triggering Rage Quit.
    > 2. In the beginning of the block the Rage Quit ends, the attacker includes a bundle with two transaction: the first triggers the Rage Quit -> Normal transition, the second locks the unused half of stETH into the signalling escrow, triggering the Normal -> Rage Quit transition.
    > 3. While Rage Quit is in progress, wait until ETH claim timelock ends for the other half of stETH, claim them to ETH and stake/swap to stETH. Go to 2.

* Decreased the proposed Veto Cooldown state duration from 1 day to 5 hours.

    > The new proposed time should be enough for the DAO (or anyone since execution is permissionless) to trigger proposal execution. At the same time, given the changes from the previous item, the DAO submitting a proposal at the end of Rage Quit now leads to the proposal's min execution timelock being effectively reduced by the veto cooldown duration so the latter should be set to a minumally viable value.
    >
    > An example attack:
    >
    > 0. If `VetoCooldownDuration >= ProposalExecutionMinTimelock`, the DAO can submit a proposal at the block preceding the one in which the Rage Quit ends. Since Rage Quit transitions to Veto Cooldown that allows proposal execution, the proposal will inevitably become executable after `ProposalExecutionMinTimelock` without stakers having the ability to extend its timelock and potentially leave before the proposal becomes executable.
    > 1. If `VetoCooldownDuration < ProposalExecutionMinTimelock`, the DAO can submit a proposal `ProposalExecutionMinTimelock - VetoCooldownDuration - one_block` seconds before the Rage Quit ends.
    > 2. Now, in order to extend the execution timelock of this proposal, stakers have the time until Rage Quit ends to lock enough stETH into the signalling escrow to generate `FirstSealRageQuitThreshold`. Otherwise, the proposal will become executable while the Veto Cooldown state lasts without stakers having the ability to extend its timelock and potentially leave before the proposal becomes executable.
    > 3. This way, the effective execution timelock of the proposal is reduced by `VetoCooldownDuration`. That's ok if `VetoCooldownDuration << ProposalExecutionMinTimelock` but is not ok if they're comparable.

### [2024-03-22](https://github.com/skozin/hackmd-notes/blob/35a2190a130ed6c92c231255be9bffd1f0d07a6c/dual-governance-design.md)

* Made the Veto Signalling Deactivation state duration dependent on the last time a proposal was submitted during Veto Signalling.

    > An example attack:
    > 1. A malicious DAO actor locks `SecondSealRageQuitSupport` tokens in the veto signalling escrow, triggering the transition to Veto Signalling.
    > 2. Waits until the `VetoSignallingMaxDuration` minus one block passes, submits a malicious proposal, and withdraws their tokens. This triggers the entrance of the Deactivation state.
    > 3. Now, honest stakers have only the `VetoSignallingDeactivationDuration` to enter the signalling escrow with no less than the `SecondSealRageQuitSupport` tokens and trigger rage quit. Otherwise, the Veto Cooldown state gets activated and the malicious proposal becomes executable.

* Added the Tiebreaker execution timelock.
* Renamed parameters and changed some terms for clarity.

### [2024-02-09](https://github.com/skozin/hackmd-notes/blob/22dbd2f22a35de44cca8d9cdfc556e6d0ce17c25/dual-governance-design.md)

* Removed the Rage Quit Accumulation state since it allowed a sophisticated actor to bypass locking (w)stETH in the escrow while still blocking the DAO execution (which, in turn, significantly reduced the cost of the "constant veto" DoS attack on the governance).
* Added details on veto signalling and rage quit escrows.
* Changed the post-rage quit ETH withdrawal timelock to be dynamic instead of static to further increase the cost of the "constant veto" DoS attack while keeping the default timelock adequate.

### [2023-12-05](https://github.com/skozin/hackmd-notes/blob/9a4eba7eb48de2915321e7875fbb7285ebb46949/dual-governance-design.md)

* Removed the stETH balance snapshotting mechanism since the Tiebreaker Committee already allows recovering from an infinite stETH mint vulnerability.
* Added support for using withdrawal NFTs in the veto escrow.

### [2023-10-23](https://github.com/skozin/hackmd-notes/blob/e84727ec658983761fa9c6a897de00a11f42edfe/dual-governance-design.md)

A major re-work of the DG mechanism (previous version [here](https://hackmd.io/@lido/BJKmFkM-i)).

* Replaced the global settlement mechanism with the rage quit mechanism (i.e. local settlement, a protected exit from the protocol). Removed states: Global Settlement; added states: Rage Quit Accumulation, Rage Quit.
* Removed the veto lift voting mechanism.
* Re-worked the DG activation and negotiation mechanism, replacing Veto Voting and Veto Negotiation states with the Veto Signalling state.
* Added the Veto Cooldown state.
* Added the $KillAllPendingProposals$ DAO decision.
* Added stETH balance snapshotting mechanism.
* Specified inter-operation between the Gate Seal mechanism and DG.
* Added the Tiebreaker Committee.
