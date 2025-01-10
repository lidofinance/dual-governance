// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {stdJson} from "forge-std/StdJson.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StETHMock} from "./StETHMock.sol";
import {WstETHMock} from "./WstETHMock.sol";
import {UnsafeWithdrawalQueueMock} from "./UnsafeWithdrawalQueueMock.sol";
import {SerializedJson, SerializedJsonLib} from "../utils/SerializedJson.sol";

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

    function _printAddresses(DeployedMockContracts memory mockContracts) internal {
        console.log("Lido mocks deployed successfully");
        console.log("StETH address", mockContracts.stETH);
        console.log("WstETH address", mockContracts.wstETH);
        console.log("WithdrawalQueue address", mockContracts.withdrawalQueue);
        console.log("Copy these lines to your JSON deploy config", _serializeAddresses(mockContracts));
    }

    function _serializeAddresses(DeployedMockContracts memory mockContracts) internal returns (string memory) {
        SerializedJson memory addressesJson = SerializedJsonLib.getInstance();

        addressesJson.str =
            stdJson.serialize(addressesJson.serializationId, "HOLESKY_MOCK_ST_ETH", address(mockContracts.stETH));
        addressesJson.str =
            stdJson.serialize(addressesJson.serializationId, "HOLESKY_MOCK_WST_ETH", address(mockContracts.wstETH));
        addressesJson.str = stdJson.serialize(
            addressesJson.serializationId, "HOLESKY_MOCK_WITHDRAWAL_QUEUE", address(mockContracts.withdrawalQueue)
        );

        return addressesJson.str;
    }
}
