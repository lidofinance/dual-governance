// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IInsuranceFund {
    function transferOwnership(address newOwner) external;
    function owner() external view returns (address);
}
