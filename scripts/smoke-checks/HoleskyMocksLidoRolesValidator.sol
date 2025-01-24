// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AragonRolesAssertion} from "./libraries/AragonRolesAssertion.sol";
import {OZRolesAssertion} from "./libraries/OZRolesAssertion.sol";
import {LidoRolesValidator} from "./LidoRolesValidator.sol";

contract HoleskyMocksLidoRolesValidator is LidoRolesValidator {
    using OZRolesAssertion for OZRolesAssertion.Context;
    using AragonRolesAssertion for AragonRolesAssertion.Context;

    address public immutable ACL_ADDRESS = 0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC;
    address public immutable LIDO = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address public immutable VOTING = 0xdA7d2573Df555002503F29aA4003e398d28cc00f;
    address public immutable AGENT = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d;
    address public immutable WITHDRAWAL_QUEUE = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
    address public immutable EASYTRACK_ALLOWED_TOKENS_REGISTRY = 0x091C0eC8B4D54a9fcB36269B5D5E5AF43309e666;

    address public immutable DAO_KERNEL = 0x3b03f75Ec541Ca11a223bB58621A3146246E1644;
    address public immutable STAKING_ROUTER = 0xd6EbF043D30A7fe46D1Db32BA90a0A51207FE229;

    constructor() LidoRolesValidator(ACL_ADDRESS) {}

    function validate(address dgAdminExecutor, address dgResealManager) external {
        // _validate(LIDO, "STAKING_CONTROL_ROLE", AragonRolesAssertion.skipGrantedCheck());   <- Looks like obsolete
        // _validate(LIDO, "RESUME_ROLE", AragonRolesAssertion.skipGrantedCheck());   <- Looks like obsolete

        // From the initial gist
        _validate(DAO_KERNEL, "APP_MANAGER_ROLE", AragonRolesAssertion.checkManager(AGENT).skipGrantedCheck());
        _validate(STAKING_ROUTER, "DEFAULT_ADMIN_ROLE", OZRolesAssertion.grant(AGENT));

        // From the aragon-permissions.json
        _validate(AGENT, "RESUME_ROLE", AragonRolesAssertion.grant(LIDO));

        /////////////////////////////////////////////////////////////////////

        // Roles from scripts/dual_governance_upgrade_holesky.py in the PR https://github.com/lidofinance/scripts/pull/331
        _validate(LIDO, "STAKING_CONTROL_ROLE", AragonRolesAssertion.checkManager(AGENT).grant(AGENT).revoke(VOTING));

        _validate(WITHDRAWAL_QUEUE, "PAUSE_ROLE", OZRolesAssertion.grant(dgResealManager));
        _validate(WITHDRAWAL_QUEUE, "RESUME_ROLE", OZRolesAssertion.grant(dgResealManager));

        _validate(
            EASYTRACK_ALLOWED_TOKENS_REGISTRY, "DEFAULT_ADMIN_ROLE", AragonRolesAssertion.grant(VOTING).revoke(AGENT)
        );
        _validate(AGENT, "RUN_SCRIPT_ROLE", AragonRolesAssertion.grant(dgAdminExecutor));
    }
}
