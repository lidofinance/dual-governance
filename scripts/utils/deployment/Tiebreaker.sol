// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {ImmutableDualGovernanceConfigProvider} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {ConfigFileReader, ConfigFileBuilder, JsonKeys} from "../ConfigFiles.sol";
import {DeployFiles} from "../DeployFiles.sol";

import {Duration} from "contracts/types/Duration.sol";

using JsonKeys for string;
using ConfigFileReader for ConfigFileReader.Context;
using ConfigFileBuilder for ConfigFileBuilder.Context;

// solhint-disable-next-line const-name-snakecase
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

struct TiebreakerSubCommitteeDeployConfig {
    address[] members;
    uint256 quorum;
}

library TiebreakerDeployConfig {
    error InvalidChainId(uint256 actual, uint256 expected);
    error InvalidParameter(string parameter);

    struct Context {
        uint256 chainId;
        address owner;
        address dualGovernance;
        uint256 quorum;
        Duration executionDelay;
        TiebreakerSubCommitteeDeployConfig[] committees;
    }

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (Context memory ctx) {
        string memory $ = configRootKey.root();
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        ctx.quorum = file.readUint($.key("quorum"));
        ctx.executionDelay = file.readDuration($.key("execution_delay"));

        uint256 committeesCount = file.readUint($.key("committees_count"));
        ctx.committees = new TiebreakerSubCommitteeDeployConfig[](committeesCount);

        for (uint256 i = 0; i < committeesCount; ++i) {
            string memory $committees = $.index("committees", i);
            ctx.committees[i].quorum = file.readUint($committees.key("quorum"));
            ctx.committees[i].members = file.readAddressArray($committees.key("members"));
        }

        if (file.keyExists($.key("owner"))) {
            ctx.owner = file.readAddress($.key("owner"));
        }
        if (file.keyExists($.key("dual_governance"))) {
            ctx.dualGovernance = file.readAddress($.key("dual_governance"));
        }
    }

    function validate(Context memory ctx) internal view {
        if (ctx.chainId != block.chainid) {
            revert InvalidChainId(block.chainid, ctx.chainId);
        }

        if (ctx.quorum == 0 || ctx.quorum > ctx.committees.length) {
            revert InvalidParameter("tiebreaker.quorum");
        }

        for (uint256 i = 0; i < ctx.committees.length; ++i) {
            if (ctx.committees[i].quorum == 0 || ctx.committees[i].quorum > ctx.committees[i].members.length) {
                revert InvalidParameter(string.concat("tiebreaker.committees[", vm.toString(i), "].quorum"));
            }
        }

        if (ctx.owner == address(0)) {
            revert InvalidParameter("tiebreaker.owner");
        }

        if (ctx.dualGovernance == address(0)) {
            revert InvalidParameter("tiebreaker.dual_governance");
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("owner", ctx.owner);
        builder.set("quorum", ctx.quorum);
        builder.set("execution_delay", ctx.executionDelay);
        builder.set("dual_governance", ctx.dualGovernance);
        builder.set("committees_count", ctx.committees.length);

        string[] memory tiebreakerCommitteesContent = new string[](ctx.committees.length);

        for (uint256 i = 0; i < ctx.committees.length; ++i) {
            // forgefmt: disable-next-item
            tiebreakerCommitteesContent[i] = ConfigFileBuilder.create()
                .set("quorum", ctx.committees[i].quorum)
                .set("members", ctx.committees[i].members)
                .content;
        }

        builder.set("committees", tiebreakerCommitteesContent);

        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("===== Tiebreaker");
        console.log("Tiebreaker Owner", ctx.owner);
        console.log("Tiebreaker Dual Governance", ctx.dualGovernance);
        console.log("Tiebreaker Quorum", ctx.quorum);
        console.log("Tiebreaker Execution Delay", ctx.executionDelay.toSeconds());
        console.log("\n");

        for (uint256 i = 0; i < ctx.committees.length; ++i) {
            console.log("===== Tiebreaker Committee [%d]", i);
            console.log("Committee Quorum: %d", ctx.committees[i].quorum);
            console.log("Committee Members:");
            for (uint256 j = 0; j < ctx.committees[i].members.length; ++j) {
                console.log("Committee Member [%d] %s", j, ctx.committees[i].members[j]);
            }
            console.log("\n");
        }
    }
}

library TiebreakerDeployedContracts {
    using ConfigFileReader for ConfigFileReader.Context;

    struct Context {
        TiebreakerCoreCommittee tiebreakerCoreCommittee;
        TiebreakerSubCommittee[] tiebreakerSubCommittees;
    }

    function load(
        string memory deployedContractsFilePath,
        string memory prefix
    ) internal view returns (Context memory ctx) {
        string memory $ = prefix.root();
        ConfigFileReader.Context memory deployedContract = ConfigFileReader.load(deployedContractsFilePath);

        ctx.tiebreakerCoreCommittee =
            TiebreakerCoreCommittee(deployedContract.readAddress($.key("tiebreaker_core_committee")));

        address[] memory subCommittees = deployedContract.readAddressArray($.key("tiebreaker_sub_committees"));
        ctx.tiebreakerSubCommittees = new TiebreakerSubCommittee[](subCommittees.length);
        for (uint256 i = 0; i < subCommittees.length; ++i) {
            ctx.tiebreakerSubCommittees[i] = TiebreakerSubCommittee(subCommittees[i]);
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("tiebreaker_core_committee", address(ctx.tiebreakerCoreCommittee));

        address[] memory subCommittees = new address[](ctx.tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < ctx.tiebreakerSubCommittees.length; ++i) {
            subCommittees[i] = address(ctx.tiebreakerSubCommittees[i]);
        }
        builder.set("tiebreaker_sub_committees", subCommittees);

        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("TiebreakerCoreCommittee address", address(ctx.tiebreakerCoreCommittee));

        for (uint256 i = 0; i < ctx.tiebreakerSubCommittees.length; ++i) {
            console.log("TiebreakerSubCommittee[%d] address %x", i, address(ctx.tiebreakerSubCommittees[i]));
        }
    }
}
