// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ITiebreakerCoreCommittee {
    function getSealableResumeNonce(address sealable) external view returns (uint256 nonce);
    function scheduleProposal(uint256 proposalId) external;
    function sealableResume(address sealable, uint256 nonce) external;
    function checkProposalExists(uint256 proposalId) external view;
    function checkSealableIsPaused(address sealable) external view;
}
