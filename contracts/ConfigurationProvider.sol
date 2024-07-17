// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IConfiguration} from "./interfaces/IConfiguration.sol";

contract ConfigurationProvider {
    error NotAdminExecutor(address account);

    IConfiguration public immutable CONFIG;

    constructor(address config) {
        CONFIG = IConfiguration(config);
    }

    function _checkAdminExecutor(address account) internal view {
        if (CONFIG.ADMIN_EXECUTOR() != account) {
            revert NotAdminExecutor(account);
        }
    }
}
