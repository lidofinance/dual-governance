// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IAdminExecutorConfiguration {
    function ADMIN_EXECUTOR() external view returns (address);
}

interface ITimelockConfiguration {
    function AFTER_SUBMIT_DELAY() external view returns (uint256);
    function AFTER_SCHEDULE_DELAY() external view returns (uint256);
    function EMERGENCY_GOVERNANCE() external view returns (address);
}

interface IDualGovernanceConfiguration {
    function RAGE_QUIT_ETH_WITHDRAWAL_TIMELOCK() external view returns (uint256);

    function SIGNALLING_COOLDOWN_DURATION() external view returns (uint256);
    function SIGNALLING_DEACTIVATION_DURATION() external view returns (uint256);
    function SIGNALLING_MIN_PROPOSAL_REVIEW_DURATION() external view returns (uint256);

    function SIGNALLING_MIN_DURATION() external view returns (uint256);
    function SIGNALLING_MAX_DURATION() external view returns (uint256);

    function FIRST_SEAL_THRESHOLD() external view returns (uint256);
    function SECOND_SEAL_THRESHOLD() external view returns (uint256);

    function TIE_BREAK_ACTIVATION_TIMEOUT() external view returns (uint256);

    function sealableWithdrawalBlockers() external view returns (address[] memory);

    function getSignallingThresholdData()
        external
        view
        returns (
            uint256 firstSealThreshold,
            uint256 secondSealThreshold,
            uint256 signallingMinDuration,
            uint256 signallingMaxDuration
        );
}

interface IConfiguration is IAdminExecutorConfiguration, ITimelockConfiguration, IDualGovernanceConfiguration {}
