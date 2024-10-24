// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StETHMock} from "./StETHMock.sol";
import {WstETHMock} from "./WstETHMock.sol";
import {UnsafeWithdrawalQueueMock} from "./UnsafeWithdrawalQueueMock.sol";

struct DeployedContracts {
    address stETH;
    address wstETH;
    address withdrawalQueue;
}

contract DeployHoleskyLidoMocks is Script {
    error ChainIdMismatch(uint256 actual, uint256 expected);

    address private deployer;

    function run() external {
        if (17000 != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: 17000});
        }

        deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        vm.startBroadcast();

        DeployedContracts memory res = deployLidoMockContracts();

        vm.stopBroadcast();

        printAddresses(res);
    }

    function deployLidoMockContracts() internal returns (DeployedContracts memory res) {
        StETHMock stETH = new StETHMock();
        WstETHMock wstETH = new WstETHMock(stETH);
        UnsafeWithdrawalQueueMock withdrawalQueue = new UnsafeWithdrawalQueueMock(address(stETH), payable(deployer));

        stETH.mint(deployer, 100 gwei);

        res.stETH = address(stETH);
        res.wstETH = address(wstETH);
        res.withdrawalQueue = address(withdrawalQueue);
    }

    function printAddresses(DeployedContracts memory res) internal pure {
        console.log("Lido mocks deployed successfully");
        console.log("StETH address", res.stETH);
        console.log("WstETH address", res.wstETH);
        console.log("WithdrawalQueue address", res.withdrawalQueue);
    }
}
