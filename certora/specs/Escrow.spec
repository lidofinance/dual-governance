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
    function isWithdrawalsBatchesFinalized() external returns (bool) envfree; 
    function getRageQuitSupport() external  returns (Escrow.PercentD16)  envfree;
    function withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT() external returns (uint) envfree;
    
    //calls to stEth and wst_eth from spec
    function DummyStETH.getTotalShares() external returns(uint256) envfree;
    function DummyStETH.totalSupply() external returns(uint256) envfree;
    function DummyStETH.balanceOf(address) external returns(uint256) envfree;
    function DummyWstETH.balanceOf(address) external returns(uint256) envfree;
    function DummyStETH.getPooledEthByShares(uint256) external returns (uint256) envfree; 

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

use builtin rule sanity; 


/**
@title Ragequit is a final state of the contract, i.e can not change the state

**/
function isRageQuitState() returns bool {
    return require_uint8(currentContract._escrowState.state) ==  2 /*EscrowState.State.RageQuitEscrow*/;
}
/**
@title If the state of an escrow is RageQuitEscrow, we can execute any method and it will still be in the same state afterwards
**/ 
rule E_State_1_rageQuitFinalState(method f) 
{
    bool rageQuitStateBefore = isRageQuitState();

    env e;
    calldataarg args; 
    f(e,args);

    bool rageQuitStateAfter = isRageQuitState();

    assert rageQuitStateBefore => rageQuitStateAfter ;

}

rule E_KP_5_rageQuitStarter(method f) 
{
    bool rageQuitStateBefore = isRageQuitState();

    env e;
    calldataarg args; 
    f(e,args);

    bool rageQuitStateAfter = isRageQuitState();

    assert !rageQuitStateBefore && rageQuitStateAfter => 
        e.msg.sender == dualGovernance;
    // && 
    // enought support &&  time=> rageQuitStarted

}

/** @title It's not possible to lock funds in or unlock funds from an escrow that is already in the rage quit state.
locking/unlocking implies chaning the stETHLockedShares or unstETHLockedShares of an account

this can happen only on withdrawEth
**/

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
@title An agent cannot unlock their funds until SignallingEscrowMinLockTime has passed since this user last locked funds.
**/
//TODO - there is a violation : https://prover.certora.com/output/40726/de13f7a8cc0a43ea9d0a2626098cb465/?anonymousKey=cd50592304ac7f689618e4afa778f954271896cd
// need to acknowledge  it is ok 
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
        beforeStShares <= currentContract._accounting.assets[holder].stETHLockedShares &&
        beforeUnStShares <= currentContract._accounting.assets[holder].unstETHLockedShares;
}

/**
@title once requestNextWithdrawalsBatch results in batchesQueue.close() all additional calls result in close(); 
**/
rule W2_2_batchesQueueCloseFinalState(method f){

    bool startBatchesQueueStatus =  isWithdrawalsBatchesFinalized();
    
    env eF;
    calldataarg argsF;
    f(eF,argsF);
    
    bool nextBatchesQueueStatus =  isWithdrawalsBatchesFinalized();
    assert startBatchesQueueStatus => nextBatchesQueueStatus;
}



/**
@title W2-2 DOS when queues are closed, no change in batch list.

checked with mutation on version with issue
https://prover.certora.com/output/40726/dd696d553405430aa40ae244474aa1d0/?anonymousKey=fe11fe659d51d8b9d1c1021a8ec18b9c2e6ab2a9


**/  

rule W2_2_batchesQueueCloseNoChange(method f){

    bool finalize = isWithdrawalsBatchesFinalized();
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
@title W2-2 In a situation where requestNextWithdrawalsBatch should close the queue, 
    there is no way to prevent it from being closed by first calling another function.
@notice We are filtering out some functions that are not interesting since they cannot 
    successfully be called in a situation where requestNextWithdrawalsBatch makes sense to call.
*/
rule W2_2_front_running(method f) {
    storage initial_storage = lastStorage;

    // set up one run in which requestNextWithdrawalsBatch closes the queue
    require !isWithdrawalsBatchesFinalized();
    env e;
    uint batchsize;
    requestNextWithdrawalsBatch(e, batchsize);
    require isWithdrawalsBatchesFinalized();

    // if we frontrun something else, at the end it should still be closed
    calldataarg args;
    f@withrevert(e, args) at initial_storage;
    bool fReverted = lastReverted;
    requestNextWithdrawalsBatch(e, batchsize);
    uint stETHRemaining = stEth.balanceOf(currentContract);
    uint minStETHWithdrawalRequestAmount = withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT();
    assert fReverted || stETHRemaining < minStETHWithdrawalRequestAmount => isWithdrawalsBatchesFinalized();
}

/**
W1-1 Evading Ragequit second seal:

@title when is ragequit the ragequit support is at least SECOND_SEAL_RAGE_QUIT_SUPPORT 

**/

invariant W1_1_rageQuitSupportMinValue()
    isRageQuitState() => getRageQuitSupport() <= config.SECOND_SEAL_RAGE_QUIT_SUPPORT
    // startRageQuit is only called from DualGoverance (rule ragequitStarter)
    // and those functions are checked through dual governance 
    filtered { f-> f.selector !=  sig:startRageQuit(Durations.Duration, Durations.Duration).selector}


/**
    @title Reage quit support value

ignoring imprecisions due to fixed-point arithmetic, the rage quit support of an escrow is equal to 
(S+W+U+F) / (T+F)
 where
S - is the ETH amount locked in the escrow in the form of stET + 
W - is the ETH amount locked in the escrow in the form of wstETH: _accounting.stETHTotals.lockedShares
U - is the ETH amount locked in the escrow in the form of unfinalized Withdrawal NFTs: _accounting.unstETHTotals.unfinalizedShares (sum of all nft deposited)
F - is the ETH amount locked in the escrow in the form of finalized Withdrawal NFTs: _accounting.unstETHTotals.unstETHFinalizedETH (out of unstETHUnfinalizedShares )
T - is the total supply of stETH.
 **/ 


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

/************* Solvency  Rules **********/
/************* E-KP-2 : total holding of each token ***********/
/** 
@title total holding of wst_eth is zero as all wst_eth are converted to st_eth
**/  
invariant zeroWstEthBalance() 
    wst_eth.balanceOf(currentContract) == 0
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
    }
}

ghost mathint sumStETHLockedShares{
    // assuming value zero at the initial state before constructor 
	init_state axiom sumStETHLockedShares == 0; 
}

/* updated sumStETHLockedShares according to the change of a single account */
hook Sstore currentContract._accounting.assets[KEY address a].stETHLockedShares Escrow.SharesValue new_balance
// the old value that balances[a] holds before the store
    (Escrow.SharesValue old_balance) {
  sumStETHLockedShares = sumStETHLockedShares + new_balance - old_balance;
}

hook Sload Escrow.SharesValue value currentContract._accounting.assets[KEY address a].stETHLockedShares {
    require  value <= sumStETHLockedShares;
}

invariant totalLockedShares()
    sumStETHLockedShares <= currentContract._accounting.stETHTotals.lockedShares;

 /** @title total holding of stEth before rageQuit start 
 **/ 
invariant solvency_stETH_before_ragequit() 
    !isRageQuitState() => stEth.getPooledEthByShares(currentContract._accounting.stETHTotals.lockedShares
    ) <=  stEth.balanceOf(currentContract) 

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
    }
}

//////  Nurit : From here work in progress 
/*
invariant solvency_stETH_before_ragequit() 
    !isRageQuitState() => 
        currentContract._accounting.unstETHTotals.unfinalizedShares 

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
    }
}
*/


invariant solvency_claimedETH() 
    isRageQuitState() =>  currentContract._accounting.stETHTotals.claimedETH * sumStETHLockedShares /*/ currentContract._accounting.stETHTotals.lockedShares*/ <=  nativeBalances[currentContract] * currentContract._accounting.stETHTotals.lockedShares

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
    }
}




//todo - StETHAccounting.claimedETH <=  nativeBalances[currentContract]
// need to prove sum of balance <= self.stETHTotals.lockedShares
/*
rule change_eth(method f) 
{
    uint256 before = nativeBalances[currentContract];  
    env e;
    calldataarg args;
    f(e,args);
    uint256 after = nativeBalances[currentContract];  
    assert after == before;
}

rule change_st_eth(method f) 
{
    uint256 before = stEth.balanceOf(currentContract); 
    env e;
    calldataarg args;
    f(e,args);
    uint256 after = stEth.balanceOf(currentContract); 
    assert after == before;
}
*/
//todo - count of all unstETHIds <= withdrawalQueue.balanaceOf(currentContract)

