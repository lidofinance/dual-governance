// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

function computeAddress(address deployer, uint256 nonce) returns (address) {
    bytes memory data;

    if (nonce == 0x00) {
        data = abi.encodePacked(hex"94", deployer, hex"80");
    } else if (nonce <= 0x7f) {
        data = abi.encodePacked(hex"d6", hex"94", deployer, uint8(nonce));
    } else if (nonce <= 0xff) {
        data = abi.encodePacked(hex"d7", hex"94", deployer, hex"81", uint8(nonce));
    } else if (nonce <= 0xffff) {
        data = abi.encodePacked(hex"d8", hex"94", deployer, hex"82", uint16(nonce));
    } else if (nonce <= 0xffffff) {
        data = abi.encodePacked(hex"d9", hex"94", deployer, hex"83", uint24(nonce));
    } else {
        data = abi.encodePacked(hex"da", hex"94", deployer, hex"84", uint32(nonce));
    }

    return address(uint160(uint256(keccak256(data))));
}
