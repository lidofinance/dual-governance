import "../ERC20/erc20dispatched.spec";

use builtin rule sanity filtered { f -> f.contract == currentContract }
