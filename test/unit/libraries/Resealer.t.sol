// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Resealer} from "contracts/libraries/Resealer.sol";
import {IResealManager} from "contracts/interfaces/IResealManager.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract ResealerTest is UnitTest {
    using Resealer for Resealer.Context;

    Resealer.Context ctx;

    address resealManager = makeAddr("resealManager");
    address resealCommittee = makeAddr("resealCommittee");

    function setUp() external {
        ctx.resealManager = IResealManager(resealManager);
        ctx.resealCommittee = resealCommittee;
    }

    function testFuzz_setResealManager_HappyPath(IResealManager newResealManager) external {
        vm.assume(newResealManager != ctx.resealManager && address(newResealManager) != address(0));

        vm.expectEmit();
        emit Resealer.ResealManagerSet(newResealManager);
        this.external__setResealManager(newResealManager);

        assertEq(address(ctx.resealManager), address(newResealManager));
    }

    function test_setResealManager_RevertOn_InvalidResealManager() external {
        vm.expectRevert(abi.encodeWithSelector(Resealer.InvalidResealManager.selector, address(ctx.resealManager)));
        this.external__setResealManager(ctx.resealManager);

        vm.expectRevert(abi.encodeWithSelector(Resealer.InvalidResealManager.selector, address(0)));
        this.external__setResealManager(IResealManager(address(0)));
    }

    function testFuzz_setResealCommittee_HappyPath(address newResealCommittee) external {
        vm.assume(newResealCommittee != ctx.resealCommittee);

        vm.expectEmit();
        emit Resealer.ResealCommitteeSet(newResealCommittee);
        this.external__setResealCommittee(newResealCommittee);

        assertEq(ctx.resealCommittee, newResealCommittee);
    }

    function test_setResealCommittee_RevertOn_InvalidResealCommittee() external {
        vm.expectRevert(abi.encodeWithSelector(Resealer.InvalidResealCommittee.selector, ctx.resealCommittee));
        this.external__setResealCommittee(ctx.resealCommittee);
    }

    function test_checkCallerIsResealCommittee_HappyPath() external {
        vm.prank(resealCommittee);
        this.external__checkCallerIsResealCommittee();
    }

    function testFuzz_checkCallerIsResealCommittee_RevertOn_Stranger(address stranger) external {
        vm.assume(stranger != resealCommittee);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Resealer.CallerIsNotResealCommittee.selector, stranger));
        this.external__checkCallerIsResealCommittee();
    }

    function external__checkCallerIsResealCommittee() external view {
        ctx.checkCallerIsResealCommittee();
    }

    function external__setResealCommittee(address newResealCommittee) external {
        ctx.setResealCommittee(newResealCommittee);
    }

    function external__setResealManager(IResealManager newResealManager) external {
        ctx.setResealManager(newResealManager);
    }
}
