// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StETHMock} from "./StETHMock.sol";
import {WstETHMock} from "./WstETHMock.sol";
import {UnsafeWithdrawalQueueMock} from "./UnsafeWithdrawalQueueMock.sol";

struct DeployedMockContracts {
    address stETH;
    address wstETH;
    address withdrawalQueue;
}

contract DeployHoleskyLidoMocks is Script {
    error DoNotRunThisOnMainnet(uint256 currentChainId);

    address private deployer;

    function run() external {
        if (1 == block.chainid) {
            revert DoNotRunThisOnMainnet(block.chainid);
        }

        deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        vm.startBroadcast();

        DeployedMockContracts memory mockContracts = _deployLidoMockContracts();

        vm.stopBroadcast();

        _printAddresses(mockContracts);
    }

    function _deployLidoMockContracts() internal returns (DeployedMockContracts memory mockContracts) {
        StETHMock stETH = new StETHMock();
        WstETHMock wstETH = new WstETHMock(stETH);
        UnsafeWithdrawalQueueMock withdrawalQueue = new UnsafeWithdrawalQueueMock(address(stETH), payable(deployer));

        stETH.mint(deployer, 100 gwei);

        mockContracts.stETH = address(stETH);
        mockContracts.wstETH = address(wstETH);
        mockContracts.withdrawalQueue = address(withdrawalQueue);
    }

    function _printAddresses(DeployedMockContracts memory mockContracts) internal pure {
        console.log("Lido mocks deployed successfully");
        console.log("StETH address", mockContracts.stETH);
        console.log("WstETH address", mockContracts.wstETH);
        console.log("WithdrawalQueue address", mockContracts.withdrawalQueue);
        console.log("Copy these lines to your TOML deploy config", _serializeAddresses(mockContracts));
    }

    function _serializeAddresses(DeployedMockContracts memory mockContracts) internal pure returns (string memory) {
        string memory addressesToml = string.concat(
            "\n[dual_governance.signalling_tokens]\nst_eth = \"", Strings.toHexString(address(mockContracts.stETH))
        );
        addressesToml =
            string.concat(addressesToml, "\"\nwst_eth = \"", Strings.toHexString(address(mockContracts.wstETH)));
        addressesToml = string.concat(
            addressesToml,
            "\"\nwithdrawal_queue = \"",
            Strings.toHexString(address(mockContracts.withdrawalQueue)),
            "\""
        );

        return addressesToml;
    }
}
