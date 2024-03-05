// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IConfiguration {
    function ADMIN_EXECUTOR() external view returns (address);
    function EMERGENCY_GOVERNANCE() external view returns (address);

    function AFTER_SUBMIT_DELAY() external view returns (uint256);
    function AFTER_SCHEDULE_DELAY() external view returns (uint256);

    function RAGE_QUIT_ETH_WITHDRAWAL_TIMELOCK() external view returns (uint256);

    function SIGNALING_COOLDOWN_DURATION() external view returns (uint256);
    function SIGNALLING_DEACTIVATION_DURATION() external view returns (uint256);
    function SIGNALLING_MIN_PROPOSAL_REVIEW_DURATION() external view returns (uint256);

    function SIGNALING_MIN_DURATION() external view returns (uint256);
    function SIGNALING_MAX_DURATION() external view returns (uint256);

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
