// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, Vm} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {Escrow} from "contracts/Escrow.sol";
import {IConfiguration, Configuration} from "contracts/Configuration.sol";

import {DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE} from "../../utils/mainnet-addresses.sol";

contract EscrowUnitTests is Test {
    Configuration private _config;
    Escrow private _escrow;
    Escrow private _escrowMasterCopy;

    function setUp() external {
        _config = new Configuration(address(0), address(0), new address[](0));
        _escrowMasterCopy = new Escrow(ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, address(_config));
        _escrow = Escrow(payable(Clones.clone(address(_escrowMasterCopy))));
    }
}
