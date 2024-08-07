// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";

library TimelockState {
    error InvalidGovernance(address value);
    error InvalidAfterSubmitDelay(Duration value);
    error InvalidAfterScheduleDelay(Duration value);

    event GovernanceSet(address newGovernance);
    event AdminExecutorSet(address newAdminExecutor);
    event AfterSubmitDelaySet(Duration newAfterSubmitDelay);
    event AfterScheduleDelaySet(Duration newAfterScheduleDelay);

    struct Config {
        Duration maxSubmitDelay;
        Duration minSubmitDelay;
        Duration minScheduleDelay;
        Duration maxScheduleDelay;
    }

    struct Context {
        /// @dev slot0 [0..159]
        address governance;
        /// @dev slot0 [160..191]
        Duration afterSubmitDelay;
        /// @dev slot0 [192..224]
        Duration afterScheduleDelay;
    }

    function setGovernance(Context storage self, address newGovernance) internal {
        if (newGovernance == address(0)) {
            revert InvalidGovernance(newGovernance);
        }
        if (self.governance == newGovernance) {
            return;
        }
        self.governance = newGovernance;
        emit GovernanceSet(newGovernance);
    }

    function getAfterSubmitDelay(Context storage self) internal view returns (Duration) {
        return self.afterSubmitDelay;
    }

    function getAfterScheduleDelay(Context storage self) internal view returns (Duration) {
        return self.afterScheduleDelay;
    }

    function setAfterSubmitDelay(
        Context storage self,
        Duration newAfterSubmitDelay,
        Duration maxAfterSubmitDelay
    ) internal {
        if (newAfterSubmitDelay > maxAfterSubmitDelay) {
            revert InvalidAfterScheduleDelay(newAfterSubmitDelay);
        }
        if (self.afterSubmitDelay == newAfterSubmitDelay) {
            return;
        }
        self.afterSubmitDelay = newAfterSubmitDelay;
        emit AfterSubmitDelaySet(newAfterSubmitDelay);
    }

    function setAfterScheduleDelay(
        Context storage self,
        Duration newAfterScheduleDelay,
        Duration maxAfterScheduleDelay
    ) internal {
        if (newAfterScheduleDelay > maxAfterScheduleDelay) {
            revert InvalidAfterScheduleDelay(newAfterScheduleDelay);
        }
        if (self.afterScheduleDelay == newAfterScheduleDelay) {
            return;
        }
        self.afterScheduleDelay = newAfterScheduleDelay;
        emit AfterScheduleDelaySet(newAfterScheduleDelay);
    }

    function checkGovernance(Context storage self, address account) internal view {
        if (self.governance != account) {
            revert InvalidGovernance(account);
        }
    }
}
