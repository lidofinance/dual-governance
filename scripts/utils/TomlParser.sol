// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdToml} from "forge-std/StdToml.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {PercentsD16, PercentD16} from "contracts/types/PercentD16.sol";

library TomlParser {
    using stdToml for string;

    function readDuration(string memory toml, string memory key) internal pure returns (Duration) {
        return Durations.from(toml.readUint(key));
    }

    function readPercentD16BP(string memory toml, string memory key) internal pure returns (PercentD16) {
        return PercentsD16.fromBasisPoints(toml.readUint(key));
    }
}
