// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {stdToml} from "forge-std/StdToml.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

// solhint-disable-next-line const-name-snakecase
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

enum ConfigFormat {
    JSON,
    TOML
}

error EmptyFilePath();
error InvalidConfigFormat(uint256 format);
error UnsupportedFileFormat(string format);

function getFileFormatByPath(string memory path) pure returns (ConfigFormat) {
    // solhint-disable-next-line custom-errors
    if (bytes(path).length == 0) {
        revert EmptyFilePath();
    }

    string[] memory pathSplit = vm.split(path, ".");

    string memory fileFormat = pathSplit[pathSplit.length - 1];
    bytes32 fileExtensionDigest = keccak256(bytes(vm.toLowercase(fileFormat)));

    if (fileExtensionDigest == keccak256(bytes("toml"))) {
        return ConfigFormat.TOML;
    } else if (fileExtensionDigest == keccak256(bytes("json"))) {
        return ConfigFormat.JSON;
    }
    revert UnsupportedFileFormat(fileFormat);
}

library ConfigFileReader {
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

    function keyExists(Context memory ctx, string memory key) internal view returns (bool) {
        if (ctx.format == ConfigFormat.JSON) return stdJson.keyExists(ctx.content, key);
        if (ctx.format == ConfigFormat.TOML) return stdToml.keyExists(ctx.content, key);
        revert InvalidConfigFormat(uint256(ctx.format));
    }
}

library ConfigFileBuilder {
    struct Context {
        string id;
        string content;
    }

    function create() internal returns (Context memory ctx) {
        ctx.id = _nextId();
    }

    function write(Context memory ctx, string memory path) internal {
        ConfigFormat outputFileFormat = getFileFormatByPath(path);

        if (outputFileFormat == ConfigFormat.JSON) {
            stdJson.write(ctx.content, path);
        } else if (outputFileFormat == ConfigFormat.TOML) {
            stdToml.write(ctx.content, path);
        } else {
            revert InvalidConfigFormat(uint256(outputFileFormat));
        }
    }

    function set(Context memory ctx, string memory key, uint256 value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, Duration value) internal returns (Context memory) {
        return set(ctx, key, value.toSeconds());
    }

    function set(Context memory ctx, string memory key, Timestamp value) internal returns (Context memory) {
        return set(ctx, key, value.toSeconds());
    }

    function set(Context memory ctx, string memory key, PercentD16 value) internal returns (Context memory) {
        return set(ctx, key, value.toUint256());
    }

    function set(Context memory ctx, string memory key, address value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, address[] memory value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, string[] memory value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, string memory value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function _nextId() private returns (string memory id) {
        bytes32 slot = keccak256("config-files.storage.counter");

        uint256 count = uint256(vm.load(address(0), slot)) + 1;
        vm.store(address(0), slot, bytes32(count));
        return string(abi.encodePacked(address(0), count));
    }
}

library JsonKeys {
    function root(string memory prefix) internal pure returns (string memory) {
        if (bytes(prefix).length == 0) {
            return "$";
        }
        if (bytes(prefix)[0] == bytes1("$") || bytes(prefix)[0] == bytes1(".")) {
            return prefix;
        }
        return string.concat("$", ".", prefix);
    }

    function key(string memory prefix, string memory _key) internal pure returns (string memory) {
        return string.concat(prefix, ".", _key);
    }

    function index(string memory prefix, string memory _key, uint256 _index) internal pure returns (string memory) {
        return string.concat(prefix, ".", _key, "[", vm.toString(_index), "]");
    }
}
