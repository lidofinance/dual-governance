// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EmergencyActivationCommittee} from "../../contracts/EmergencyActivationCommittee.sol";

import {ExecutiveCommitteeUnitTest, ExecutiveCommittee} from "./ExecutiveCommittee.t.sol";

contract EmergencyActivationCommitteeUnitTest is ExecutiveCommitteeUnitTest {
    EmergencyActivationCommittee internal _emergencyActivationCommittee;

    EmergencyProtectedTimelockMock internal _emergencyProtectedTimelock;

    function setUp() public {
        _emergencyProtectedTimelock = new EmergencyProtectedTimelockMock();
        _emergencyActivationCommittee =
            new EmergencyActivationCommittee(_owner, _committeeMembers, _quorum, address(_emergencyProtectedTimelock));
        _executiveCommittee = ExecutiveCommittee(_emergencyActivationCommittee);
    }
}

contract EmergencyProtectedTimelockMock {}
