# Single governance specification (plan B)

Signle Governance (SG) is a governance subsystem that sits between the Lido DAO, represented by various voting systems, and the protocol contracts it manages. It protects protocol users from hostile actions by the DAO by allowing to cooperate and block any in-scope governance decision until either the DAO cancels this decision or users' (w)stETH is completely withdrawn to ETH.

## System overview

![image](https://github.com/lidofinance/dual-governance/assets/13422270/e9358375-b72c-40b9-9882-a7ff9b871708)

The system is composed of the following main contracts:

- `SingleGovernance.sol` is a singleton that provides an interface for submitting governance proposals and scheduling their execution, as well as managing the list of supported proposers (DAO voting systems).
- `EmergencyProtectedTimelock.sol` is a singleton that stores submitted proposals and provides an interface for their execution. In addition, it implements an optional temporary protection from a zero-day vulnerability in the dual governance contracts following the initial deployment or upgrade of the system. The protection is implemented as a timelock on proposal execution combined with two emergency committees that have the right to cooperate and disable the dual governance.
- `Executor.sol` contract instances make calls resulting from governance proposals' execution. Every protocol permission or role protected by the DG, as well as the permission to manage this role/permission, should be assigned exclusively to one of the instances of this contract (in contrast with being assigned directly to a DAO voting system).

## [Proposal flow](specification.md#proposal-flow)

## [Proposal execution and deployment modes](specification.md#proposal-execution-and-deployment-modes)
