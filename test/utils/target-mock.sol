// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// May be used as a mock contract to collect method calls
contract TargetMock {
    struct Call {
        uint256 value;
        address sender;
        uint256 blockNumber;
        bytes data;
    }

    Call[] public calls;

    function getCallsLength() external view returns (uint256) {
        return calls.length;
    }

    function getCalls() external view returns (Call[] memory calls_) {
        calls_ = calls;
    }

    function reset() external {
        for (uint256 i = 0; i < calls.length; ++i) {
            calls.pop();
        }
    }

    fallback() external payable {
        calls.push(Call({value: msg.value, sender: msg.sender, blockNumber: block.number, data: msg.data}));
    }

    receive() external payable {}
}
