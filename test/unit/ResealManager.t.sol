// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ResealManager} from "contracts/ResealManager.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {ISealable} from "contracts/interfaces/ISealable.sol";
import {Durations} from "contracts/types/Duration.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract ResealManagerUnitTests is UnitTest {
    ResealManager internal resealManager;

    address timelock = makeAddr("timelock");
    address sealable = makeAddr("sealable");
    address private governance = makeAddr("governance");

    function setUp() external {
        vm.mockCall(timelock, abi.encodeWithSelector(ITimelock.getGovernance.selector), abi.encode(governance));

        resealManager = new ResealManager(ITimelock(timelock));
    }

    function test_resealSuccess() public {
        uint256 futureTimestamp = block.timestamp + 1000;
        vm.mockCall(
            sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), abi.encode(futureTimestamp)
        );

        vm.expectCall(sealable, abi.encodeWithSelector(ISealable.resume.selector));
        vm.expectCall(sealable, abi.encodeWithSelector(ISealable.pauseFor.selector, type(uint256).max));

        vm.prank(governance);
        resealManager.reseal(sealable);
    }

    function test_resealFailsForPastTimestamp() public {
        uint256 pastTimestamp = block.timestamp;
        vm.mockCall(
            sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), abi.encode(pastTimestamp)
        );

        _wait(Durations.from(1));

        vm.prank(governance);
        vm.expectRevert(ResealManager.SealableWrongPauseState.selector);
        resealManager.reseal(sealable);
    }

    function test_resealFailsForInfinitePause() public {
        vm.mockCall(
            sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), abi.encode(type(uint256).max)
        );

        vm.prank(governance);
        vm.expectRevert(ResealManager.SealableWrongPauseState.selector);
        resealManager.reseal(sealable);
    }

    function test_resumeSuccess() public {
        uint256 futureTimestamp = block.timestamp + 1000;
        vm.mockCall(
            sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), abi.encode(futureTimestamp)
        );

        vm.expectCall(sealable, abi.encodeWithSelector(ISealable.resume.selector));

        vm.prank(governance);
        resealManager.resume(sealable);
    }

    function test_resumeFailsForPastTimestamp() public {
        uint256 pastTimestamp = block.timestamp;
        vm.mockCall(
            sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), abi.encode(pastTimestamp)
        );

        _wait(Durations.from(1));

        vm.prank(governance);
        vm.expectRevert(ResealManager.SealableWrongPauseState.selector);
        resealManager.resume(sealable);
    }

    function test_revertWhenSenderIsNotGovernanceOnReseal() public {
        uint256 futureTimestamp = block.timestamp + 1000;
        vm.mockCall(
            sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), abi.encode(futureTimestamp)
        );

        vm.prank(address(0x123));
        vm.expectRevert(ResealManager.SenderIsNotGovernance.selector);
        resealManager.reseal(sealable);
    }

    function test_revertWhenSenderIsNotGovernanceOnResume() public {
        uint256 futureTimestamp = block.timestamp + 1000;
        vm.mockCall(
            sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), abi.encode(futureTimestamp)
        );

        vm.prank(address(0x123));
        vm.expectRevert(ResealManager.SenderIsNotGovernance.selector);
        resealManager.resume(sealable);
    }
}
