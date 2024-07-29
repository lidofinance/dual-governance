// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";

library Timelock {
    error InvalidGovernance(address value);
    error InvalidAdminExecutor(address value);
    error InvalidAfterSubmitDelay(Duration value);

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
        /// @dev slot1 [0..159]
        address adminExecutor;
    }

    function setAdminExecutor(Context storage self, address newAdminExecutor) internal {
        if (self.adminExecutor == address(0)) {
            revert InvalidAdminExecutor(address(0));
        }
        if (self.adminExecutor == newAdminExecutor) {
            return;
        }
        self.adminExecutor = newAdminExecutor;
        emit AdminExecutorSet(newAdminExecutor);
    }

    function setGovernance(Context storage self, address newGovernance) internal {
        if (self.governance == address(0)) {
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

    function setAfterSubmitDelay(Context storage self, Config memory config, Duration newAfterSubmitDelay) internal {
        if (newAfterSubmitDelay < config.minSubmitDelay || newAfterSubmitDelay > config.maxSubmitDelay) {
            revert InvalidAfterSubmitDelay(newAfterSubmitDelay);
        }
        if (self.afterSubmitDelay == newAfterSubmitDelay) {
            return;
        }
        self.afterSubmitDelay = newAfterSubmitDelay;
        emit AfterSubmitDelaySet(newAfterSubmitDelay);
    }

    function setAfterScheduleDelay(
        Context storage self,
        Config memory config,
        Duration newAfterScheduleDelay
    ) internal {
        if (newAfterScheduleDelay < config.minScheduleDelay || newAfterScheduleDelay > config.maxScheduleDelay) {
            revert InvalidAfterSubmitDelay(newAfterScheduleDelay);
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

    function checkAdminExecutor(Context storage self, address account) internal view {
        if (self.adminExecutor != account) {
            revert InvalidAdminExecutor(account);
        }
    }
}
