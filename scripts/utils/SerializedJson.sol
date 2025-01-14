// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdJson} from "forge-std/StdJson.sol";
import {Vm} from "forge-std/Vm.sol";

struct SerializedJson {
    string serializationId;
    string str;
}

library SerializedJsonLib {
    // solhint-disable-next-line const-name-snakecase
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getInstance() internal returns (SerializedJson memory obj) {
        obj.serializationId = string(abi.encodePacked(address(this), _nextId()));
        obj.str = "";
    }

    function set(
        SerializedJson memory json,
        string memory key,
        uint256 value
    ) internal returns (SerializedJson memory) {
        json.str = stdJson.serialize(json.serializationId, key, value);
        return json;
    }

    function set(
        SerializedJson memory json,
        string memory key,
        string memory value
    ) internal returns (SerializedJson memory) {
        json.str = stdJson.serialize(json.serializationId, key, value);
        return json;
    }

    function set(
        SerializedJson memory json,
        string memory key,
        address value
    ) internal returns (SerializedJson memory) {
        json.str = stdJson.serialize(json.serializationId, key, value);
        return json;
    }

    function set(
        SerializedJson memory json,
        string memory key,
        address[] memory value
    ) internal returns (SerializedJson memory) {
        json.str = stdJson.serialize(json.serializationId, key, value);
        return json;
    }

    function _nextId() private returns (uint256 count) {
        bytes32 slot = keccak256("serialized-json-lib.id.counter");

        count = uint256(vm.load(address(this), slot));
        count += 1;
        vm.store(address(this), slot, bytes32(count));
    }
}
