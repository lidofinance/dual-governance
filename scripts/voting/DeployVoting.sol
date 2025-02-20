// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {Voting} from "./Voting.sol";

contract DeployVotingScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        new Voting(
            0xE29D4d0CAD66D87a054b5A93867C708000DaE1E6, // Dual Governance
            0x3Cc908B004422fd66FdB40Be062Bf9B0bd5BDbed, // Admin Executor
            0x517C93bb27aD463FE3AD8f15DaFDAD56EC0bEeC3 // Reseal Manager
        );
        vm.stopBroadcast();
    }
}
