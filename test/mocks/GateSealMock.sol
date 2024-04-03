// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISealable} from "contracts/interfaces/ISealable.sol";
import {IGateSeal} from "contracts/interfaces/IGateSeal.sol";

contract GateSealMock is IGateSeal {
    error GateSealExpired();

    event SealablesSealed(address[] sealables);

    uint256 internal constant _INFINITE_DURATION = type(uint256).max;

    uint256 internal _expiryTimestamp;
    uint256 internal _minSealDuration;
    address[] internal _sealedSealables;

    constructor(uint256 minSealDuration, uint256 lifetime) {
        _minSealDuration = minSealDuration;
        _expiryTimestamp = block.timestamp + lifetime;
    }

    function seal(address[] calldata sealables) external {
        if (_expiryTimestamp <= block.timestamp) {
            revert GateSealExpired();
        }
        _sealedSealables = sealables;
        _expiryTimestamp = block.timestamp;

        for (uint256 i = 0; i < sealables.length; ++i) {
            ISealable(sealables[i]).pauseFor(_INFINITE_DURATION);
            assert(ISealable(sealables[i]).isPaused());
        }

        emit SealablesSealed(sealables);
    }

    function sealed_sealables() external view returns (address[] memory) {
        return _sealedSealables;
    }

    function get_min_seal_duration() external view returns (uint256) {
        return _minSealDuration;
    }

    function get_expiry_timestamp() external view returns (uint256) {
        return _expiryTimestamp;
    }
}
