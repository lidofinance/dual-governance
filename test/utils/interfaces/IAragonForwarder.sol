// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAragonForwarder {
    function forward(bytes memory evmScript) external;
}
