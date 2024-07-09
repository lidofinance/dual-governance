// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Struct to represent executor calls
struct ExecutorCall {
    address target;
    uint96 value;
    bytes payload;
}

enum ProposalStatus {
    Pending,
    Scheduled,
    Executed,
    Canceled
}

struct Proposal {
    uint256 id;
    address proposer;
    ExecutorCall[] calls;
    uint256 submissionTime;
    uint256 schedulingTime;
    ProposalStatus status;
}

// This contract manages the timelocking of proposals with emergency intervention capabilities.
// It provides controls for entering and managing emergency states as well as executing proposals under normal and emergency conditions.
contract EmergencyProtectedTimelockModel {
    // Addresses associated with governance roles and permissions.
    address public governance;
    address public emergencyGovernance;
    address public adminExecutor;
    address public emergencyActivationCommittee;
    address public emergencyExecutionCommittee;

    // State Variables
    mapping(uint256 => Proposal) public proposals; // Maps to keep track of proposals and their states.
    uint256 public nextProposalId; // ID to be assigned to the next proposal.
    bool public emergencyModeActive; // Indicates if the contract is currently in emergency mode.
    bool public protectedModeActive; // Indicates if the contract is in a protected deployment mode.
    uint256 public emergencyActivatedTimestamp; // Timestamp for when emergency mode was activated.
    uint256 public emergencyProtectionTimelock; // Timelock settings for emergency and proposal management. Set to 0 in regular deployment mode.

    // Constants
    uint256 public constant EMERGENCY_MODE_MAX_DURATION = 1 days; // Maximum duration emergency mode can be active.
    uint256 public constant PROPOSAL_EXECUTION_MIN_TIMELOCK = 3 days; // Minimum delay before an executed proposal becomes effective, during normal operation.

    constructor(address _governance, uint256 _emergencyProtectionTimelock) {
        governance = _governance;
        emergencyProtectionTimelock = _emergencyProtectionTimelock;
    }

    // Submits a new proposal, initializing its timelock and storing its calls.
    function submit(address executor, ExecutorCall[] memory calls) external returns (uint256 proposalId) {
        // Ensure that only the governance can submit new proposals.
        require(msg.sender == governance, "Only governance can submit proposal.");

        proposals[nextProposalId].id = nextProposalId;
        proposals[nextProposalId].proposer = executor;
        proposals[nextProposalId].submissionTime = block.timestamp;
        proposals[nextProposalId].schedulingTime = 0;
        proposals[nextProposalId].status = ProposalStatus.Pending;

        for (uint256 i = 0; i < calls.length; i++) {
            proposals[nextProposalId].calls.push(calls[i]);
        }

        proposalId = nextProposalId;
        nextProposalId++;
    }

    // Schedules a proposal if it has been submitted for at least AFTER_SUBMIT_DELAY days.
    function schedule(uint256 proposalId) external {
        // The proposal MUST be already submitted.
        require(proposalId < nextProposalId, "Proposal does not exist.");
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Pending, "Proposal must be in Pending status.");
        // Ensure that only the governance can schedule proposals.
        require(msg.sender == governance, "Only governance can schedule proposal.");
        // Ensure the mandatory delay after submission has passed before allowing scheduling.
        require(
            block.timestamp >= proposal.submissionTime + PROPOSAL_EXECUTION_MIN_TIMELOCK,
            "Required time since submission has not yet elapsed."
        );
        proposal.status = ProposalStatus.Scheduled;
        proposal.schedulingTime = block.timestamp;
    }

    // Executes a scheduled proposal after a defined delay.
    function execute(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        // Ensure the emergency mode is not active to proceed with normal execution.
        require(!emergencyModeActive, "Emergency mode must not be active to execute a proposal.");
        // Check that the proposal is in the Scheduled state, ready for execution.
        require(proposal.status == ProposalStatus.Scheduled, "Proposal must be scheduled before it can be executed.");
        // Check that the required time delay after scheduling has passed to allow for sufficient time.
        require(
            block.timestamp >= proposal.schedulingTime + emergencyProtectionTimelock,
            "Scheduled time plus delay must pass before execution."
        );
        // Execute the proposal by calling `executeProposalCalls`, which handles the execution of all calls within the proposal.
        executeProposalCalls(proposalId);
    }

    /**
     * Contains the logic for executing the calls within a proposal.
     * Each call within the proposal must execute successfully.
     */
    function executeProposalCalls(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        // Iterate over all calls in the proposal.
        for (uint256 i = 0; i < proposal.calls.length; i++) {
            (bool success,) = proposal.calls[i].target.call{value: proposal.calls[i].value}(proposal.calls[i].payload);
            require(success, "Execution failed.");
        }
        proposal.status = ProposalStatus.Executed;
    }

    /**
     * Cancels all proposals that have not yet been executed.
     * It iterates through the list of all proposals and cancels each that has not been executed.
     */
    function cancelAllNonExecutedProposals() public {
        require(msg.sender == governance, "Caller is not authorized to cancel proposal.");

        if (nextProposalId > 0) {
            // Loop through all the proposals stored in the contract.
            for (uint256 i = 0; i < nextProposalId; i++) {
                // Ensure that only proposals in 'Submitted' or 'Scheduled' status are canceled.
                if (proposals[i].status != ProposalStatus.Executed) {
                    proposals[i].status = ProposalStatus.Canceled;
                }
            }
        }
    }

    // Emergency protection functions
    /**
     * Activates the emergency mode, restricting new proposals and allowing emergency interventions.
     * Can only be activated by the emergency activation committee.
     */
    function activateEmergencyMode() external {
        require(msg.sender == emergencyActivationCommittee, "Must be called by the Emergency Activation Committee.");
        require(!emergencyModeActive, "Emergency mode is already active.");
        // Activate the emergency mode.
        emergencyModeActive = true;
        // Record the timestamp of activation to manage the duration of the emergency state accurately.
        emergencyActivatedTimestamp = block.timestamp;
    }

    /**
     * Deactivates the emergency mode, resuming normal operations.
     * This function is a crucial step in the recovery process from an emergency state,
     * allowing the system to return to standard operational mode after addressing the emergency situation.
     */
    function deactivateEmergencyMode() external {
        // Ensure the emergency mode is currently active before attempting to deactivate.
        require(emergencyModeActive, "Emergency mode is not active.");

        // If within the duration, only the Admin Executor can deactivate to prevent premature termination of emergency procedures.
        if (block.timestamp - emergencyActivatedTimestamp < EMERGENCY_MODE_MAX_DURATION) {
            require(msg.sender == adminExecutor, "Only the Admin Executor can deactivate emergency mode prematurely.");
        }
        // Deactivate the emergency mode.
        emergencyModeActive = false;
        // Clearing both the Emergency Activation and Execution Committees.
        emergencyActivationCommittee = address(0);
        emergencyExecutionCommittee = address(0);
        cancelAllNonExecutedProposals();
        emergencyProtectionTimelock = 0;
    }

    // Executes the scheduled proposal. Emergency execution allows bypassing the normal timelock in critical situations.
    function emergencyExecute(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        require(msg.sender == emergencyExecutionCommittee, "Caller is not the Emergency Execution Committee.");
        require(emergencyModeActive, "Emergency mode is not active.");
        require(proposal.status == ProposalStatus.Scheduled, "Proposal is not scheduled.");

        executeProposalCalls(proposalId);
    }

    /**
     * Executes an emergency reset of the governance system to the pre-configured emergency governance address,
     * cancels all non-executed proposals, and resets both emergency committees.
     */
    function emergencyReset() external {
        require(msg.sender == emergencyExecutionCommittee, "Caller is not the Emergency Execution Committee.");
        require(emergencyModeActive, "Emergency mode must be active.");

        // Deactivate the emergency mode.
        emergencyModeActive = false;
        // Clearing both the Emergency Activation and Execution Committees.
        emergencyActivationCommittee = address(0);
        emergencyExecutionCommittee = address(0);
        // Setting the governance address to a pre-configured Emergency Governance address.
        governance = emergencyGovernance;
        cancelAllNonExecutedProposals();
        emergencyProtectionTimelock = 0;
    }
}
