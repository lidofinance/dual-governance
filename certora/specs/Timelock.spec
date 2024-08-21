using Configuration as CONFIG;

methods {
    function CONFIG.AFTER_SUBMIT_DELAY() external returns (Durations.Duration) envfree;
    function getProposalSubmissionTime(uint256) external returns (Timestamps.Timestamp) envfree;
}

rule EPT_KP_1 {
    env e;
    uint proposalId;

    schedule(e, proposalId);

    assert getProposalSubmissionTime(proposalId) + CONFIG.AFTER_SUBMIT_DELAY() <= e.block.timestamp;
}

rule EPT_2a {
    env e;
    uint proposalId;

    schedule(e, proposalId);

    assert e.msg.sender == currentContract._governance;
}

rule EPT_2b {
    env e;
    calldataarg args;
    submit(e, args);

    assert e.msg.sender == currentContract._governance;
}