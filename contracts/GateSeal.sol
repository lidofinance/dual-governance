// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IPausableUntil {
    function resume() external;
    function pauseFor(uint256 duration) external;
    function pauseUntil(uint256 _pauseUntilInclusive) external;
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
    error GateSealExpired();
    error GovernanceIsBlocked();
    error GateSealNotActivated();
    error SealDurationNotPassed();
    error NotSealingCommittee();

    uint256 internal constant INFINITE_DURATION = type(uint256).max;

    uint256 public immutable SEAL_DURATION;
    address public immutable SEALING_COMMITTEE;
    IGovernanceState public immutable GOV_STATE;

    address[] internal _sealables;
    uint256 internal _expiryTimestamp;
    uint256 internal _releaseTimestamp;

    function isTriggered() external view returns (bool) {}

    function expiryTimestamp() external view returns (uint256) {
        return _expiryTimestamp;
    }

    constructor(address sealingCommittee, uint256 sealDuration, address govState, address[] memory sealables) {
        GOV_STATE = IGovernanceState(govState);
        SEAL_DURATION = sealDuration;
        SEALING_COMMITTEE = sealingCommittee;
        _sealables = sealables;
        _expiryTimestamp = block.timestamp + sealDuration;
    }

    function seal(address[] calldata sealables) external onlySealingCommittee {
        if (block.timestamp > _expiryTimestamp) {
            revert GateSealExpired();
        }
        _expiryTimestamp = block.timestamp;
        _releaseTimestamp = block.timestamp + SEAL_DURATION;
        for (uint256 i = 0; i < sealables.length; ++i) {
            IPausableUntil(sealables[i]).pauseFor(INFINITE_DURATION);
            assert(IPausableUntil(sealables[i]).isPaused());
        }
    }

    // when the sealable was paused forever, this method may unlock it if the pause was
    function release(address[] calldata sealables) external {
        if (_expiryTimestamp == 0) {
            revert GateSealNotActivated();
        }

        IGovernanceState.State govState = GOV_STATE.currentState();
        // TODO: check is it safe to allow release seal in the veto cooldown state
        if (govState != IGovernanceState.State.Normal && govState != IGovernanceState.State.VetoCooldown) {
            revert GovernanceIsBlocked();
        }
        if (block.timestamp < _releaseTimestamp) {
            revert SealDurationNotPassed();
        }

        for (uint256 i = 0; i < sealables.length; ++i) {
            IPausableUntil sealable = IPausableUntil(sealables[i]);
            assert(IPausableUntil(sealable).isPaused());
            IPausableUntil(sealable).resume();
            assert(!IPausableUntil(sealable).isPaused());
        }
    }

    function _assertSealingCommittee() internal view {
        if (msg.sender != SEALING_COMMITTEE) {
            revert NotSealingCommittee();
        }
    }

    modifier onlySealingCommittee() {
        _assertSealingCommittee();
        _;
    }
}
