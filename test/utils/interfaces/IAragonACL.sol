// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAragonACL {
    event ChangePermissionManager(address indexed app, bytes32 indexed role, address indexed manager);
    event SetPermission(address indexed entity, address indexed app, bytes32 indexed role, bool allowed);
    event SetPermissionParams(address indexed entity, address indexed app, bytes32 indexed role, bytes32 paramsHash);

    function getPermissionManager(address app, bytes32 role) external view returns (address);
    function grantPermission(address grantee, address app, bytes32 role) external;
    function hasPermission(address who, address app, bytes32 role) external view returns (bool);
    function setPermissionManager(address _newManager, address _app, bytes32 _role) external;
    function removePermissionManager(address _app, bytes32 _role) external;
    function revokePermission(address _entity, address _app, bytes32 _role) external;
}
