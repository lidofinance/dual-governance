// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";

// @title UpgradeConstantsHoodi
// @notice This contract contains constants for Dual Governance upgrade on Hoodi testnet
contract UpgradeConstantsHoodi {
    address public constant VOTING = 0x49B3512c44891bef83F8967d075121Bd1b07a01B;
    address public constant DUAL_GOVERNANCE = 0x4d12b9f6aCAB54FF6a3a776BA3b8724D9B77845F;
    address public constant TIMELOCK = 0x0A5E22782C0Bd4AddF10D771f0bF0406B038282d;
    address public constant ADMIN_EXECUTOR = 0x0eCc17597D292271836691358B22340b78F3035B;
    address public constant WITHDRAWAL_QUEUE = 0xfe56573178f1bcdf53F01A6E9977670dcBBD9186;
    address public constant VALIDATORS_EXIT_BUS_ORACLE = 0x8664d394C2B3278F26A1B44B967aEf99707eeAB2;
    address public constant TRIGGERABLE_WITHDRAWALS_GATEWAY = 0x6679090D92b08a2a686eF8614feECD8cDFE209db;
    address public constant RESEAL_COMMITTEE = 0x83BCE68B4e8b7071b2a664a26e6D3Bc17eEe3102;
    Duration public constant TIEBREAKER_ACTIVATION_TIMEOUT = Duration.wrap(900 seconds);
}
