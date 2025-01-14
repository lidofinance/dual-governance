// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {Executor} from "contracts/Executor.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
import {SerializedJson, SerializedJsonLib} from "../utils/SerializedJson.sol";

struct DeployedContracts {
    Executor adminExecutor;
    IEmergencyProtectedTimelock timelock;
    TimelockedGovernance emergencyGovernance;
    ResealManager resealManager;
    DualGovernance dualGovernance;
    TiebreakerCoreCommittee tiebreakerCoreCommittee;
    TiebreakerSubCommittee[] tiebreakerSubCommittees;
    TimelockedGovernance temporaryEmergencyGovernance;
}

library DGContractsSet {
    using stdJson for string;
    using SerializedJsonLib for SerializedJson;

    function print(DeployedContracts memory contracts) internal pure {
        console.log("DualGovernance address", address(contracts.dualGovernance));
        console.log("ResealManager address", address(contracts.resealManager));
        console.log("TiebreakerCoreCommittee address", address(contracts.tiebreakerCoreCommittee));

        for (uint256 i = 0; i < contracts.tiebreakerSubCommittees.length; ++i) {
            console.log("TiebreakerSubCommittee #", i, "address", address(contracts.tiebreakerSubCommittees[i]));
        }

        console.log("AdminExecutor address", address(contracts.adminExecutor));
        console.log("EmergencyProtectedTimelock address", address(contracts.timelock));
        console.log("EmergencyGovernance address", address(contracts.emergencyGovernance));
        console.log("TemporaryEmergencyGovernance address", address(contracts.temporaryEmergencyGovernance));
    }

    function loadFromFile(string memory file) internal pure returns (DeployedContracts memory) {
        address[] memory tiebreakerSubCommitteesAddresses = file.readAddressArray(".TIEBREAKER_SUB_COMMITTEES");
        TiebreakerSubCommittee[] memory tiebreakerSubCommittees =
            new TiebreakerSubCommittee[](tiebreakerSubCommitteesAddresses.length);
        for (uint256 i = 0; i < tiebreakerSubCommitteesAddresses.length; ++i) {
            tiebreakerSubCommittees[i] = TiebreakerSubCommittee(tiebreakerSubCommitteesAddresses[i]);
        }

        return DeployedContracts({
            adminExecutor: Executor(payable(file.readAddress(".ADMIN_EXECUTOR"))),
            timelock: IEmergencyProtectedTimelock(file.readAddress(".TIMELOCK")),
            emergencyGovernance: TimelockedGovernance(file.readAddress(".EMERGENCY_GOVERNANCE")),
            resealManager: ResealManager(file.readAddress(".RESEAL_MANAGER")),
            dualGovernance: DualGovernance(file.readAddress(".DUAL_GOVERNANCE")),
            tiebreakerCoreCommittee: TiebreakerCoreCommittee(file.readAddress(".TIEBREAKER_CORE_COMMITTEE")),
            tiebreakerSubCommittees: tiebreakerSubCommittees,
            temporaryEmergencyGovernance: TimelockedGovernance(file.readAddress(".TEMPORARY_EMERGENCY_GOVERNANCE"))
        });
    }

    function serialize(DeployedContracts memory contracts) internal returns (SerializedJson memory) {
        SerializedJson memory addressesJson = SerializedJsonLib.getInstance();
        address[] memory tiebreakerSubCommitteesAddresses = new address[](contracts.tiebreakerSubCommittees.length);

        for (uint256 i = 0; i < contracts.tiebreakerSubCommittees.length; ++i) {
            tiebreakerSubCommitteesAddresses[i] = address(contracts.tiebreakerSubCommittees[i]);
        }

        addressesJson.set("ADMIN_EXECUTOR", address(contracts.adminExecutor));
        addressesJson.set("TIMELOCK", address(contracts.timelock));
        addressesJson.set("EMERGENCY_GOVERNANCE", address(contracts.emergencyGovernance));
        addressesJson.set("RESEAL_MANAGER", address(contracts.resealManager));
        addressesJson.set("DUAL_GOVERNANCE", address(contracts.dualGovernance));
        addressesJson.set("TIEBREAKER_CORE_COMMITTEE", address(contracts.tiebreakerCoreCommittee));
        addressesJson.set("TIEBREAKER_SUB_COMMITTEES", tiebreakerSubCommitteesAddresses);
        addressesJson.set("TEMPORARY_EMERGENCY_GOVERNANCE", address(contracts.temporaryEmergencyGovernance));

        return addressesJson;
    }
}
