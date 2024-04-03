// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IGovernanceState {
    enum State {
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
        RageQuit
    }
    function currentState() external view returns (State);
}