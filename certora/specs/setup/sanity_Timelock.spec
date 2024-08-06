import "../problems.spec";
import "../unresolved.spec";
import "../optimizations.spec";

methods {
    function _.execute(address,uint256,bytes) external => DISPATCHER(true);
    function _.transferOwnership(address) external => DISPATCHER(true);
}

use builtin rule sanity filtered { f -> f.contract == currentContract }
