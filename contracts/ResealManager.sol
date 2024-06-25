// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISealable} from "./interfaces/ISealable.sol";

contract ResealExecutor is Ownable {
    error SealableWrongPauseState();
    error SenderIsNotManager();

    event ManagerSet(address newManager);

    uint256 public constant PAUSE_INFINITELY = type(uint256).max;

    address public manager;

    constructor(address owner, address managerAddress) Ownable(owner) {
        manager = managerAddress;

        emit ManagerSet(managerAddress);
    }

    function reseal(address[] memory sealables) public onlyManager {
        for (uint256 i = 0; i < sealables.length; ++i) {
            uint256 sealableResumeSinceTimestamp = ISealable(sealables[i]).getResumeSinceTimestamp();
            if (sealableResumeSinceTimestamp < block.timestamp || sealableResumeSinceTimestamp == PAUSE_INFINITELY) {
                revert SealableWrongPauseState();
            }
            Address.functionCall(sealables[i], abi.encodeWithSelector(ISealable.resume.selector));
            Address.functionCall(sealables[i], abi.encodeWithSelector(ISealable.pauseFor.selector, PAUSE_INFINITELY));
        }
    }

    function resume(address sealable) public onlyManager {
        uint256 sealableResumeSinceTimestamp = ISealable(sealable).getResumeSinceTimestamp();
        if (sealableResumeSinceTimestamp < block.timestamp) {
            revert SealableWrongPauseState();
        }
        Address.functionCall(sealable, abi.encodeWithSelector(ISealable.resume.selector));
    }

    function setManager(address newManager) public onlyOwner {
        manager = newManager;
        emit ManagerSet(newManager);
    }

    modifier onlyManager() {
        if (msg.sender != manager) {
            revert SenderIsNotManager();
        }
        _;
    }
}
