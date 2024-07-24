// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

struct AdminExecutorConfigState {
    address adminExecutor;
}

interface IAdminExecutorConfig {
    function ADMIN_EXECUTOR() external view returns (address);
    function getAdminExecutionConfig() external view returns (AdminExecutorConfigState memory);
}

contract AdminExecutorConfig is IAdminExecutorConfig {
    address public immutable ADMIN_EXECUTOR;

    constructor(AdminExecutorConfigState memory input) {
        ADMIN_EXECUTOR = input.adminExecutor;
    }

    function getAdminExecutionConfig() external view returns (AdminExecutorConfigState memory config) {
        config.adminExecutor = ADMIN_EXECUTOR;
    }
}

library AdminExecutorConfigUtils {
    error NotAdminExecutor(address account);

    function checkAdminExecutor(IAdminExecutorConfig config, address account) internal view {
        if (config.ADMIN_EXECUTOR() != account) {
            revert NotAdminExecutor(account);
        }
    }
}
