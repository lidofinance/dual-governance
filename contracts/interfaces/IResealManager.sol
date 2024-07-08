// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IResealManager {
    function resume(address sealable) external;
    function reseal(address[] memory sealables) external;
}
