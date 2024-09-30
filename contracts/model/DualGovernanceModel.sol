// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./EmergencyProtectedTimelockModel.sol";
import "./EscrowModel.sol";

/**
 * @title Dual Governance Mechanism
 * Based on the Lido protocol desgin documents.
 * This document describes the module of the Dual Governance in a high-level.
 */

// DualGovernance contract to handle proposal submissions and lifecycle management.
contract DualGovernanceModel {
    enum State {
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
        RageQuit
    }

    EmergencyProtectedTimelockModel public emergencyProtectedTimelock;
    EscrowModel public signallingEscrow;
    EscrowModel public rageQuitEscrow;
    address public fakeETH;

    // State Variables
    mapping(address => bool) public proposers;
    mapping(address => bool) public admin_proposers;
    uint256 public lastStateChangeTime;
    uint256 public lastSubStateActivationTime;
    uint256 public lastStateReactivationTime;
    uint256 public lastVetoSignallingTime;
    uint256 public rageQuitSequenceNumber;

    State public currentState;

    // Constants
    uint256 public constant FIRST_SEAL_RAGE_QUIT_SUPPORT = 10 ** 16; // Threshold required for transition from Normal to Veto Signalling state (1%).
    uint256 public constant SECOND_SEAL_RAGE_QUIT_SUPPORT = 10 ** 17; // Transition to Rage Quit occurs if t - t^S_{act} > DynamicTimelockMaxDuration and R > SecondSealRageQuitSupport (10%).
    uint256 public constant DYNAMIC_TIMELOCK_MIN_DURATION = 5 days; // L_min; minimum duration for the dynamic timelock, which extends based on the level of dissent or rage quit support.
    uint256 public constant DYNAMIC_TIMELOCK_MAX_DURATION = 45 days; // L_max; maximum possible duration for dynamic timelocks, applied under conditions of extreme dissent to delay proposal execution.
    uint256 public constant VETO_SIGNALLING_MIN_ACTIVE_DURATION = 5 hours; // Minimum time Veto Signalling must be active before before transitioning to the Deactivation sub-state can be considered.
    uint256 public constant VETO_COOLDOWN_DURATION = 5 hours; // Cooling period following the Veto Signalling state to prevent immediate re-signalling.
    uint256 public constant VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = 3 days; // Maximum duration that the Veto Signalling can remain in Deactivation before advancing to Veto Cooldown or reverting to Veto Signalling.
    uint256 public constant RAGE_QUIT_EXTENSION_DELAY = 7 days; // The delay follows the completion of the withdrawal process in Rage Quit state.

    // Constructor to initialize the governance contract in the Normal state.
    constructor(address _fakeETH, uint256 emergencyProtectionTimelock) {
        currentState = State.Normal;
        lastStateChangeTime = block.timestamp;
        fakeETH = _fakeETH;
        emergencyProtectedTimelock = new EmergencyProtectedTimelockModel(address(this), emergencyProtectionTimelock);
        signallingEscrow = new EscrowModel(address(this), _fakeETH);
    }

    // Operations
    /**
     * Submits a proposal for consideration within the governance model.
     * Proposals can be submitted when in the Normal state or during Veto Signalling; however they cannot be executed in Veto Signalling.
     */
    function submitProposal(ExecutorCall[] calldata calls) external returns (uint256 proposalId) {
        activateNextState();

        require(proposers[msg.sender], "Caller is not authorized to submit proposals.");
        require(calls.length != 0, "Empty calls.");
        require(
            currentState == State.Normal || currentState == State.VetoSignalling || currentState == State.RageQuit,
            "Cannot submit in current state."
        );

        proposalId = emergencyProtectedTimelock.submit(msg.sender, calls);
    }

    /**
     * Schedules a proposal for execution, ensuring that all conditions for governance are met.
     * Scheduling is allowed in Normal and Veto Cooldown states to prepare proposals for decision-making.
     */
    function scheduleProposal(uint256 proposalId) external {
        activateNextState();

        require(
            currentState == State.Normal || currentState == State.VetoCooldown,
            "Proposals can only be scheduled in Normal or Veto Cooldown states."
        );
        if (currentState == State.VetoCooldown) {
            (,, uint256 submissionTime,,) = emergencyProtectedTimelock.proposals(proposalId);
            require(
                submissionTime < lastVetoSignallingTime,
                "Proposal submitted after the last time Veto Signalling state was entered."
            );
        }

        emergencyProtectedTimelock.schedule(proposalId);
    }

    // Cancel all non-executed proposals.
    function cancelAllPendingProposals() external {
        activateNextState();

        require(admin_proposers[msg.sender], "Caller is not admin proposers.");
        require(
            currentState != State.Normal || currentState != State.VetoCooldown || currentState != State.RageQuit,
            "Cannot cancel all pending proposals in the current state."
        );

        emergencyProtectedTimelock.cancelAllNonExecutedProposals();
    }

    /**
     * Calculate the dynamic timelock T_lock(R) based on the current rage quit support.
     * Ajusting the timelock duration to reflect community sentiment and stake involvement,
     * ranging from immediate to maximum delay based on the specified thresholds.
     */
    function calculateDynamicTimelock(uint256 rageQuitSupport) public pure returns (uint256) {
        if (rageQuitSupport <= FIRST_SEAL_RAGE_QUIT_SUPPORT) {
            return 0;
        } else if (rageQuitSupport <= SECOND_SEAL_RAGE_QUIT_SUPPORT) {
            return linearInterpolation(rageQuitSupport);
        } else {
            return DYNAMIC_TIMELOCK_MAX_DURATION;
        }
    }

    /**
     * Implement linear interpolation to calculate dynamic timelocks based on current rage quit support.
     * Linear interpolation is used to smoothly transition between DYNAMIC_TIMELOCK_MIN_DURATION and DYNAMIC_TIMELOCK_MAX_DURATION,
     * proportional to the current rage quit support within the defined thresholds.
     */
    function linearInterpolation(uint256 rageQuitSupport) private pure returns (uint256) {
        uint256 L_min = DYNAMIC_TIMELOCK_MIN_DURATION;
        uint256 L_max = DYNAMIC_TIMELOCK_MAX_DURATION;
        // Assumption: No underflow
        require(FIRST_SEAL_RAGE_QUIT_SUPPORT <= rageQuitSupport);
        // Assumption: No overflow
        require(
            ((rageQuitSupport - FIRST_SEAL_RAGE_QUIT_SUPPORT) * (L_max - L_min)) / (L_max - L_min)
                == (rageQuitSupport - FIRST_SEAL_RAGE_QUIT_SUPPORT)
        );
        return L_min
            + ((rageQuitSupport - FIRST_SEAL_RAGE_QUIT_SUPPORT) * (L_max - L_min))
                / (SECOND_SEAL_RAGE_QUIT_SUPPORT - FIRST_SEAL_RAGE_QUIT_SUPPORT);
    }

    // Function to manage transitions between states, based on rage quit support and timing.
    function transitionState(State newState) private {
        require(newState != currentState, "New state must be different from current state.");

        if (newState == State.Normal) {
            rageQuitSequenceNumber = 0;
        } else if (newState == State.VetoSignalling) {
            lastVetoSignallingTime = block.timestamp;
        } else if (newState == State.RageQuit) {
            signallingEscrow.startRageQuit();
            rageQuitSequenceNumber++;
            rageQuitEscrow = signallingEscrow;
            signallingEscrow = new EscrowModel(address(this), fakeETH);
        }

        lastStateChangeTime = block.timestamp;
        lastStateReactivationTime = 0;
        currentState = newState;
    }

    // Function to manage transitions from parent states to sub-states.
    function enterSubState(State subState) private {
        require(
            currentState == State.VetoSignalling && subState == State.VetoSignallingDeactivation,
            "New state must be a sub-state of current state."
        );
        lastSubStateActivationTime = block.timestamp;
        currentState = subState;
    }

    // Function to manage transitions from sub-states back to parent states.
    function exitSubState(State parentState) private {
        require(
            currentState == State.VetoSignallingDeactivation && parentState == State.VetoSignalling,
            "New state must be a parent state of current state."
        );
        lastStateReactivationTime = block.timestamp;
        currentState = parentState;
    }

    // State Transitions

    function activateNextState() public {
        // Assumption: various time stamps are in the past
        require(lastStateChangeTime <= block.timestamp);
        require(lastSubStateActivationTime <= block.timestamp);
        require(lastStateReactivationTime <= block.timestamp);

        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();

        State previousState;

        // Make multiple transitions in sequence if the transition conditions are satisfied
        do {
            previousState = currentState;

            if (currentState == State.Normal) {
                fromNormal(rageQuitSupport);
            } else if (currentState == State.VetoSignalling) {
                fromVetoSignalling(rageQuitSupport);
            } else if (currentState == State.VetoSignallingDeactivation) {
                fromVetoSignallingDeactivation(rageQuitSupport);
            } else if (currentState == State.VetoCooldown) {
                fromVetoCooldown(rageQuitSupport);
            } else {
                fromRageQuit(rageQuitSupport);
            }
        } while (currentState != previousState);
    }

    /**
     * Manages the state transition logic from Normal.
     * Transitions from Normal to Veto Signalling occurs if rage quit support exceeds FIRST_SEAL_RAGE_QUIT_SUPPORT.
     */
    function fromNormal(uint256 rageQuitSupport) private {
        require(currentState == State.Normal, "Must be in Normal state.");

        if (rageQuitSupport > FIRST_SEAL_RAGE_QUIT_SUPPORT) {
            transitionState(State.VetoSignalling);
        }
    }

    /**
     * Manages the state transition logic from VetoSignalling.
     * Transitions to Rage Quit if both the max timelock duration is exceeded and rage quit support exceeds SECOND_SEAL_RAGE_QUIT_SUPPORT.
     * Transitions to Veto Deactivation occurs when the time elapsed since the last state change or proposal exceeds the dynamic timelock and minimum active duration.
     */
    function fromVetoSignalling(uint256 rageQuitSupport) private {
        require(currentState == State.VetoSignalling, "Must be in Veto Signalling state.");

        // Check the conditions for transitioning to RageQuit or Veto Deactivation based on the time elapsed and support level.
        if (
            block.timestamp != lastStateChangeTime
                && block.timestamp - lastStateChangeTime > DYNAMIC_TIMELOCK_MAX_DURATION
                && rageQuitSupport > SECOND_SEAL_RAGE_QUIT_SUPPORT
        ) {
            transitionState(State.RageQuit);
        } else if (
            block.timestamp != lastStateChangeTime
                && block.timestamp - lastStateChangeTime > calculateDynamicTimelock(rageQuitSupport)
                && block.timestamp - Math.max(lastStateChangeTime, lastStateReactivationTime)
                    > VETO_SIGNALLING_MIN_ACTIVE_DURATION
        ) {
            enterSubState(State.VetoSignallingDeactivation);
        }
    }

    /**
     * Manages the state transition logic from VetoSignallingDeactivation.
     * Checks if enough time has passed and evaluates current rage quit support to determine the next state.
     */
    function fromVetoSignallingDeactivation(uint256 rageQuitSupport) private {
        require(currentState == State.VetoSignallingDeactivation, "Must be in Deactivation sub-state.");

        uint256 elapsed = block.timestamp - lastSubStateActivationTime;
        // Check the conditions for transitioning to VetoCooldown or back to VetoSignalling
        if (
            block.timestamp == lastStateChangeTime
                || block.timestamp - lastStateChangeTime <= calculateDynamicTimelock(rageQuitSupport)
                || rageQuitSupport > SECOND_SEAL_RAGE_QUIT_SUPPORT
        ) {
            exitSubState(State.VetoSignalling);
        } else if (elapsed > VETO_SIGNALLING_DEACTIVATION_MAX_DURATION) {
            transitionState(State.VetoCooldown);
        }
    }

    /**
     * Manages the state transition logic from VetoCooldown.
     * Checks if the cooldown period has elapsed before making any state transitions based on the rageQuitSupport levels.
     */
    function fromVetoCooldown(uint256 rageQuitSupport) private {
        require(currentState == State.VetoCooldown, "Must be in Veto Cooldown state.");

        // Ensure the Veto Cooldown has lasted for at least the minimum duration.
        if (block.timestamp != lastStateChangeTime && block.timestamp - lastStateChangeTime > VETO_COOLDOWN_DURATION) {
            // Depending on the level of rage quit support, transition to Normal or Veto Signalling.
            if (rageQuitSupport <= FIRST_SEAL_RAGE_QUIT_SUPPORT) {
                transitionState(State.Normal);
            } else {
                transitionState(State.VetoSignalling);
            }
        }
    }

    /**
     * Manages the state transition logic from RageQuit based on cooldown expiration and rage support evaluation.
     * Checks if withdrawal process is complete, cooldown period expired.
     * Transitions to VetoCooldown if support has decreased below the threshold; otherwise, transitions to VetoSignalling.
     */
    function fromRageQuit(uint256 rageQuitSupport) public {
        require(currentState == State.RageQuit, "Must be in Rage Quit state.");

        // Check if the withdrawal process is completed and if the RageQuitExtensionDelay has elapsed
        if (rageQuitEscrow.isRageQuitFinalized()) {
            // Start ETH claim timelock period
            rageQuitEscrow.startEthClaimTimelock(rageQuitSequenceNumber);

            // Depending on the level of rage quit support, transition to Veto Cooldown or Veto Signalling.
            // Transition to Veto Cooldown if support has decreased below the critical threshold.
            // Otherwise, return to Veto Signalling if support is still above a lower threshold.
            if (rageQuitSupport <= FIRST_SEAL_RAGE_QUIT_SUPPORT) {
                transitionState(State.VetoCooldown);
            } else {
                transitionState(State.VetoSignalling);
            }
        }
    }
}
