import "../problems.spec";
import "../unresolved.spec";
import "../optimizations.spec";



methods {
    function _.getRageQuitSupport() external => DISPATCHER(true);
    function _.isRageQuitFinalized() external => DISPATCHER(true);
    function _.MASTER_COPY() external => DISPATCHER(true);
    function _.startRageQuit(Durations.Duration, Durations.Duration) external => DISPATCHER(true);
    function _.initialize(address) external => DISPATCHER(true);
}

use builtin rule sanity filtered { f -> f.contract == currentContract }
