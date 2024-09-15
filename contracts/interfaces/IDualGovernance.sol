// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGovernance} from "./IGovernance.sol";
import {ITiebreaker} from "./ITiebreaker.sol";
import {Timestamp} from "../types/Timestamp.sol";
import {Duration} from "../types/Duration.sol";
import {State} from "../libraries/DualGovernanceStateMachine.sol";

interface IDualGovernance is IGovernance, ITiebreaker {
    struct StateDetails {
        State state;
        Timestamp enteredAt;
        State nextState;
        Timestamp vetoSignallingActivatedAt;
        Timestamp vetoSignallingReactivationTime;
        Timestamp normalOrVetoCooldownExitedAt;
        uint256 rageQuitRound;
        Duration vetoSignallingDuration;
    }

    function activateNextState() external;

    function resealSealable(address sealables) external;
}
