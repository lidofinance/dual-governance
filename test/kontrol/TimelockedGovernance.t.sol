pragma solidity 0.8.26;

import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {DualGovernanceSetUp} from "test/kontrol/DualGovernanceSetUp.sol";

contract TimelockedGovernanceTest is DualGovernanceSetUp {
    TimelockedGovernance private _timelockedGovernance;

    function setUp() public override {
        super.setUp();

        address governance = address(uint160(uint256(keccak256("governance"))));
        _timelockedGovernance = new TimelockedGovernance(governance, timelock);
    }

    function testSubmitProposalRevert(address caller, ExternalCall[] calldata calls, string calldata metadata) public {
        vm.assume(caller != _timelockedGovernance.GOVERNANCE());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockedGovernance.CallerIsNotGovernance.selector, caller));
        _timelockedGovernance.submitProposal(calls, metadata);
        vm.stopPrank();
    }

    function testCancellAllPendingProposalsRevert(address caller) public {
        vm.assume(caller != _timelockedGovernance.GOVERNANCE());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockedGovernance.CallerIsNotGovernance.selector, caller));
        _timelockedGovernance.cancelAllPendingProposals();
        vm.stopPrank();
    }
}
