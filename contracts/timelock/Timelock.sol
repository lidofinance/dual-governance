// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Proposals, Proposal} from "./Proposals.sol";
import {TimelockExecutor} from "./TimelockExecutor.sol";

contract Timelock {
    using Proposals for Proposals.State;

    error NotAdmin(address sender);
    error NotGuardian(address sender);
    error NotAdminExecutor(address sender);
    error GuardianLifetimeExpired();
    error InvalidTimelockDuration(
        uint256 duration,
        uint256 minTimelockDuation,
        uint256 maxTimelockDuration
    );

    event AdminSet(address admin);
    event EmergencyAdminReset();
    event TimelockDurationSet(uint256 timelockDuration);
    event GuardianSet(address guardian);
    event GuardianActiveTillSet(uint256 guardianActiveTill);
    event AdminExecutorCreated(address executor);

    uint256 public immutable MIN_TIMELOCK_DURATION;
    uint256 public immutable MAX_TIMELOCK_DURATION;

    address internal immutable EMERGENCY_ADMIN;
    address public immutable ADMIN_EXECUTOR; // can call manage methods on the timelock

    address public admin; // can call propose, queue, execute

    uint256 public delay;
    address public guardian; // can reset admin
    uint256 public guardianActiveTill;

    Proposals.State private _proposals;

    constructor(
        address admin_,
        address emergencyAdmin,
        uint256 minTimelockDuration,
        uint256 maxTimelockDuration,
        uint256 timelockDuration,
        address guardian_,
        uint256 guardianActiveTill_
    ) {
        MIN_TIMELOCK_DURATION = minTimelockDuration;
        MAX_TIMELOCK_DURATION = maxTimelockDuration;

        EMERGENCY_ADMIN = emergencyAdmin;
        ADMIN_EXECUTOR = address(new TimelockExecutor(address(this)));

        admin = admin_;
        guardian = guardian_;
        guardianActiveTill = guardianActiveTill_;

        // TODO: add ranges checks
        delay = timelockDuration;

        emit AdminExecutorCreated(ADMIN_EXECUTOR);
    }

    function cancelAllProposals() external onlyAdmin {
        _proposals.cancelAllProposals();
    }

    function dequeueAllProposals() external onlyGuardian {
        _proposals.dequeueAllProposals();
    }

    function propose(
        address executor,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads
    ) external onlyAdmin returns (uint256 proposalId) {
        proposalId = _proposals.propose(executor, targets, values, payloads);
    }

    function enqueue(uint256 proposalId, uint256 waitBeforeEnqueue) external onlyAdmin {
        _proposals.enqueue(proposalId, waitBeforeEnqueue);
    }

    // trustless method
    function execute(uint256 proposalId) external {
        _proposals.execute(proposalId, delay);
    }

    function setGuardian(address guardian_, uint256 lifetime) external onlyAdminExecutor {
        _setGuardian(guardian_, lifetime);
    }

    function setAdmin(address newAdmin, uint256 timelockDuration) external onlyAdminExecutor {
        if (timelockDuration < MIN_TIMELOCK_DURATION || timelockDuration > MAX_TIMELOCK_DURATION) {
            revert InvalidTimelockDuration(
                timelockDuration,
                MIN_TIMELOCK_DURATION,
                MAX_TIMELOCK_DURATION
            );
        }
        _setAdmin(newAdmin, timelockDuration);
    }

    function resetToEmergencyAdmin() external onlyGuardian {
        // Shall be canceled all proposals created by the Dual Governance also? Seems like yes, but
        // need to think about it one more time
        _proposals.cancelAllProposals();
        _proposals.dequeueAllProposals();
        _setGuardian(address(0), 0);
        // TODO: Figure out is it correct to set min timelock duration?
        _setAdmin(EMERGENCY_ADMIN, MIN_TIMELOCK_DURATION);
        emit EmergencyAdminReset();
    }

    function getProposalsCount() external view returns (uint256 proposalsCount) {
        proposalsCount = _proposals.proposalsCount;
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        proposal = _proposals.get(proposalId);
    }

    function isProposed(uint256 proposalId) external view returns (bool isProposed_) {
        isProposed_ = _proposals.isProposed(proposalId);
    }

    function isEnqueued(uint256 proposalId) external view returns (bool isEnqueued_) {
        isEnqueued_ = _proposals.isEnqueued(proposalId);
    }

    function isExecutable(uint256 proposalId) external view returns (bool isExecutable_) {
        isExecutable_ = _proposals.isExecutable(proposalId, delay);
    }

    function isExecuted(uint256 proposalId) external view returns (bool isExecutable_) {
        isExecutable_ = _proposals.isExecuted(proposalId);
    }

    function isDequeued(uint256 proposalId) external view returns (bool isExecutable_) {
        isExecutable_ = _proposals.isDequeued(proposalId);
    }

    function isCanceled(uint256 proposalId) external view returns (bool isExecutable_) {
        isExecutable_ = _proposals.isCanceled(proposalId);
    }

    function _setAdmin(address newAdmin, uint256 timelockDuration) internal {
        if (newAdmin != admin) {
            admin = newAdmin;
            emit AdminSet(newAdmin);
        }
        if (delay != timelockDuration) {
            delay = timelockDuration;
            emit TimelockDurationSet(timelockDuration);
        }
    }

    function _setGuardian(address guardian_, uint256 lifetime) internal {
        if (guardian != guardian_) {
            guardian = guardian_;
            emit GuardianSet(guardian);
        }
        uint256 guardianActiveTill_ = block.timestamp + lifetime;
        if (guardianActiveTill != guardianActiveTill_) {
            guardianActiveTill = guardianActiveTill_;
            emit GuardianActiveTillSet(guardianActiveTill);
        }
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert NotAdmin(msg.sender);
        }
        _;
    }

    modifier onlyAdminExecutor() {
        if (msg.sender != ADMIN_EXECUTOR) {
            revert NotAdminExecutor(msg.sender);
        }
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) {
            revert NotGuardian(msg.sender);
        }
        if (block.timestamp >= guardianActiveTill) {
            revert GuardianLifetimeExpired();
        }
        _;
    }
}
