// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AragonRoles} from "../libraries/AragonRoles.sol";
import {OZRoles} from "../libraries/OZRoles.sol";

import {LidoRolesValidator} from "../LidoRolesValidator.sol";

contract HoleskyMocksLidoRolesValidator is LidoRolesValidator {
    using OZRoles for OZRoles.Context;
    using AragonRoles for AragonRoles.Context;

    address public immutable ACL_ADDRESS = 0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC;
    address public immutable LIDO = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address public immutable VOTING = 0xdA7d2573Df555002503F29aA4003e398d28cc00f;
    address public immutable AGENT = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d;
    address public immutable WITHDRAWAL_QUEUE = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
    address public immutable EASYTRACK_ALLOWED_TOKENS_REGISTRY = 0x091C0eC8B4D54a9fcB36269B5D5E5AF43309e666;

    constructor() LidoRolesValidator(ACL_ADDRESS) {}

    function validate(address dgAdminExecutor, address dgResealManager) external {
        // Roles from scripts/dual_governance_upgrade_holesky.py in the PR https://github.com/lidofinance/scripts/pull/331
        _validate(LIDO, "STAKING_CONTROL_ROLE", AragonRoles.checkManager(AGENT).granted(AGENT).revoked(VOTING));

        _validate(WITHDRAWAL_QUEUE, "PAUSE_ROLE", OZRoles.granted(dgResealManager));
        _validate(WITHDRAWAL_QUEUE, "RESUME_ROLE", OZRoles.granted(dgResealManager));

        _validate(EASYTRACK_ALLOWED_TOKENS_REGISTRY, "DEFAULT_ADMIN_ROLE", AragonRoles.granted(VOTING).revoked(AGENT));
        _validate(AGENT, "RUN_SCRIPT_ROLE", AragonRoles.granted(dgAdminExecutor));
    }
}
