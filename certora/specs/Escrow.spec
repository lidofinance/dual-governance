using DummyStETH as stEth;
using DummyWstETH as wst_eth;
using Escrow as escrow;
using DualGovernance as dualGovernance;
using ImmutableDualGovernanceConfigProvider as config;
using DummyWithdrawalQueue as withdrawalQueue;

methods {
    // calls to Escrow from dualGovernance 
    function _.getRageQuitSupport() external => DISPATCHER(true);
    function _.isRageQuitFinalized() external => DISPATCHER(true);
    function _.startRageQuit(Durations.Duration, Durations.Duration) external => DISPATCHER(true);
    function _.initialize(Durations.Duration) external => DISPATCHER(true);
    function _.setMinAssetsLockDuration(Durations.Duration newMinAssetsLockDuration) external => DISPATCHER(true);

    //envfree
    function isWithdrawalsBatchesClosed() external returns (bool) envfree; 
    function getRageQuitSupport() external  returns (Escrow.PercentD16)  envfree;
    function withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT() external returns (uint) envfree;
    function getRageQuitEscrowDetails() external returns (IRageQuitEscrow.RageQuitEscrowDetails memory) envfree;

    
    //calls to stEth and wst_eth from spec
    function DummyStETH.getTotalShares() external returns(uint256) envfree;
    function DummyStETH.totalSupply() external returns(uint256) envfree;
    function DummyStETH.balanceOf(address) external returns(uint256) envfree;
    function DummyWstETH.balanceOf(address) external returns(uint256) envfree;
    function DummyStETH.getPooledEthByShares(uint256) external returns (uint256) envfree; 
    function DummyWithdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT() external returns (uint256) envfree;

    //calls to resealManager are from dualGov are unrelated 
    function _.resume(address sealable) external => NONDET;
    function _.reseal(address sealable) external => NONDET;
    function _.reseal(address[] sealables) external => NONDET;

    //calls to timelock  are from dualGov are unrelated
    function _.submit(address executor, DualGovernance.ExternalCall[] calls) external => NONDET;

    function _.schedule(uint256 proposalId) external => NONDET;
    function _.execute(uint256 proposalId) external => NONDET;
    function _.cancelAllNonExecutedProposals() external => NONDET;

    function _.canSchedule(uint256 proposalId) external => NONDET;
    function _.canExecute(uint256 proposalId) external => NONDET;

    function _.getProposalSubmissionTime(uint256 proposalId) external => NONDET;

}

/**
Helper functions 
**/

function isNotInitializedState() returns bool {
    return require_uint8(currentContract._escrowState.state) ==  0 /*EscrowState.State.NotInitialized*/;
}

function isSignallingState() returns bool {
    return require_uint8(currentContract._escrowState.state) ==1 /*EscrowState.State.SignallingEscrow*/;
}

function isRageQuitState() returns bool {
    return require_uint8(currentContract._escrowState.state) ==  2 /*EscrowState.State.RageQuitEscrow*/;
}

function isBatchQueueStateAbset() returns bool {
    return require_uint8(currentContract._batchesQueue.info. state) ==  0; 
}

function isBatchQueueStateOpened() returns bool {
    return require_uint8(currentContract._batchesQueue.info. state) ==  1; 
}

function isBatchQueueStateClosed() returns bool {
    return require_uint8(currentContract._batchesQueue.info. state) ==  2; 
}

function isAllStEthNFTClaimed() returns bool {
    return currentContract._batchesQueue.info.totalUnstETHIdsClaimed == currentContract._batchesQueue.info.totalUnstETHIdsCount ;
}

// The real WithdrawalsBatchesClosed function will revert if 
// the escrow is not in the RageQuitState. Because function calls
// in our specifications without withRevert implicitly assume the functions
// take the non-reverting path, we need to instead use a function that
// returns whether the batch queue is closed and in the ragequit state
// rather than reverting outside of ragequit.
function isWithdrawalsBatchesClosedNonReverting() returns bool {
    return isRageQuitState() && isBatchQueueStateClosed();
}

/**
@title If the state of an escrow is RageQuitEscrow, we can execute any method and it will still be in the same state afterwards
**/ 
// Run link: https://prover.certora.com/output/65266/7970f0eac1234bc2a203a40d04c40954/?anonymousKey=33b62d0e4dd04f71af9d93950db67f7a8848c905
// Status: PASSING
rule E_State_1_rageQuitFinalState(method f) 
{
    bool rageQuitStateBefore = isRageQuitState();

    env e;
    calldataarg args; 
    f(e,args);

    bool rageQuitStateAfter = isRageQuitState();

    assert rageQuitStateBefore => rageQuitStateAfter ;

}

/**
@title only dual governance can start a rage quit
**/ 
// Run link: https://prover.certora.com/output/65266/5082969d13ba4bcdb557ece42b8601a6/?anonymousKey=0301f848b71cf42e4d79ac2c4cd1ddd0d74e3be3
// Status: PASSING
rule E_KP_5_rageQuitStarter(method f) 
{
    bool rageQuitStateBefore = isRageQuitState();

    env e;
    calldataarg args; 
    f(e,args);

    bool rageQuitStateAfter = isRageQuitState();

    assert !rageQuitStateBefore && rageQuitStateAfter => 
        e.msg.sender == dualGovernance;

}

/** @title It's not possible to lock funds in or unlock funds from an escrow that is already in the rage quit state.
locking/unlocking implies changing the stETHLockedShares or unstETHLockedShares of an account.
WithdrawEth (after rage quit) is the other option to change account's asset entry.
**/
// Run link: https://prover.certora.com/output/65266/7808167b9baf4ea3bda80e045af6e1b8/?anonymousKey=2d44d34af79ff992c9d66bd72f84154b02429385'
// Status: PASSING
rule E_KP_3_rageQuitNolockUnlock(method f, address holder) 
{
    bool rageQuitStateBefore = isRageQuitState();

    uint256 beforeStShares = currentContract._accounting.assets[holder].stETHLockedShares;
    uint256 beforeUnStShares = currentContract._accounting.assets[holder].unstETHLockedShares;

    env e;
    calldataarg args;
    f(e,args);

    assert rageQuitStateBefore => 
        (beforeStShares == currentContract._accounting.assets[holder].stETHLockedShares &&
        beforeUnStShares == currentContract._accounting.assets[holder].unstETHLockedShares ) ||
        f.selector == sig:withdrawETH().selector;
}

/** 
@title Before rage quit An agent cannot unlock their funds until SignallingEscrowMinLockTime has passed since this user last locked funds.
funds can move between stEthLocked and unstETHLockedShares
**/
// Run link: https://prover.certora.com/output/65266/4e22bd925ead45b08cd1847d943d71e4/?anonymousKey=b2c611027b519656f2de13e39cf074289ad48faa
// Status: PASSING
rule E_KP_4_unlockMinTime(method f, address holder) 
{
    bool rageQuitStateBefore = isRageQuitState();

    uint256 beforeStShares = currentContract._accounting.assets[holder].stETHLockedShares;
    uint256 beforeUnStShares = currentContract._accounting.assets[holder].unstETHLockedShares;
    uint256 lastTimestamp = currentContract._accounting.assets[holder].lastAssetsLockTimestamp;

    env e;
    calldataarg args;
    f(e,args);

    uint256 min_time = currentContract._escrowState.minAssetsLockDuration; 

    assert (!rageQuitStateBefore && e.block.timestamp < lastTimestamp + min_time) 
        => 
        beforeStShares + beforeUnStShares <= currentContract._accounting.assets[holder].stETHLockedShares + currentContract._accounting.assets[holder].unstETHLockedShares;
}

/**
@title once requestNextWithdrawalsBatch results in batchesQueue.close() all additional calls result in close(); 
**/
// Run link: https://prover.certora.com/output/65266/25bf0ade61664d4a8d30efc59a2342ba/?anonymousKey=fb8d5f1f7ba6d2231e07d6b90d280310c168f2d6
// Status: PASSING
rule W2_2_batchesQueueCloseFinalState(method f){

    bool startBatchesQueueStatus =  isWithdrawalsBatchesClosedNonReverting();
    
    env eF;
    calldataarg argsF;
    f(eF,argsF);
    
    bool nextBatchesQueueStatus =  isWithdrawalsBatchesClosedNonReverting();
    assert startBatchesQueueStatus => nextBatchesQueueStatus;
}



/**
@title W2-2 DOS when queues are closed, no change in batch list.

checked with mutation on version with issue
https://prover.certora.com/output/40726/dd696d553405430aa40ae244474aa1d0/?anonymousKey=fe11fe659d51d8b9d1c1021a8ec18b9c2e6ab2a9


**/  
// Run link: https://prover.certora.com/output/65266/7f20c1aca8844873922a0104e3fdb727/?anonymousKey=9bcb9b388336519d00bf50eefdd3fd26ef3a031f
// Status: PASSING 
rule W2_2_batchesQueueCloseNoChange(method f){

    bool finalize = isWithdrawalsBatchesClosedNonReverting();
    uint256 any;
    uint256 beforeFirst =  currentContract._batchesQueue.batches[any].firstUnstETHId;
    uint256 beforeSecond =  currentContract._batchesQueue.batches[any].lastUnstETHId;
    env eF;
    calldataarg argsF;
    f(eF,argsF);

    assert finalize =>     
        beforeFirst == currentContract._batchesQueue.batches[any].firstUnstETHId &&
        beforeSecond ==  currentContract._batchesQueue.batches[any].lastUnstETHId;
}

/**
    @title Rage quit support value
    The rage quit support of an escrow is equal to: 
                (S+W+U+F) / (T+F)
    where:
        S - is the ETH amount locked in the escrow in the form of stET 
        W - is the ETH amount locked in the escrow in the form of wstETH: _accounting.stETHTotals.lockedShares
        U - is the ETH amount locked in the escrow in the form of unfinalized Withdrawal NFTs: _accounting.unstETHTotals.unfinalizedShares (sum of all nft deposited)
        F - is the ETH amount locked in the escrow in the form of finalized Withdrawal NFTs: _accounting.unstETHTotals.unstETHFinalizedETH (out of unstETHUnfinalizedShares )
        T - is the total supply of stETH.
 **/ 

// Run link: https://prover.certora.com/output/65266/85b1e462456f40bdb010551464ae6803/?anonymousKey=a9d72d7e77dcb6cfad084562496d5bd950229b50
// Status: PASSING
 rule E_KP_1_rageQuitSupportValue() {
    // this mostly checks for overflow/underflow 
    mathint actual = getRageQuitSupport();
    uint256 S_W = currentContract._accounting.stETHTotals.lockedShares;
    uint256 U = currentContract._accounting.unstETHTotals.unfinalizedShares;
    mathint F = currentContract._accounting.unstETHTotals.finalizedETH; 
    mathint T = stEth.totalSupply(); 
    mathint expected =  
        ((100 * 10 ^ 16) *(stEth.getPooledEthByShares( assert_uint256(S_W + U) ) + F) )
        / ( T  +  F );
    assert  actual == expected;
 }





/** @title state transition of an unsteth record 
enum UnstETHRecordStatus {
    NotLocked = 0
    Locked = 1
    Finalized = 2
    Claimed = 3
    Withdrawn =  4
}
Valid transitions are: 
0 -> 1 
1 -> 0
1 -> 2
1 -> 3
2 -> 3
2 -> 0
3 -> 4 
4 final state 
**/ 

rule stateTransition_unstethRecord(uint256 unstETHId, method f) {
    uint8 before = require_uint8(currentContract._accounting.unstETHRecords[unstETHId].status);
    require before == 3 => isRageQuitState();
    env e;
    calldataarg args;
    f(e,args);

    uint8 after = require_uint8(currentContract._accounting.unstETHRecords[unstETHId].status);
    assert before != after =>
        (  ( before == 0 <=> after == 1)
        && ( before == 1 => after <= 3)
        && ( before == 2 => ( after == 0 || after == 3) )
        && ( before == 3 <=>  after == 4 )
        && ( after == 2 => before == 1 )
        && ( after == 3 => (before == 1  || before == 2) )
        );
    assert after == 3 => isRageQuitState();

}


