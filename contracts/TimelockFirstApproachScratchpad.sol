// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Configuration} from "./Configuration.sol";

interface IGateSeal {
    function isTriggered() external view returns (bool);
}

interface IGovernanceState {
    enum State {
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
        RageQuit
    }

    function currentState() external view returns (State);
    function state() external view returns (State state, uint256 enteredAt);
    function activateNextState() external returns (State);
}

struct Proposer {
    address account;
    address executor;
}

struct ExecutorCall {
    address target;
    uint96 value; // ~ 7.9 billion ETH
    bytes payload;
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
    uint256 proposedAt;
    uint256 adoptedAt;
    ExecutorCall[] calls;
}

struct ProposalPacked {
    address proposer;
    uint40 proposedAt;
    // Time passed, starting from the proposedAt till the adoption of the proposal
    uint32 adoptionTime;
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
    error ProposalAlreadyAdopted(uint256 proposalId, uint256 adoptedAt);
    error ProposalNotExecutable(uint256 proposalId);
    error InvalidAdoptionDelay(uint256 adoptionDelay);

    event Proposed(uint256 indexed id, address indexed proposer, address indexed executor, ExecutorCall[] calls);
    event ProposalsCanceledTill(uint256 proposalId);

    function create(
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
        newProposal.adoptionTime = 0;
        newProposal.proposedAt = block.timestamp.toUint40();

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

    function adopt(State storage self, uint256 proposalId, uint256 delay) internal returns (Proposal memory proposal) {
        ProposalPacked storage packed = _packed(self, proposalId);

        if (proposalId <= self.lastCanceledProposalId) {
            revert ProposalCanceled(proposalId);
        }
        uint256 proposedAt = packed.proposedAt;
        if (packed.adoptionTime != 0) {
            revert ProposalAlreadyAdopted(proposalId, proposedAt + packed.adoptionTime);
        }
        if (block.timestamp < proposedAt + delay) {
            revert ProposalNotExecutable(proposalId);
        }
        uint256 adoptionTime = block.timestamp - proposedAt;
        // the proposal can't be proposed and adopted at the same transaction
        if (adoptionTime == 0) {
            revert InvalidAdoptionDelay(0);
        }
        packed.adoptionTime = adoptionTime.toUint32();
        proposal = _unpack(proposalId, packed);
    }

    function execute(State storage self, uint256 proposalId, uint256 delay) internal {
        // Works similar to ScheduledCalls.execute() but marks proposal as executed
        // instead of calls deletion
        // TODO: implement
    }

    function get(State storage self, uint256 proposalId) internal view returns (Proposal memory proposal) {
        proposal = _unpack(proposalId, _packed(self, proposalId));
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.proposals.length;
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
        proposal.proposedAt = packed.proposedAt;
        proposal.adoptedAt = packed.adoptionTime == 0 ? 0 : proposal.proposedAt + packed.adoptionTime;
    }
}

interface IDelayer {
    function getDelay() external view returns (uint256);
    function beforeSchedule() external returns (bool isSchedulingAllowed);
    function beforeExecute() external returns (bool isExecutionAllowed);
}

contract PauseExecutionEmergencyCommittee {
    Timelock timelock;

    uint256 emergencyModeDuration;
    uint256 emergencyModeActivatedAt;

    function activateEmergencyMode() external {
        timelock.pause();
        emergencyModeActivatedAt = block.timestamp;
    }

    function deactivateEmergencyMode() external {
        if (block.timestamp < emergencyModeActivatedAt + emergencyModeDuration) {
            revert("emergency duration not passed");
        }
        timelock.cancelAll();
        timelock.resume();
    }

    function execute(uint256 proposalId) external {
        timelock.executeUrgently(proposalId);
    }
}

contract TiebreakCommittee {
    Timelock timelock;
    DualGovernanceDelayer delayer;
    IGateSeal gateSeal;

    function execute(uint256 proposalId) external {
        if (_isRageQuitAndGateSealTriggered() || _isDualGovernanceLocked()) {
            timelock.executeUrgently(proposalId);
            return;
        }
        revert("Dual Governance is not locked");
    }

    function _isRageQuitAndGateSealTriggered() internal view returns (bool) {
        return gateSeal.isTriggered() && delayer.state() == IGovernanceState.State.RageQuit;
    }

    function _isDualGovernanceLocked() internal view returns (bool) {
        return delayer.isLocked();
    }
}

contract ResetDualGovernanceEmergencyCommittee {
    Timelock timelock;
}

contract DualGovernanceDelayer is IDelayer {
    Configuration public immutable CONFIG;
    IGovernanceState internal immutable GOV_STATE;

    function isLocked() external view returns (bool) {
        (IGovernanceState.State state_, uint256 enteredAt) = GOV_STATE.state();
        return state_ != IGovernanceState.State.Normal
            && block.timestamp > enteredAt + CONFIG.tieBreakerActivationTimeout();
    }

    function state() external view returns (IGovernanceState.State) {
        return GOV_STATE.currentState();
    }

    function getDelay() external view returns (uint256) {
        return CONFIG.minProposalExecutionTimelock();
    }

    function beforeSchedule() external returns (bool isSchedulingAllowed) {
        GOV_STATE.activateNextState();
    }

    function beforeExecute() external returns (bool isExecutionAllowed) {
        GOV_STATE.activateNextState();
    }
}

contract Timelock {
    using Proposers for Proposers.State;
    using Proposals for Proposals.State;

    address public immutable ADMIN_EXECUTOR;
    address public immutable ADMIN_PROPOSER;

    uint256 public immutable MIN_TIMELOCK_DURATION = 2 days;

    bool _isPaused;
    IDelayer internal _delayer;
    Proposers.State internal _proposers;
    Proposals.State internal _proposals;

    // emergency committee and tiebreak committee are guardians
    address[] internal _guardians;

    function schedule(ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        bool isSchedulingAllowed = _delayer.beforeSchedule();
        if (!isSchedulingAllowed) {
            revert("scheduling disabled");
        }
        Proposer memory proposer = _proposers.get(msg.sender);
        newProposalId = _proposals.create(proposer.account, proposer.executor, calls);
    }

    function execute(uint256 proposalId) external {
        if (_isPaused) {
            revert("paused");
        }
        bool isExecutionAllowed = _delayer.beforeExecute();
        if (!isExecutionAllowed) {
            revert("execution disabled");
        }
        uint256 delay = Math.max(MIN_TIMELOCK_DURATION, _delayer.getDelay());

        _proposals.execute(proposalId, delay);
    }

    // executes even when delay is not passed

    function pause() external onlyGuardian {}

    function resume() external onlyGuardian {}

    function cancelAll() external onlyGuardian {}

    // allows execution of the proposal without touching the delayer
    function executeUrgently(uint256 proposalId) external onlyGuardian {
        uint256 delay = MIN_TIMELOCK_DURATION;
        _proposals.execute(proposalId, delay);
    }

    modifier onlyGuardian() {
        _;
    }
}
