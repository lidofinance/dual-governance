using DummyStETH as stEth;
using DummyWstETH as wst_eth;

methods {
    function _.getRageQuitSupport() external => DISPATCHER(true);
    function _.isRageQuitFinalized() external => DISPATCHER(true);
    function _.MASTER_COPY() external => DISPATCHER(true);
    function _.startRageQuit(Durations.Duration, Durations.Duration) external => DISPATCHER(true);
    function _.initialize(address) external => DISPATCHER(true);

    //envfree

    function isWithdrawalsBatchesFinalized() external returns (bool) envfree; 

    //calls to stEthn and wst_eth from spec

    function DummyStETH.balanceOf(address) external returns(uint256) envfree;
    function DummyWstETH.balanceOf(address) external returns(uint256) envfree;
    function DummyStETH.getPooledEthByShares(uint256) external returns (uint256) envfree; 

    //calls to resealMaanger are from dualGov and unrelated 
    function _.resume(address sealable) external => NONDET;
    function _.reseal(address[] sealables) external => NONDET;

    //calls to timelosck  are from dualGov and unrelated
    function _.submit(address executor, DualGovernance.ExecutorCall[] calls) external => NONDET;
    function _.schedule(uint256 proposalId) external => NONDET;
    function _.execute(uint256 proposalId) external => NONDET;
    function _.cancelAllNonExecutedProposals() external => NONDET;

    function _.canSchedule(uint256 proposalId) external => NONDET;
    function _.canExecute(uint256 proposalId) external => NONDET;

    function _.getProposalSubmissionTime(uint256 proposalId) external => NONDET;
}

use builtin rule sanity; 



/**
@title Rage Quite is a final state of the contract, i.e can not change the state

**/
rule rageQuiteFinalState(method f) 
{
    Escrow.EscrowState stateBefore = currentContract._escrowState; 

    env e;
    calldataarg args; 
    f(e,args);

    Escrow.EscrowState stateAfter = currentContract._escrowState; 

    assert stateBefore == Escrow.EscrowState.RageQuitEscrow =>
     stateAfter == Escrow.EscrowState.RageQuitEscrow;
 

}

/// @todo rule rageQuitNlockUnlock 


/**
@title once requestNextWithdrawalsBatch results in batchesQueue.close() all additional calls result in close(); 
**/
rule batchesQueueCloseFinalState(method f){

    bool startBatchesQueueStatus =  isWithdrawalsBatchesFinalized();
    
    env eF;
    calldataarg argsF;
    f(eF,argsF);
    
    bool nextBatchesQueueStatus =  isWithdrawalsBatchesFinalized();
    assert startBatchesQueueStatus => nextBatchesQueueStatus;
}

//todo - what else should not change be allowed;
/**
@title when ques are closed, no change in batch list.

checked with mutation on version with issue
https://prover.certora.com/output/40726/dd696d553405430aa40ae244474aa1d0/?anonymousKey=fe11fe659d51d8b9d1c1021a8ec18b9c2e6ab2a9

**/  

rule batchesQueueCloseNochange(method f){

    bool finialize = isWithdrawalsBatchesFinalized();
    uint256 any;
    uint256 before =  currentContract._batchesQueue.batches[any];
    
    env eF;
    calldataarg argsF;
    f(eF,argsF);

    assert finialize => before == currentContract._batchesQueue.batches[any];
}


invariant solvency_steth() 
    stEth.getPooledEthByShares(currentContract._accounting.stETHTotals.lockedShares) <=  stEth.balanceOf(currentContract);


//todo (assuming no transfer)
//    wstEth.balanceOf(currentContract) == 0 ;

rule solvency_wst_eth_test(method f) 
{
    uint256 before = wst_eth.balanceOf(currentContract);  
    env e;
    calldataarg args;
    f(e,args);
    uint256 after = wst_eth.balanceOf(currentContract);  
    assert after == before;
}
//todo - StETHAccounting.claimedETH <=  nativeBalances[currentContract]
// need to prove sum of balance <= self.stETHTotals.lockedShares

rule solvency_eth(method f) 
{
    uint256 before = nativeBalances[currentContract];  
    env e;
    calldataarg args;
    f(e,args);
    uint256 after = nativeBalances[currentContract];  
    assert after == before;
}

rule solvency_st_eth(method f) 
{
    uint256 before = stEth.balanceOf(currentContract); 
    env e;
    calldataarg args;
    f(e,args);
    uint256 after = stEth.balanceOf(currentContract); 
    assert after == before;
}

//todo - count of all unstETHIds <= withdrawalQueue.balanaceOf(currentContract)
