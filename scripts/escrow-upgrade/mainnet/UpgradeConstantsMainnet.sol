// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";

// @title UpgradeConstantsMainnet
// @notice This contract contains constants for Dual Governance upgrade on Mainnet
contract UpgradeConstantsMainnet {
    address public constant VOTING = 0x2e59A20f205bB85a89C53f1936454680651E618e;
    address public constant AGENT = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
    address public constant DUAL_GOVERNANCE = 0xcdF49b058D606AD34c5789FD8c3BF8B3E54bA2db;
    address public constant TIMELOCK = 0xCE0425301C85c5Ea2A0873A2dEe44d78E02D2316;
    address public constant ADMIN_EXECUTOR = 0x23E0B465633FF5178808F4A75186E2F2F9537021;
    address public constant WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
    address public constant VALIDATORS_EXIT_BUS_ORACLE = 0x0De4Ea0184c2ad0BacA7183356Aea5B8d5Bf5c6e;
    address public constant RESEAL_COMMITTEE = 0xFFe21561251c49AdccFad065C94Fb4931dF49081;
    Duration public constant TIEBREAKER_ACTIVATION_TIMEOUT = Duration.wrap(31536000 seconds);
    address public constant MATIC_TOKEN = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address public constant LABS_BORG_FOUNDATION = 0x95B521B4F55a447DB89f6a27f951713fC2035f3F;
}
