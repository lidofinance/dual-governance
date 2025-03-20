// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IWithdrawalVaultProxy {
    function proxy_changeAdmin(address admin) external payable;
    function proxy_getAdmin() external returns (address);
}
