// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";


using EnumerableSet for EnumerableSet.UintSet;

error TimelockNotExpired();
error CallCancelled();
error CallIdNotCancelled(uint256 id);
error TargetCannotBeZero();
error IdNotFound();


library TimelockCallSet {
    using SafeCast for uint256;

    struct Call {
        uint64 scheduledAt;
        uint64 lockedTill;
        address target;
        bytes data;
    }

    struct Set {
        uint256 _maxId;
        uint256 _cancelledTill;
        mapping(uint256 id => Call) _calls;
        EnumerableSet.UintSet _ids;
    }

    function get(Set storage self, uint256 id) internal view returns (Call storage) {
        Call storage call = self._calls[id];
        if (call.target == address(0)) {
            revert IdNotFound();
        }
        return call;
    }

    function add(
        Set storage self,
        uint256 scheduledAt,
        uint256 lockedTill,
        address target,
        bytes calldata data
    ) internal returns (uint256) {
        if (target == address(0)) {
            revert TargetCannotBeZero();
        }
        uint256 callId = ++self._maxId;
        self._calls[callId] = Call(scheduledAt.toUint64(), lockedTill.toUint64(), target, data);
        assert(self._ids.add(callId));
        return callId;
    }

    function removeForExecution(Set storage self, uint256 callId, uint256 timestamp) internal returns (Call memory) {
        Call memory call = get(self, callId);
        if (call.scheduledAt <= self._cancelledTill) {
            revert CallCancelled();
        }
        if (call.lockedTill >= timestamp) {
            revert TimelockNotExpired();
        }
        _remove(self, callId);
        return call;
    }

    function _remove(Set storage self, uint256 callId) internal {
        delete self._calls[callId];
        assert(self._ids.remove(callId));
    }

    function cancelCallsTill(Set storage self, uint256 timestamp) internal {
        require(timestamp >= self._cancelledTill);
        self._cancelledTill = timestamp;
    }

    function getIds(Set storage self) internal view returns (uint256[] memory) {
        return self._ids.values();
    }

    function getExecutableIds(Set storage self, uint256 timestamp) internal view returns (uint256[] memory) {
        uint256[] memory ids = self._ids.values();
        uint256[] memory execIds = new uint256[](ids.length);
        uint256 iExecCall = 0;

        for (uint256 iCall = 0; iCall < ids.length; ++iCall) {
            uint256 callId = ids[iCall];
            Call storage _op = self._calls[callId];
            if (timestamp > _op.lockedTill && _op.scheduledAt > self._cancelledTill) {
                execIds[iExecCall++] = callId;
            }
        }

        if (iExecCall < ids.length) {
            // trim the memory array
            assembly ("memory-safe") {
                mstore(execIds, iExecCall)
            }
        }

        return execIds;
    }

    function removeCancelledCalls(Set storage self, uint256[] calldata ids) internal {
        uint256 cancelledTill = self._cancelledTill;

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            Call storage _call = get(self, id);
            if (_call.scheduledAt > cancelledTill) {
                revert CallIdNotCancelled(id);
            }
            _remove(self, id);
        }
    }
}
