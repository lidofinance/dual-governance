// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

struct SerializedJson {
    string serializationId;
    string str;
}

library SerializedJsonLib {
    function getInstance() internal returns (SerializedJson memory obj) {
        obj.serializationId = string(abi.encodePacked(address(this), _nextId()));
        obj.str = "";
    }

    function _nextId() private returns (uint256 count) {
        bytes32 slot = keccak256("serialized-json-lib.id.counter");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            count := sload(slot)
            sstore(slot, add(count, 1))
        }
    }
}
