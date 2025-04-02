// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IVotingProvider {
    function getEVMScript() external view returns (bytes memory);
}
