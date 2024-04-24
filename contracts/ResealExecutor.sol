// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {OwnableExecutor, Address} from "./OwnableExecutor.sol";
import {ISealable} from "./interfaces/ISealable.sol";

interface IDualGovernanace {
    enum GovernanceState {
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
        RageQuit
    }

    function currentState() external view returns (GovernanceState);
}

contract ResealExecutor is OwnableExecutor {
    event ResealCommitteeSet(address indexed newResealCommittee);

    error SenderIsNotCommittee();
    error DualGovernanceInNormalState();
    error SealableWrongPauseState();

    uint256 public constant PAUSE_INFINITELY = type(uint256).max;
    address public immutable DUAL_GOVERNANCE;

    address public resealCommittee;

    constructor(address owner, address dualGovernance, address resealCommitteeAddress) OwnableExecutor(owner) {
        DUAL_GOVERNANCE = dualGovernance;
        resealCommittee = resealCommitteeAddress;
    }

    function reseal(address[] memory sealables) public onlyCommittee {
        if (IDualGovernanace(DUAL_GOVERNANCE).currentState() == IDualGovernanace.GovernanceState.Normal) {
            revert DualGovernanceInNormalState();
        }
        for (uint256 i = 0; i < sealables.length; ++i) {
            uint256 sealableResumeSinceTimestamp = ISealable(sealables[i]).getResumeSinceTimestamp();
            if (sealableResumeSinceTimestamp < block.timestamp || sealableResumeSinceTimestamp == PAUSE_INFINITELY) {
                revert SealableWrongPauseState();
            }
            Address.functionCall(sealables[i], abi.encodeWithSelector(ISealable.resume.selector));
            Address.functionCall(sealables[i], abi.encodeWithSelector(ISealable.pauseFor.selector, PAUSE_INFINITELY));
        }
    }

    function setResealCommittee(address newResealCommittee) public onlyOwner {
        resealCommittee = newResealCommittee;
        emit ResealCommitteeSet(newResealCommittee);
    }

    modifier onlyCommittee() {
        if (msg.sender != resealCommittee) {
            revert SenderIsNotCommittee();
        }
        _;
    }
}
