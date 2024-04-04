// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

error InvalidPercentsString(string value);

struct Percents {
    uint256 value;
    uint256 precision;
}

uint256 constant PRECISION = 16;

function percents(string memory value) pure returns (Percents memory result) {
    result = percents(value, PRECISION);
}

function percents(string memory value, uint256 precision) pure returns (Percents memory result) {
    uint256 integerPart;
    uint256 fractionalPart;
    uint256 fractionalPartLength;

    bytes memory bvalue = bytes(value);
    uint256 length = bytes(value).length;
    bytes1 dot = bytes1(".");

    bool isFractionalPart = false;
    for (uint256 i = 0; i < length; ++i) {
        if (bytes1(bvalue[i]) == dot) {
            if (isFractionalPart) {
                revert InvalidPercentsString(value);
            }
            isFractionalPart = true;
        } else if (uint8(bvalue[i]) >= 48 && uint8(bvalue[i]) <= 57) {
            if (isFractionalPart) {
                fractionalPartLength += 1;
                fractionalPart = 10 * fractionalPart + (uint8(bvalue[i]) - 48);
            } else {
                integerPart = 10 * integerPart + (uint8(bvalue[i]) - 48);
            }
        } else {
            revert InvalidPercentsString(value);
        }
    }
    result.precision = precision;
    result.value = 10 ** precision * integerPart + 10 ** (precision - fractionalPartLength) * fractionalPart;
}
