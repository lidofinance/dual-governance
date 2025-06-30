
import "./Escrow_validState.spec";
/**
    Verification of asset holding

**/

// Run link, most rules and methods: https://prover.certora.com/output/37629/54b41dd82a20403f8a905032f2e9137b/?anonymousKey=b8cd279c9e3c0ea09b0fd8bbbee1071d07203c84
// Run links for each signature of claimNextWithdrawalsBatch
// https://prover.certora.com/output/65266/646573ffd76a4f1db77b4d68a9b0b981/?anonymousKey=0efe6540924e1f21f25451ae30ac1db12e386470
// https://prover.certora.com/output/65266/9e561aa9c9b74c95bb3f2a5cd35e8de4/?anonymousKey=0f98d90288fa85cf681b9eea9cd59d31632d7289
// Status, all rules PASSING
// NOTE: in the firt run link, two of the methods
// timeout, but passing separate runs of these are also given.

/** 
@title Total holding of wst_eth is zero as all wst_eth are converted to st_eth
**/  
invariant solvency_zeroWstEthBalance() 
    wst_eth.balanceOf(currentContract) == 0
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
    }
}

 /** @title Total holding of stEth before rageQuit start 
 **/ 
invariant solvency_stETH_before_rageQuit() 
    !isRageQuitState() => stEth.getPooledEthByShares(currentContract._accounting.stETHTotals.lockedShares
    ) <=  stEth.balanceOf(currentContract) 

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
    }
}


/** @title Before rage quit eth value of escrow can not be reduced  
**/
rule solvency_ETH_before_rageQuit(method f) 
{
    bool rageQuitStateBefore = isRageQuitState();
    uint256 before = nativeBalances[currentContract]; 
    env e;
    calldataarg args;
    // Escrow is the starting point, it can never call directly an arbitrary function
    require (e.msg.sender != currentContract);  
    f(e,args);
    uint256 after = nativeBalances[currentContract]; 
    assert !rageQuitStateBefore => after >= before;
}


/** @title Total holding of eth by the escrow:
    1. For the locked shares:
        claimedETH * sumStETHLockedShares / stETHTotals.lockedShares 

        where sumStETHLockedShares is the current holding of shares 
    2. For the unstEth holding:
            sumClaimedUnSTEth - sumWithdrawnUnSTEth
        where:
            sumClaimedUnSTEth - total amount of all claimed unstEth 
            sumWithdrawnUnSTEth - total amount already withdrawn 

**/
invariant solvency_ETH() 
    // pool of batch queue
    // if lockedShares is zero than this pool is zero (to avoid divide by zero)
    (( (currentContract._batchesQueue.info.totalUnstETHIdsCount!= 0 && currentContract._accounting.stETHTotals.lockedShares!=0) ? (currentContract._accounting.stETHTotals.claimedETH * sumStETHLockedShares /currentContract._accounting.stETHTotals.lockedShares )  : 0 ) 
    // unstEth pool: the all claimed unsteth records minus those withdrawn already 
         +
        (sumClaimedUnSTEth - sumWithdrawnUnSTEth) 
        <=  nativeBalances[currentContract]  
    )
    && 
    (currentContract._batchesQueue.info.totalUnstETHIdsClaimed== 0 => currentContract._accounting.stETHTotals.claimedETH == 0) 

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
        requireInvariant solvency_stETH_before_rageQuit();
        validState(); 
    }
    preserved withdrawETH(uint256[] unstETHIds) with (env e) {
        require unstETHIds.length ==1; 
        require sumClaimedUnSTEth >= unstETHIds[0];
        require e.msg.sender != currentContract;
        requireInvariant solvency_stETH_before_rageQuit();
        validState(); 

    }
}



