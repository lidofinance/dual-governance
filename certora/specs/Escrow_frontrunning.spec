import "./Escrow.spec";

/**
@title W2-2 In a situation where requestNextWithdrawalsBatch should close the queue, 
    there is no way to prevent it from being closed by first calling another function.
@notice We are filtering out some functions that are not interesting since they cannot 
    successfully be called in a situation where requestNextWithdrawalsBatch makes sense to call.
*/
// Run link: https://prover.certora.com/output/37629/64c57d2946fe47da9b9c4ae0057e0378?anonymousKey=62e64093362fa9f21325d7032f8cad215eca2693
// Status: PASSING
rule W2_2_front_running(method f) {
    storage initial_storage = lastStorage;

    // set up one run in which requestNextWithdrawalsBatch closes the queue
    require !isWithdrawalsBatchesClosedNonReverting();
    env e;
    uint batchsize;
    requestNextWithdrawalsBatch(e, batchsize);
    require isWithdrawalsBatchesClosedNonReverting();

    // if we frontrun something else, at the end it should still be closed
    calldataarg args;
    f@withrevert(e, args) at initial_storage;
    bool fReverted = lastReverted;
    requestNextWithdrawalsBatch(e, batchsize);
    uint stETHRemaining = stEth.balanceOf(currentContract);
    uint minStETHWithdrawalRequestAmount = withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT();
    assert fReverted || stETHRemaining < minStETHWithdrawalRequestAmount => isWithdrawalsBatchesClosedNonReverting();
}
