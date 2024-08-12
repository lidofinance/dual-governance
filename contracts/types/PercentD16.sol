// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

type PercentD16 is uint256;

uint256 constant HUNDRED_PERCENTS_UINT256 = 100 * 10 ** 16;

error Overflow();

using {lt as <, lte as <=, gte as >=, gt as >, minus as -, plus as +} for PercentD16 global;

function lt(PercentD16 a, PercentD16 b) pure returns (bool) {
    return PercentD16.unwrap(a) < PercentD16.unwrap(b);
}

function lte(PercentD16 a, PercentD16 b) pure returns (bool) {
    return PercentD16.unwrap(a) <= PercentD16.unwrap(b);
}

function gt(PercentD16 a, PercentD16 b) pure returns (bool) {
    return PercentD16.unwrap(a) > PercentD16.unwrap(b);
}

function gte(PercentD16 a, PercentD16 b) pure returns (bool) {
    return PercentD16.unwrap(a) >= PercentD16.unwrap(b);
}

function minus(PercentD16 a, PercentD16 b) pure returns (PercentD16) {
    if (b > a) {
        revert Overflow();
    }
    return PercentD16.wrap(PercentD16.unwrap(a) - PercentD16.unwrap(b));
}

function plus(PercentD16 a, PercentD16 b) pure returns (PercentD16) {
    return PercentD16.wrap(PercentD16.unwrap(a) + PercentD16.unwrap(b));
}

library PercentsD16 {
    function fromBasisPoints(uint256 bpValue) internal pure returns (PercentD16) {
        return PercentD16.wrap(HUNDRED_PERCENTS_UINT256 * bpValue / 100_00);
    }

    function fromFraction(uint256 numerator, uint256 denominator) internal pure returns (PercentD16) {
        return PercentD16.wrap(HUNDRED_PERCENTS_UINT256 * numerator / denominator);
    }
}
