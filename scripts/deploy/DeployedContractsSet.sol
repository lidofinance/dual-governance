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
}

library DGContractsSet {
    using stdJson for string;
    using SerializedJsonLib for SerializedJson;

    function print(DeployedContracts memory contracts) internal pure {
        console.log("DualGovernance address", address(contracts.dualGovernance));
        console.log("ResealManager address", address(contracts.resealManager));
        console.log("TiebreakerCoreCommittee address", address(contracts.tiebreakerCoreCommittee));

        for (uint256 i = 0; i < contracts.tiebreakerSubCommittees.length; i++) {
            console.log("TiebreakerSubCommittee", i, "address", address(contracts.tiebreakerSubCommittees[i]));
        }
        console.log("AdminExecutor address", address(contracts.adminExecutor));
        console.log("EmergencyProtectedTimelock address", address(contracts.timelock));
        console.log("EmergencyGovernance address", address(contracts.emergencyGovernance));
    }

    function loadFromFile(string memory file) internal pure returns (DeployedContracts memory) {
        address[] memory tiebreakerSubCommitteeAddresses =
            file.readAddressArray(".DEPLOYED_CONTRACTS.TIEBREAKER_SUB_COMMITTEES");
        TiebreakerSubCommittee[] memory tiebreakerSubCommittees =
            new TiebreakerSubCommittee[](tiebreakerSubCommitteeAddresses.length);
        for (uint256 i = 0; i < tiebreakerSubCommitteeAddresses.length; i++) {
            tiebreakerSubCommittees[i] = TiebreakerSubCommittee(tiebreakerSubCommitteeAddresses[i]);
        }

        return DeployedContracts({
            adminExecutor: Executor(payable(file.readAddress(".DEPLOYED_CONTRACTS.ADMIN_EXECUTOR"))),
            timelock: IEmergencyProtectedTimelock(file.readAddress(".DEPLOYED_CONTRACTS.TIMELOCK")),
            emergencyGovernance: TimelockedGovernance(file.readAddress(".DEPLOYED_CONTRACTS.EMERGENCY_GOVERNANCE")),
            resealManager: ResealManager(file.readAddress(".DEPLOYED_CONTRACTS.RESEAL_MANAGER")),
            dualGovernance: DualGovernance(file.readAddress(".DEPLOYED_CONTRACTS.DUAL_GOVERNANCE")),
            tiebreakerCoreCommittee: TiebreakerCoreCommittee(
                file.readAddress(".DEPLOYED_CONTRACTS.TIEBREAKER_CORE_COMMITTEE")
            ),
            tiebreakerSubCommittees: tiebreakerSubCommittees
        });
    }

    function serialize(DeployedContracts memory contracts) internal returns (SerializedJson memory) {
        address[] memory tiebreakerSubCommitteeAddresses = new address[](contracts.tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < contracts.tiebreakerSubCommittees.length; i++) {
            tiebreakerSubCommitteeAddresses[i] = address(contracts.tiebreakerSubCommittees[i]);
        }

        SerializedJson memory addressesJson = SerializedJsonLib.getInstance();

        addressesJson.set("ADMIN_EXECUTOR", address(contracts.adminExecutor));
        addressesJson.set("TIMELOCK", address(contracts.timelock));
        addressesJson.set("EMERGENCY_GOVERNANCE", address(contracts.emergencyGovernance));
        addressesJson.set("RESEAL_MANAGER", address(contracts.resealManager));
        addressesJson.set("DUAL_GOVERNANCE", address(contracts.dualGovernance));
        addressesJson.set("TIEBREAKER_CORE_COMMITTEE", address(contracts.tiebreakerCoreCommittee));
        addressesJson.set("TIEBREAKER_SUB_COMMITTEES", tiebreakerSubCommitteeAddresses);

        return addressesJson;
    }
}
