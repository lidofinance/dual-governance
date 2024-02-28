// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

abstract contract Blueprint {
    address private immutable _BLUEPRINT;

    error NotProxy();

    constructor() {
        _BLUEPRINT = address(this);
    }

    function _clone() internal returns (address instance) {
        instance = Clones.clone(_BLUEPRINT);
    }

    function _isBlueprint() internal view returns (bool) {
        return address(this) == _BLUEPRINT;
    }

    modifier onlyOnProxy() {
        if (_isBlueprint()) {
            revert NotProxy();
        }
        _;
    }
}
