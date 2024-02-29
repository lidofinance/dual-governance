// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

abstract contract MasterCopy {
    address private immutable _MASTER_COPY;

    error MasterCopyCallForbidden();

    constructor() {
        _MASTER_COPY = address(this);
    }

    function _clone() internal returns (address instance) {
        instance = Clones.clone(_MASTER_COPY);
    }

    function _isMasterCopy() internal view returns (bool) {
        return address(this) == _MASTER_COPY;
    }

    modifier onlyInstance() {
        if (_isMasterCopy()) {
            revert MasterCopyCallForbidden();
        }
        _;
    }
}
