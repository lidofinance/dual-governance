// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IPausableUntil {
    function resume() external;
    function pauseFor(uint256 duration) external;
    function isPaused() external view returns (bool);
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
}

contract GateSeal {
    struct Sealable {
        bool isSealable;
        bool isSealed;
    }

    struct SealingError {
        address sealable;
        bytes executionError;
    }

    error NotSealingCommittee();
    error CommitteeExpired();
    error SealingReverted(SealingError[] errors);
    error GovernanceIsBlocked();
    error NotOwner();
    error SealDurationNotPassed();
    error ReleaseExpired();
    error ReleaseArleadyStarted();
    error ReleaseNotStarted();

    event ErrorWhileResuming(address sealable, bytes reason);
    event SealingCommitteeSet(address sealingCommittee, uint256 committeeExpiryTimestamp);
    event SealablesSet(address[] sealables);
    event Sealed(address[] sealables);
    event ReleaseReset();
    event ReleaseStarted(uint256 releaseTimestamp);
    event Released(address sealables);

    uint256 internal constant INFINITE_DURATION = type(uint256).max;

    IGovernanceState public immutable GOV_STATE;
    uint256 public immutable RELEASE_TIMELOCK;
    uint256 public immutable RELEASE_EXPIRY;
    uint256 public immutable SEALING_COMMITTEE_LIFETIME;
    address public immutable OWNER;

    uint256 internal _releaseTimestamp;
    address[] internal _pausedSealables;
    uint256 internal _sealingCommitteeLifetime;

    address[] public sealables;
    mapping(address => Sealable) sealableStatuses;

    address public sealingCommittee;
    uint256 public committeeExpiryTimestamp;

    constructor(
        address owner,
        address govState,
        address _sealingCommittee,
        uint256 lifetime,
        uint256 releaseTimelock,
        uint256 releaseExpiry,
        address[] memory _sealables
    ) {
        OWNER = owner;
        GOV_STATE = IGovernanceState(govState);
        RELEASE_TIMELOCK = releaseTimelock;
        RELEASE_EXPIRY = releaseExpiry;
        SEALING_COMMITTEE_LIFETIME = lifetime;

        sealables = _sealables;

        for (uint256 i = 0; i < _sealables.length; ++i) {
            sealableStatuses[_sealables[i]] = Sealable(true, false);
        }

        sealingCommittee = _sealingCommittee;
        committeeExpiryTimestamp = block.timestamp + lifetime;

        emit SealingCommitteeSet(sealingCommittee, committeeExpiryTimestamp);
        emit SealablesSet(sealables);
    }

    function setSealingCommittee(address _sealingCommittee) public onlyOwner {
        sealingCommittee = _sealingCommittee;
        committeeExpiryTimestamp = block.timestamp + SEALING_COMMITTEE_LIFETIME;

        for (uint256 i = 0; i < sealables.length; ++i) {
            sealableStatuses[sealables[i]] = Sealable(true, false);
        }

        emit SealingCommitteeSet(sealingCommittee, committeeExpiryTimestamp);
        emit SealablesSet(sealables);
    }

    function setSealables(address[] calldata _sealables) public onlyOwner {
        for (uint256 i = 0; i < sealables.length; ++i) {
            sealableStatuses[sealables[i]] = Sealable(false, false);
        }
        for (uint256 i = 0; i < _sealables.length; ++i) {
            sealableStatuses[sealables[i]] = Sealable(true, false);
        }
        sealables = _sealables;

        emit SealablesSet(sealables);
    }

    function seal(address[] calldata _sealables) external onlySealingCommittee {
        committeeExpiryTimestamp = block.timestamp;
        _releaseTimestamp = 0;

        SealingError[] memory revertMessages = new SealingError[](sealables.length);
        uint256 lastRevertIdx = 0;

        for (uint256 i = 0; i < _sealables.length; ++i) {
            assert(sealableStatuses[_sealables[i]].isSealable);

            try IPausableUntil(_sealables[i]).pauseFor(INFINITE_DURATION) {
                sealableStatuses[_sealables[i]].isSealed = true;
                if (IPausableUntil(_sealables[i]).isPaused() == false) {
                    revertMessages[lastRevertIdx++] = SealingError(_sealables[i], bytes("Sealable is not paused"));
                }
            } catch (bytes memory reason) {
                revertMessages[lastRevertIdx++] = SealingError(_sealables[i], reason);
            }
        }
        if (lastRevertIdx > 0) {
            revert SealingReverted(revertMessages);
        }

        emit Sealed(_sealables);
        emit ReleaseReset();
    }

    function startRelease() public {
        if (_releaseTimestamp > 0) {
            revert ReleaseArleadyStarted();
        }

        IGovernanceState.State govState = GOV_STATE.currentState();
        // TODO: check is it safe to allow release seal in the veto cooldown state
        if (govState != IGovernanceState.State.Normal && govState != IGovernanceState.State.VetoCooldown) {
            revert GovernanceIsBlocked();
        }

        _releaseTimestamp = block.timestamp + RELEASE_TIMELOCK;

        emit ReleaseStarted(_releaseTimestamp);
    }

    function enactRelease() external {
        if (_releaseTimestamp == 0) {
            revert ReleaseNotStarted();
        }

        if (block.timestamp < _releaseTimestamp) {
            revert SealDurationNotPassed();
        }

        if (block.timestamp > _releaseTimestamp + RELEASE_EXPIRY) {
            revert ReleaseExpired();
        }

        for (uint256 i = 0; i < sealables.length; ++i) {
            if (sealableStatuses[sealables[i]].isSealable && sealableStatuses[sealables[i]].isSealed) {
                IPausableUntil sealable = IPausableUntil(sealables[i]);
                if (sealable.isPaused()) {
                    try sealable.resume() {
                        emit Released(sealables[i]);
                    } catch (bytes memory reason) {
                        emit ErrorWhileResuming(sealables[i], reason);
                        continue;
                    }
                }
                sealableStatuses[sealables[i]].isSealed = false;
            }
        }
    }

    function isAnySealed(address[] memory _sealables) public view returns (bool) {
        for (uint256 i = 0; i < _sealables.length; ++i) {
            if (sealableStatuses[_sealables[i]].isSealed) {
                return true;
            }
        }
        return false;
    }

    function isAnySealed() public view returns (bool) {
        return isAnySealed(sealables);
    }

    modifier onlySealingCommittee() {
        if (msg.sender != sealingCommittee) {
            revert NotSealingCommittee();
        }
        if (block.timestamp > committeeExpiryTimestamp) {
            revert CommitteeExpired();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert NotOwner();
        }
        _;
    }
}
