// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/stdJson.sol";
import {stdToml} from "forge-std/StdToml.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";
import {PercentsD16, PercentD16} from "contracts/types/PercentD16.sol";

enum ConfigFormat {
    JSON,
    TOML
}

library ConfigFileReader {
    // solhint-disable-next-line const-name-snakecase
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error InvalidConfigFormat(uint256 format);

    struct Context {
        ConfigFormat format;
        string content;
    }

    function load(string memory path) internal view returns (Context memory ctx) {
        ctx.format = getFileFormatByPath(path);
        ctx.content = vm.readFile(path);
    }

    function readUint(Context memory ctx, string memory key) internal pure returns (uint256) {
        if (ctx.format == ConfigFormat.JSON) return stdJson.readUint(ctx.content, key);
        if (ctx.format == ConfigFormat.TOML) return stdToml.readUint(ctx.content, key);
        revert InvalidConfigFormat(uint256(ctx.format));
    }

    function readDuration(Context memory ctx, string memory key) internal pure returns (Duration) {
        return Durations.from(readUint(ctx, key));
    }

    function readTimestamp(Context memory ctx, string memory key) internal pure returns (Timestamp) {
        return Timestamps.from(readUint(ctx, key));
    }

    function readPercentD16BP(Context memory ctx, string memory key) internal pure returns (PercentD16) {
        return PercentsD16.fromBasisPoints(readUint(ctx, key));
    }

    function readAddress(Context memory ctx, string memory key) internal pure returns (address) {
        if (ctx.format == ConfigFormat.JSON) return stdJson.readAddress(ctx.content, key);
        if (ctx.format == ConfigFormat.TOML) return stdToml.readAddress(ctx.content, key);
        revert InvalidConfigFormat(uint256(ctx.format));
    }

    function readAddressArray(Context memory ctx, string memory key) internal pure returns (address[] memory) {
        if (ctx.format == ConfigFormat.JSON) return stdJson.readAddressArray(ctx.content, key);
        if (ctx.format == ConfigFormat.TOML) return stdToml.readAddressArray(ctx.content, key);
        revert InvalidConfigFormat(uint256(ctx.format));
    }

    function getFileFormatByPath(string memory path) internal pure returns (ConfigFormat) {
        // solhint-disable-next-line custom-errors
        require(bytes(path).length > 0, "empty file path");

        string[] memory pathSplit = vm.split(path, ".");

        string memory fileFormat = pathSplit[pathSplit.length - 1];
        bytes32 fileExtensionDigest = keccak256(bytes(vm.toLowercase(fileFormat)));

        if (fileExtensionDigest == keccak256(bytes("toml"))) {
            return ConfigFormat.TOML;
        } else if (fileExtensionDigest == keccak256(bytes("json"))) {
            return ConfigFormat.JSON;
        }
        // solhint-disable-next-line custom-errors
        revert(string.concat("Unsupported file format: ", fileFormat));
    }

    function readRaw(Context memory ctx, string memory key) internal pure returns (bytes memory) {
        if (ctx.format == ConfigFormat.JSON) return stdJson.parseRaw(ctx.content, key);
        if (ctx.format == ConfigFormat.TOML) return stdToml.parseRaw(ctx.content, key);
        revert InvalidConfigFormat(uint256(ctx.format));
    }
}
