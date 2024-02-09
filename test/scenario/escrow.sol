// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";
import {Configuration} from "contracts/Configuration.sol";

import {Escrow} from "contracts/Escrow.sol";
import {BurnerVault} from "contracts/BurnerVault.sol";

import "forge-std/Test.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

import {DualGovernanceSetup} from "./setup.sol";

contract EscrowHappyPath is DualGovernanceSetup {
    Escrow internal escrow;
    BurnerVault internal burnerVault;

    address internal ldoWhale;
    address internal stEthWhale;

    function test_setup() external {}

    function setUp() external {
        ldoWhale = makeAddr("ldo_whale");
        Utils.setupLdoWhale(ldoWhale);

        stEthWhale = makeAddr("steth_whale");
        Utils.setupStEthWhale(stEthWhale);

        TransparentUpgradeableProxy config;
        (, config,) = deployConfig(DAO_VOTING);

        (escrow, burnerVault) = deployEscrowImplementation(ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER, address(config));
    }
}
