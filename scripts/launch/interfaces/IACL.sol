// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IACL {
    function hasPermission(address _who, address _where, bytes32 _what) external view returns (bool);
    function createPermission(address _entity, address _app, bytes32 _role, address _manager) external;
    function grantPermission(address _entity, address _app, bytes32 _role) external;
    function revokePermission(address _entity, address _app, bytes32 _role) external;

    function setPermissionManager(address _newManager, address _app, bytes32 _role) external;
    function getPermissionManager(address _app, bytes32 _role) external view returns (address);
}
