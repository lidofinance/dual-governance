// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IGateSeal {
    function seal(address[] calldata sealables) external;
}
