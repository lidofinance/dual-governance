// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ISealable} from "./interfaces/ISealable.sol";

interface IEmergencyProtectedTimelock {
    function getGovernance() external view returns (address);
}

contract ResealManager {
    error SealableWrongPauseState();
    error SenderIsNotGovernance();
    error NotAllowed();

    uint256 public constant PAUSE_INFINITELY = type(uint256).max;
    address public immutable EMERGENCY_PROTECTED_TIMELOCK;

    constructor(address emergencyProtectedTimelock) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;
    }

    function reseal(address[] memory sealables) public onlyGovernance {
        for (uint256 i = 0; i < sealables.length; ++i) {
            uint256 sealableResumeSinceTimestamp = ISealable(sealables[i]).getResumeSinceTimestamp();
            if (sealableResumeSinceTimestamp < block.timestamp || sealableResumeSinceTimestamp == PAUSE_INFINITELY) {
                revert SealableWrongPauseState();
            }
            Address.functionCall(sealables[i], abi.encodeWithSelector(ISealable.resume.selector));
            Address.functionCall(sealables[i], abi.encodeWithSelector(ISealable.pauseFor.selector, PAUSE_INFINITELY));
        }
    }

    function resume(address sealable) public onlyGovernance {
        uint256 sealableResumeSinceTimestamp = ISealable(sealable).getResumeSinceTimestamp();
        if (sealableResumeSinceTimestamp < block.timestamp) {
            revert SealableWrongPauseState();
        }
        Address.functionCall(sealable, abi.encodeWithSelector(ISealable.resume.selector));
    }

    modifier onlyGovernance() {
        address governance = IEmergencyProtectedTimelock(EMERGENCY_PROTECTED_TIMELOCK).getGovernance();
        if (msg.sender != governance) {
            revert SenderIsNotGovernance();
        }
        _;
    }
}
