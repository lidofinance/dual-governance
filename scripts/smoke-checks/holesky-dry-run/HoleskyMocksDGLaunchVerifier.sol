// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";
import {DGLaunchVerifier} from "../DGLaunchVerifier.sol";

contract HoleskyMocksDGLaunchVerifier is DGLaunchVerifier {
    constructor()
        // TODO: use the correct values for the dry run. The following values are provided exclusively for demo purposes.
        DGLaunchVerifier(
            0xd70D836D60622D48648AA1dE759361D6B9a4Baa0,
            0x5A2958dC9532bAaCdF8481C8278735B1b05FB199,
            0x89E3A5f9F41c90cBBbD3D1626df541F334680597,
            0x526d46eCa1d7969924e981ecDbcAa74e9f0EE566,
            0x526d46eCa1d7969924e981ecDbcAa74e9f0EE566,
            Timestamps.from(1738601280),
            Durations.from(900),
            2
        )
    {}
}
