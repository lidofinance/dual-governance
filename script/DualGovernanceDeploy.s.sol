// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Configuration} from "contracts/Configuration.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";

contract DualGovernanceDeployScript is Script {
    address immutable STETH;
    address immutable WSTETH;
    address immutable BURNER;
    address immutable WITHDRAWAL_QUEUE;

    constructor(address stETH, address wstETH, address withdrawalQueue, address burner) {
        STETH = stETH;
        WSTETH = wstETH;
        WITHDRAWAL_QUEUE = withdrawalQueue;
        BURNER = burner;
    }

    function run(address timelock, address adminProposer) external returns (DualGovernance dualGovernance) {
        // deploy initial config impl
        address configImpl = address(new Configuration(adminProposer));

        // deploy config proxy
        ProxyAdmin configAdmin = new ProxyAdmin(address(this));
        TransparentUpgradeableProxy config =
            new TransparentUpgradeableProxy(configImpl, address(configAdmin), new bytes(0));

        // deploy DG
        address escrowImpl = address(new Escrow(address(config), STETH, WSTETH, WITHDRAWAL_QUEUE, BURNER));
        dualGovernance = new DualGovernance(address(config), configImpl, address(configAdmin), escrowImpl, timelock);
        configAdmin.transferOwnership(address(dualGovernance));
    }
}
