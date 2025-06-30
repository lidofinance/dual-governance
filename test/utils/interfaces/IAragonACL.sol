// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAragonACL {
    function getPermissionManager(address app, bytes32 role) external view returns (address);
    function grantPermission(address grantee, address app, bytes32 role) external;
    function revokePermission(address entity, address app, bytes32 role) external;
    function setPermissionManager(address newManager, address app, bytes32 role) external;
    function hasPermission(address who, address app, bytes32 role) external view returns (bool);
}
