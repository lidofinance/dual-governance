// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ITiebreakerCore {
    function getSealableResumeNonce(address sealable) external view returns (uint256 nonce);
    function scheduleProposal(uint256 _proposalId) external;
    function sealableResume(address sealable, uint256 nonce) external;
}
