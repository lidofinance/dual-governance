// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ExecutorCall} from "contracts/libraries/ScheduledCalls.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {IExecutor} from "./interfaces/IExecutor.sol";
import {Configuration} from "./Configuration.sol";
import {GovernanceState} from "./GovernanceState.sol";

interface IGateSeal {
    function isTriggered() external view returns (bool);
}

struct Proposer {
    address account;
    address executor;
}

library Proposers {
    using SafeCast for uint256;

    error ProposerNotRegistered(address proposer);
    error ProposerAlreadyRegistered(address proposer);

    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    struct ExecutorData {
        uint8 proposerIndexOneBased; // indexed from 1. The count of executors is limited
        address executor;
    }

    struct State {
        address[] proposers;
        mapping(address proposer => ExecutorData) executors;
    }

    function register(State storage self, address proposer, address executor) internal {
        if (self.executors[proposer].proposerIndexOneBased != 0) {
            revert ProposerAlreadyRegistered(proposer);
        }
        self.proposers.push(proposer);
        self.executors[proposer] = ExecutorData(self.proposers.length.toUint8(), executor);
        emit ProposerRegistered(proposer, executor);
    }

    function unregister(State storage self, address proposer) internal {
        uint256 proposerIndexToDelete;
        ExecutorData memory executorData = self.executors[proposer];
        unchecked {
            proposerIndexToDelete = executorData.proposerIndexOneBased - 1;
        }
        if (proposerIndexToDelete == type(uint256).max) {
            revert ProposerNotRegistered(proposer);
        }

        uint256 lastProposerIndex = self.proposers.length - 1;
        if (proposerIndexToDelete != lastProposerIndex) {
            self.proposers[proposerIndexToDelete] = self.proposers[lastProposerIndex];
        }
        self.proposers.pop();
        delete self.executors[proposer];
        emit ProposerUnregistered(proposer, executorData.executor);
    }

    function all(State storage self) internal view returns (Proposer[] memory proposers) {
        proposers = new Proposer[](self.proposers.length);
        for (uint256 i = 0; i < proposers.length; ++i) {
            proposers[i] = get(self, self.proposers[i]);
        }
    }

    function get(State storage self, address account) internal view returns (Proposer memory proposer) {
        ExecutorData memory executorData = self.executors[account];
        if (executorData.proposerIndexOneBased == 0) {
            revert ProposerNotRegistered(account);
        }
        proposer.account = account;
        proposer.executor = executorData.executor;
    }

    function isProposer(State storage self, address proposer) internal view returns (bool) {
        return self.executors[proposer].proposerIndexOneBased != 0;
    }
}

struct Proposal {
    uint256 id;
    address proposer;
    address executor;
    uint256 scheduledAt;
    uint256 executedAt;
    ExecutorCall[] calls;
}

struct ProposalPacked {
    address proposer;
    uint40 scheduledAt;
    uint40 executedAt;
    address executor;
    ExecutorCall[] calls;
}

library Proposals {
    using SafeCast for uint256;

    // The id of the first proposal
    uint256 private constant FIRST_PROPOSAL_ID = 1;

    struct State {
        // any proposals with ids less or equal to the given one cannot be executed
        uint256 lastCanceledProposalId;
        ProposalPacked[] proposals;
    }

    error EmptyCalls();
    error ProposalCanceled(uint256 proposalId);
    error ProposalNotFound(uint256 proposalId);
    error ProposalNotExecutable(uint256 proposalId);
    error ProposalAlreadyExecuted(uint256 proposalId);
    error InvalidAdoptionDelay(uint256 adoptionDelay);

    event Proposed(uint256 indexed id, address indexed proposer, address indexed executor, ExecutorCall[] calls);
    event ProposalsCanceledTill(uint256 proposalId);

    function schedule(
        State storage self,
        address proposer,
        address executor,
        ExecutorCall[] calldata calls
    ) internal returns (uint256 newProposalId) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        newProposalId = self.proposals.length;
        self.proposals.push();

        ProposalPacked storage newProposal = self.proposals[newProposalId];
        newProposal.proposer = proposer;
        newProposal.executor = executor;
        newProposal.executedAt = 0;
        newProposal.scheduledAt = block.timestamp.toUint40();

        // copying of arrays of custom types from calldata to storage has not been supported by the
        // Solidity compiler yet, so insert item by item
        for (uint256 i = 0; i < calls.length; ++i) {
            newProposal.calls.push(calls[i]);
        }

        emit Proposed(newProposalId, proposer, executor, calls);
    }

    function cancelAll(State storage self) internal {
        uint256 lastProposalId = self.proposals.length;
        self.lastCanceledProposalId = lastProposalId;
        emit ProposalsCanceledTill(lastProposalId);
    }

    function execute(State storage self, uint256 proposalId, uint256 delay) internal {
        if (delay == 0) {
            revert InvalidAdoptionDelay(0);
        }

        ProposalPacked storage packed = _packed(self, proposalId);

        if (proposalId <= self.lastCanceledProposalId) {
            revert ProposalCanceled(proposalId);
        }
        uint256 scheduledAt = packed.scheduledAt;
        if (packed.executedAt != 0) {
            revert ProposalAlreadyExecuted(proposalId);
        }
        if (block.timestamp < scheduledAt + delay) {
            revert ProposalNotExecutable(proposalId);
        }
        packed.executedAt = block.timestamp.toUint40();
        _executeCalls(packed.executor, packed.calls);
    }

    function get(State storage self, uint256 proposalId) internal view returns (Proposal memory proposal) {
        proposal = _unpack(proposalId, _packed(self, proposalId));
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.proposals.length;
    }

    function isExecutable(State storage self, uint256 proposalId, uint256 delay) internal view returns (bool) {
        ProposalPacked storage packed = _packed(self, proposalId);
        if (packed.executedAt != 0) return false;
        if (proposalId <= self.lastCanceledProposalId) return false;
        return block.timestamp > packed.scheduledAt + delay;
    }

    function _executeCalls(address executor, ExecutorCall[] memory calls) private returns (bytes[] memory results) {
        uint256 callsCount = calls.length;

        assert(callsCount > 0);

        address target;
        uint256 value;
        bytes memory payload;
        results = new bytes[](callsCount);
        for (uint256 i = 0; i < callsCount; ++i) {
            value = calls[i].value;
            target = calls[i].target;
            payload = calls[i].payload;
            results[i] = IExecutor(payable(executor)).execute(target, value, payload);
        }
    }

    function _packed(State storage self, uint256 proposalId) private view returns (ProposalPacked storage packed) {
        if (proposalId < FIRST_PROPOSAL_ID || proposalId > self.proposals.length) {
            revert ProposalNotFound(proposalId);
        }
        packed = self.proposals[proposalId - FIRST_PROPOSAL_ID];
    }

    function _unpack(uint256 id, ProposalPacked memory packed) private pure returns (Proposal memory proposal) {
        proposal.id = id;
        proposal.calls = packed.calls;
        proposal.proposer = packed.proposer;
        proposal.executor = packed.executor;
        proposal.executedAt = packed.executedAt;
        proposal.scheduledAt = packed.scheduledAt;
    }
}

interface ITimelockController {
    function isExecutionEnabled() external view returns (bool);
    function isSchedulingEnabled() external view returns (bool);
}

contract Committee {
    error NotCommittee(address sender, address committee);

    address public immutable COMMITTEE;

    constructor(address committee) {
        COMMITTEE = committee;
    }

    function _checkCommittee() internal view {
        if (msg.sender != COMMITTEE) {
            revert NotCommittee(msg.sender, COMMITTEE);
        }
    }

    modifier onlyCommittee() virtual {
        _checkCommittee();
        _;
    }
}

contract ExpirableCommittee is Committee {
    error CommitteeExpired(uint256 expirationDate);

    uint256 public immutable EXPIRED_AFTER;

    constructor(address committee, uint256 lifetime) Committee(committee) {
        EXPIRED_AFTER = block.number + lifetime;
    }

    function _checkExpired() internal view {
        if (block.number > EXPIRED_AFTER) {
            revert CommitteeExpired(EXPIRED_AFTER);
        }
    }

    modifier onlyCommittee() override {
        _checkCommittee();
        _checkExpired();
        _;
    }
}

contract ResetTimelockControllerGuardian is ExpirableCommittee {
    Timelock public immutable TIMELOCK;

    constructor(address timelock, address committee, uint256 lifetime) ExpirableCommittee(committee, lifetime) {
        TIMELOCK = Timelock(timelock);
    }

    function resetController() external onlyCommittee {
        TIMELOCK.cancelAll();
        TIMELOCK.setController(address(0));
        TIMELOCK.renounceRole(TIMELOCK.GUARDIAN_ROLE(), address(this));
    }
}

contract EmergencyModeGuardian is ExpirableCommittee {
    error EmergencyModeNotActive();
    error EmergencyModeNodePassed(uint256 endsAfter);
    error EmergencyModeActivated(uint256 activatedAt);

    Timelock public immutable TIMELOCK;
    uint256 public immutable EMERGENCY_MODE_DURATION;

    uint256 internal _emergencyModeActivatedAt;

    constructor(
        address timelock,
        address committee,
        uint256 lifetime,
        uint256 emergencyModeDuration
    ) ExpirableCommittee(committee, lifetime) {
        TIMELOCK = Timelock(timelock);
        EMERGENCY_MODE_DURATION = emergencyModeDuration;
    }

    function activateEmergencyMode() external onlyCommittee {
        if (_emergencyModeActivatedAt != 0) {
            revert EmergencyModeActivated(_emergencyModeActivatedAt);
        }
        TIMELOCK.pause();
        _emergencyModeActivatedAt = block.timestamp;
    }

    function deactivateEmergencyMode() external {
        bool isEmergencyModeEnded = block.timestamp >= _emergencyModeActivatedAt + EMERGENCY_MODE_DURATION;

        if (!isEmergencyModeEnded && msg.sender != TIMELOCK.ADMIN_EXECUTOR()) {
            revert EmergencyModeNodePassed(_emergencyModeActivatedAt + EMERGENCY_MODE_DURATION);
        }

        TIMELOCK.cancelAll();
        TIMELOCK.resume();
        TIMELOCK.renounceRole(TIMELOCK.GUARDIAN_ROLE(), address(this));
    }

    function execute(uint256 proposalId) external onlyCommittee {
        if (_emergencyModeActivatedAt == 0) {
            revert EmergencyModeNotActive();
        }
        TIMELOCK.executeByGuardian(proposalId);
    }

    function getEmergencyModeEndsAfter() external view returns (uint256) {
        return _emergencyModeActivatedAt == 0 ? 0 : _emergencyModeActivatedAt + EMERGENCY_MODE_DURATION;
    }
}

contract TiebreakCommitteeGuardian is Committee {
    Timelock public immutable TIMELOCK;
    IGateSeal public immutable GATE_SEAL;
    Configuration public immutable CONFIG;
    GovernanceState public immutable GOV_STATE;

    constructor(address committee) Committee(committee) {}

    function execute(uint256 proposalId) external {
        if (_isRageQuitAndGateSealTriggered() || _isDualGovernanceLocked()) {
            TIMELOCK.executeByGuardian(proposalId);
            return;
        }
        revert("Dual Governance is not locked");
    }

    function _isRageQuitAndGateSealTriggered() internal view returns (bool) {
        return GATE_SEAL.isTriggered() && GOV_STATE.currentState() == GovernanceState.State.RageQuit;
    }

    function _isDualGovernanceLocked() internal view returns (bool) {
        (GovernanceState.State state_, uint256 enteredAt) = GOV_STATE.stateInfo();
        return
            state_ != GovernanceState.State.Normal && block.timestamp > enteredAt + CONFIG.tieBreakerActivationTimeout();
    }
}

contract Timelock is Pausable, AccessControlEnumerable {
    using Proposers for Proposers.State;
    using Proposals for Proposals.State;

    error SchedulingDisabled();
    error ExecutionDisabled();
    error NotController(address sender);
    error NotAdminExecutor(address sender);

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant CONTROLLER_MANAGER_ROLE = keccak256("CONTROLLER_MANAGER_ROLE");

    address public immutable ADMIN_EXECUTOR;
    address public immutable ADMIN_PROPOSER;

    uint256 public immutable MIN_TIMELOCK_DURATION = 2 days;
    uint256 public immutable MAX_TIMELOCK_DURATION = 30 days;

    uint256 internal _delay;
    Proposers.State internal _proposers;
    Proposals.State internal _proposals;
    ITimelockController internal _controller;

    constructor(address adminProposer, address adminExecutor, uint256 delay) {
        ADMIN_PROPOSER = adminProposer;
        ADMIN_EXECUTOR = adminExecutor;
        _proposers.register(adminProposer, adminExecutor);

        _delay = delay;

        _grantRole(DEFAULT_ADMIN_ROLE, adminExecutor);
        _grantRole(CONTROLLER_MANAGER_ROLE, adminExecutor);
    }

    function schedule(ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        Proposer memory proposer = _proposers.get(msg.sender);
        if (!_isSchedulingEnabled()) {
            revert SchedulingDisabled();
        }
        newProposalId = _proposals.schedule(proposer.account, proposer.executor, calls);
    }

    function execute(uint256 proposalId) external whenNotPaused {
        if (!_isExecutionEnabled()) {
            revert ExecutionDisabled();
        }
        _proposals.execute(proposalId, _delay);
    }

    function executeByGuardian(uint256 proposalId) external onlyRole(GUARDIAN_ROLE) {
        _proposals.execute(proposalId, _delay);
    }

    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function resume() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    function cancelAll() external onlyRole(GUARDIAN_ROLE) {
        _proposals.cancelAll();
    }

    function setController(address controller) external onlyRole(CONTROLLER_MANAGER_ROLE) {
        _controller = ITimelockController(controller);
    }

    function registerProposer(address proposer, address executor) external onlyAdminExecutor {
        return _proposers.register(proposer, executor);
    }

    function unregisterProposer(address proposer) external onlyAdminExecutor {
        _proposers.unregister(proposer);
    }

    function transferExecutorOwnership(address executor, address owner) external onlyAdminExecutor {
        IOwnable(executor).transferOwnership(owner);
    }

    function getController() external view returns (address) {
        return address(_controller);
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        proposal = _proposals.get(proposalId);
    }

    function getProposalsCount() external view returns (uint256 count) {
        count = _proposals.count();
    }

    function getIsExecutable(uint256 proposalId) external view returns (bool isExecutable) {
        return !paused() && _isExecutionEnabled() && _proposals.isExecutable(proposalId, _delay);
    }

    function _isSchedulingEnabled() internal view returns (bool) {
        return address(_controller) == address(0) ? true : _controller.isSchedulingEnabled();
    }

    function _isExecutionEnabled() internal view returns (bool) {
        return address(_controller) == address(0) ? true : _controller.isExecutionEnabled();
    }

    modifier onlyAdminExecutor() {
        if (msg.sender != ADMIN_EXECUTOR) {
            revert NotAdminExecutor(msg.sender);
        }
        _;
    }
}
