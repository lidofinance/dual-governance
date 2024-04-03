// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IGateSeal {
    function get_min_seal_duration() external view returns (uint256);
    function get_expiry_timestamp() external view returns (uint256);
    function sealed_sealables() external view returns (address[] memory);
    function seal(address[] calldata sealables) external;
}