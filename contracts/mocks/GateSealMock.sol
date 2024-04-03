// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IGovernanceState} from "../interfaces/IGovernanceState.sol";

interface IPausableUntil {
    function resume() external;
    function pauseFor(uint256 duration) external;
    function pauseUntil(uint256 _pauseUntilInclusive) external;
    function isPaused() external view returns (bool);
}

contract GateSealMock {
    error GateSealExpired();
    error GovernanceIsBlocked();
    error GateSealNotActivated();
    error SealDurationNotPassed();
    error NotSealingCommittee();

    uint256 internal constant INFINITE_DURATION = type(uint256).max;

    uint256 internal immutable MIN_SEAL_DURATION_SECONDS = 14 days;
    uint256 internal immutable SEAL_DURATION_SECONDS;
    uint256 internal immutable MAX_SEAL_DURATION_SECONDS = INFINITE_DURATION;
    address internal immutable SEALING_COMMITTEE;
    IGovernanceState internal immutable GOV_STATE;

    address[] internal _sealables;
    address[] internal _sealed;

    uint256 internal _expiryTimestamp;
    uint256 internal _releaseTimestamp;

    constructor(
        address govState,
        address sealingCommittee,
        uint256 lifetime,
        uint256 sealDuration,
        address[] memory sealables
    ) {
        GOV_STATE = IGovernanceState(govState);
        SEAL_DURATION_SECONDS = sealDuration;
        SEALING_COMMITTEE = sealingCommittee;
        _sealables = sealables;
        _expiryTimestamp = block.timestamp + lifetime;
    }

    function seal(address[] calldata sealables) external onlySealingCommittee {
        if (block.timestamp > _expiryTimestamp) {
            revert GateSealExpired();
        }
        _expiryTimestamp = block.timestamp;
        _sealed = _sealables;

        if (SEAL_DURATION_SECONDS == INFINITE_DURATION) {
            _releaseTimestamp = INFINITE_DURATION;
        } else {
            _releaseTimestamp = block.timestamp + SEAL_DURATION_SECONDS;
        }

        for (uint256 i = 0; i < sealables.length; ++i) {
            IPausableUntil(sealables[i]).pauseFor(INFINITE_DURATION);
            assert(IPausableUntil(sealables[i]).isPaused());
        }
    }

    function get_expiry_timestamp() external view returns (uint256) {
        return _expiryTimestamp;
    }

    function get_min_seal_duration() external pure returns (uint256) {
        return MIN_SEAL_DURATION_SECONDS;
    }

    function sealed_sealables() external view returns (address[] memory) {
        return _sealed;
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
