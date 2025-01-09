// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

// TODO: check license

pragma solidity 0.8.26;

struct SerializedJson {
    string ref;
    string str;
}

// @see https://github.com/lidofinance/community-staking-module/blob/main/script/utils/Json.sol
library SerializedJsonLib {
    function newObj() internal returns (SerializedJson memory obj) {
        obj.ref = string(abi.encodePacked(address(this), _incrementId()));
        obj.str = "";
    }

    function _incrementId() private returns (uint256 count) {
        bytes32 slot = keccak256("serialized-json.id.counter");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            count := sload(slot)
            sstore(slot, add(count, 1))
        }
    }
}

using SerializedJsonLib for SerializedJson global;
