// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IRolesValidator {
    function validateVotingLaunchPhase() external;
    function validateDGProposalLaunchPhase() external;
}
