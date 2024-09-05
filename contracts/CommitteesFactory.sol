pragma solidity 0.8.26;

import {EmergencyActivationCommittee} from "./committees/EmergencyActivationCommittee.sol";
import {TiebreakerSubCommittee} from "./committees/TiebreakerSubCommittee.sol";
import {EmergencyActivationCommittee} from "./committees/EmergencyActivationCommittee.sol";
import {TiebreakerCore} from "./committees/TiebreakerCore.sol";
import {ResealCommittee} from "./committees/ResealCommittee.sol";
import {Duration} from "./types/Duration.sol";

contract CommitteesFactory {
    function createEmergencyActivationCommittee(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) external returns (EmergencyActivationCommittee) {
        return new EmergencyActivationCommittee(owner, committeeMembers, executionQuorum, emergencyProtectedTimelock);
    }

    function createEmergencyExecutionCommittee(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) external returns (EmergencyActivationCommittee) {
        return new EmergencyActivationCommittee(owner, committeeMembers, executionQuorum, emergencyProtectedTimelock);
    }

    function createTiebreakerCore(
        address owner,
        address dualGovernance,
        Duration timelock
    ) external returns (TiebreakerCore) {
        return new TiebreakerCore(owner, dualGovernance, timelock);
    }

    function createTiebreakerSubCommittee(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address tiebreakerCore
    ) external returns (TiebreakerSubCommittee) {
        return new TiebreakerSubCommittee(owner, committeeMembers, executionQuorum, tiebreakerCore);
    }

    function createResealCommittee(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address dualGovernance,
        Duration timelock
    ) external returns (ResealCommittee) {
        return new ResealCommittee(owner, committeeMembers, executionQuorum, dualGovernance, timelock);
    }
}
