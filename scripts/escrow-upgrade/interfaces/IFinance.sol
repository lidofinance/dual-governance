// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IFinance {
    function newImmediatePayment(
        address _token,
        address _receiver,
        uint256 _amount,
        string memory _reference
    ) external;
}
