import "Common.spec";
using EmergencyProtectedTimelock as EmergencyProtectedTimelock;

methods {
    function _.startRageQuit(Durations.Duration rageQuitExtensionPeriodDuration, Durations.Duration rageQuitEthWithdrawalsDelay) external => NONDET;
    function _.initialize(Durations.Duration minAssetsLockDuration) external => NONDET;
    function _.setMinAssetsLockDuration(Durations.Duration newMinAssetsLockDuration) external => NONDET;
}

// Run link: https://prover.certora.com/output/65266/bbf96e1018bc46678470271a1df53ccb/?anonymousKey=883b3d8a40db2d97124b5f3d2f3887e6c22ddffa
// Status: VIOLATED, discussion on security finding pending 
// setAdminExecutor can tranfer the AdminExecutor role to an address that is 
// not an Executor
strong invariant admin_executor_is_executor()
    isExecutor(EmergencyProtectedTimelock.getAdminExecutor());