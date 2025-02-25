// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {ETHValue} from "contracts/types/ETHValue.sol";
import {SharesValue} from "contracts/types/SharesValue.sol";
import {Duration} from "contracts/types/Duration.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";
import {IndexOneBased} from "contracts/types/IndexOneBased.sol";

import {Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";
import {State as DualGovernanceState} from "contracts/DualGovernance.sol";

contract TestingAssertEqExtender is Test {
    struct Balances {
        uint256 stETHAmount;
        uint256 stETHShares;
        uint256 wstETHAmount;
        uint256 wstETHShares;
    }

    function assertEq(Duration a, Duration b) internal pure {
        assertEq(uint256(Duration.unwrap(a)), uint256(Duration.unwrap(b)));
    }

    function assertEq(Duration a, Duration b, string memory message) internal pure {
        assertEq(uint256(Duration.unwrap(a)), uint256(Duration.unwrap(b)), message);
    }

    function assertEq(Timestamp a, Timestamp b) internal pure {
        assertEq(uint256(Timestamp.unwrap(a)), uint256(Timestamp.unwrap(b)));
    }

    function assertEq(Timestamp a, Timestamp b, string memory message) internal pure {
        assertEq(uint256(Timestamp.unwrap(a)), uint256(Timestamp.unwrap(b)), message);
    }

    function assertEq(ProposalStatus a, ProposalStatus b) internal pure {
        assertEq(uint256(a), uint256(b));
    }

    function assertEq(ProposalStatus a, ProposalStatus b, string memory message) internal pure {
        assertEq(uint256(a), uint256(b), message);
    }

    function assertEq(DualGovernanceState a, DualGovernanceState b) internal pure {
        assertEq(uint256(a), uint256(b));
    }

    function assertEq(DualGovernanceState a, DualGovernanceState b, string memory message) internal pure {
        assertEq(uint256(a), uint256(b), message);
    }

    function assertEq(Balances memory b1, Balances memory b2, uint256 sharesEpsilon) internal pure {
        assertEq(b1.wstETHShares, b2.wstETHShares);
        assertEq(b1.wstETHAmount, b2.wstETHAmount);

        assertApproxEqAbs(b1.stETHShares, b2.stETHShares, sharesEpsilon);
        assertApproxEqAbs(b1.stETHAmount, b2.stETHAmount, sharesEpsilon);
    }

    function assertEq(PercentD16 a, PercentD16 b) internal pure {
        assertEq(PercentD16.unwrap(a), PercentD16.unwrap(b));
    }

    function assertEq(ETHValue a, ETHValue b) internal pure {
        assertEq(ETHValue.unwrap(a), ETHValue.unwrap(b));
    }

    function assertEq(SharesValue a, SharesValue b) internal pure {
        assertEq(SharesValue.unwrap(a), SharesValue.unwrap(b));
    }

    function assertEq(IndexOneBased a, IndexOneBased b) internal pure {
        assertEq(IndexOneBased.unwrap(a), IndexOneBased.unwrap(b));
    }
}
