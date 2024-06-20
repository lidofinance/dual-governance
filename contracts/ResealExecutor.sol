// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISealable} from "./interfaces/ISealable.sol";

contract ResealExecutor is Ownable {
    error SenderIsNotCommittee();
    error DualGovernanceInNormalState();
    error SealableWrongPauseState();

    uint256 public constant PAUSE_INFINITELY = type(uint256).max;
    address public immutable DUAL_GOVERNANCE;

    constructor(address owner, address dualGovernance) Ownable(owner) {
        DUAL_GOVERNANCE = dualGovernance;
    }

    function reseal(address[] memory sealables) public onlyOwner {
        for (uint256 i = 0; i < sealables.length; ++i) {
            uint256 sealableResumeSinceTimestamp = ISealable(sealables[i]).getResumeSinceTimestamp();
            if (sealableResumeSinceTimestamp < block.timestamp || sealableResumeSinceTimestamp == PAUSE_INFINITELY) {
                revert SealableWrongPauseState();
            }
            Address.functionCall(sealables[i], abi.encodeWithSelector(ISealable.resume.selector));
            Address.functionCall(sealables[i], abi.encodeWithSelector(ISealable.pauseFor.selector, PAUSE_INFINITELY));
        }
    }
}
