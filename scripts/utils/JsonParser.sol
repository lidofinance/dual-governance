// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdJson} from "forge-std/StdJson.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {PercentsD16, PercentD16} from "contracts/types/PercentD16.sol";

library JsonParser {
    using stdJson for string;

    function readDuration(string memory json, string memory key) internal pure returns (Duration) {
        return Durations.from(json.readUint(key));
    }

    function readPercentD16BP(string memory json, string memory key) internal pure returns (PercentD16) {
        return PercentsD16.fromBasisPoints(json.readUint(key));
    }
}
