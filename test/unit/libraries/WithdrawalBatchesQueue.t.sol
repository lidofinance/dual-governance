// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UnitTest} from "test/utils/unit-test.sol";
import {WithdrawalsBatchesQueue, Status} from "contracts/libraries/WithdrawalBatchesQueue.sol";

contract WithdrawalsBatchesQueueTest is UnitTest {
    using WithdrawalsBatchesQueue for WithdrawalsBatchesQueue.State;

    WithdrawalsBatchesQueue.State public state;

    function setUp() external {
        state.status = Status.Empty;
    }

    function test_calcRequestAmounts_exactMultiple() external {
        uint256 minRequestAmount = 1;
        uint256 maxRequestAmount = 10;
        uint256 remainingAmount = 50;

        uint256[] memory result =
            WithdrawalsBatchesQueue.calcRequestAmounts(minRequestAmount, maxRequestAmount, remainingAmount);

        uint256[] memory expected = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            expected[i] = 10;
        }

        assertEq(result.length, expected.length);
        for (uint256 i = 0; i < result.length; ++i) {
            assertEq(result[i], expected[i]);
        }
    }

    function test_calcRequestAmounts_withRemainderToBeWithdrawn() external {
        uint256 minRequestAmount = 1;
        uint256 maxRequestAmount = 10;
        uint256 remainingAmount = 55;

        uint256[] memory result =
            WithdrawalsBatchesQueue.calcRequestAmounts(minRequestAmount, maxRequestAmount, remainingAmount);

        uint256[] memory expected = new uint256[](6);
        for (uint256 i = 0; i < 5; ++i) {
            expected[i] = 10;
        }
        expected[5] = 5;

        assertEq(result.length, expected.length);
        for (uint256 i = 0; i < result.length; ++i) {
            assertEq(result[i], expected[i]);
        }
    }

    function test_calcRequestAmounts_withSmallRemainderToNotBeWithdrawn() external {
        uint256 minRequestAmount = 6;
        uint256 maxRequestAmount = 10;
        uint256 remainingAmount = 55;

        uint256[] memory result =
            WithdrawalsBatchesQueue.calcRequestAmounts(minRequestAmount, maxRequestAmount, remainingAmount);

        uint256[] memory expected = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            expected[i] = 10;
        }

        assertEq(result.length, expected.length);
        for (uint256 i = 0; i < result.length; ++i) {
            assertEq(result[i], expected[i]);
        }
    }

    function test_openQueue() external {
        assertEq(uint256(state.status), uint256(Status.Empty));

        state.open();

        assertEq(uint256(state.status), uint256(Status.Opened));
        assertEq(state.batches.length, 1); // empty batch for first item
    }

    function test_openQueueWhenAlreadyOpened() external {
        state.open();
        assertEq(uint256(state.status), uint256(Status.Opened));

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalsBatchesQueue.InvalidWithdrawalsBatchesQueueStatus.selector, Status.Opened, Status.Empty
            )
        );
        state.open();
    }

    function test_openQueueWhenAlreadyOpenedAndClosed() external {
        state.open();
        assertEq(uint256(state.status), uint256(Status.Opened));

        state.close();
        assertEq(uint256(state.status), uint256(Status.Closed));

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalsBatchesQueue.InvalidWithdrawalsBatchesQueueStatus.selector, Status.Closed, Status.Empty
            )
        );
        state.open();
    }

    function test_closeQueue() external {
        state.open();
        assertEq(uint256(state.status), uint256(Status.Opened));

        state.close();
        assertEq(uint256(state.status), uint256(Status.Closed));
    }

    function testCloseQueueRevertsWhenNotOpened() external {
        assertEq(uint256(state.status), uint256(Status.Empty));

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalsBatchesQueue.InvalidWithdrawalsBatchesQueueStatus.selector, Status.Empty, Status.Opened
            )
        );
        state.close();

        state.open();
        assertEq(uint256(state.status), uint256(Status.Opened));

        state.close();
        assertEq(uint256(state.status), uint256(Status.Closed));

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalsBatchesQueue.InvalidWithdrawalsBatchesQueueStatus.selector, Status.Closed, Status.Opened
            )
        );
        state.close();
    }

    function test_isClosed() external {
        assertEq(state.isClosed(), false);

        state.open();
        assertEq(state.isClosed(), false);

        state.close();
        assertEq(state.isClosed(), true);
    }

    function test_isAllUnstETHClaimed() external {
        state.totalUnstETHCount = 100;
        state.totalUnstETHClaimed = 0;
        assertEq(state.isAllUnstETHClaimed(), false);

        state.totalUnstETHCount = 100;
        state.totalUnstETHClaimed = 100;
        assertEq(state.isAllUnstETHClaimed(), true);

        state.totalUnstETHCount = 100;
        state.totalUnstETHClaimed = 50;
        assertEq(state.isAllUnstETHClaimed(), false);
    }

    function test_checkOpenedWhenOpened() external {
        state.open();
        assertEq(uint256(state.status), uint256(Status.Opened));

        state.checkOpened();
    }

    function test_checkOpenedRevertsWhenEmpty() external {
        assertEq(uint256(state.status), uint256(Status.Empty));

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalsBatchesQueue.InvalidWithdrawalsBatchesQueueStatus.selector, Status.Empty, Status.Opened
            )
        );
        state.checkOpened();
    }

    function test_checkOpenedRevertsWhenClosed() external {
        state.open();
        state.close();

        assertEq(uint256(state.status), uint256(Status.Closed));

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalsBatchesQueue.InvalidWithdrawalsBatchesQueueStatus.selector, Status.Closed, Status.Opened
            )
        );
        state.checkOpened();
    }

    function test_addSequentialUnstETHIds() external {
        state.open();

        uint256[] memory unstETHIds = new uint256[](3);
        unstETHIds[0] = 1;
        unstETHIds[1] = 2;
        unstETHIds[2] = 3;

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(unstETHIds);

        state.add(unstETHIds);

        assertEq(state.batches.length, 2);
        assertEq(state.totalUnstETHCount, 3);
    }

    function test_addNonSequentialUnstETHIdsReverts() public {
        state.open();

        uint256[] memory unstETHIds = new uint256[](3);
        unstETHIds[0] = 1;
        unstETHIds[1] = 3;
        unstETHIds[2] = 4;

        vm.expectRevert(); // no revert custom error because assert is used
        state.add(unstETHIds);
    }

    function test_addAndMergeBatches() public {
        state.open();

        uint256[] memory unstETHIds1 = new uint256[](3);
        unstETHIds1[0] = 1;
        unstETHIds1[1] = 2;
        unstETHIds1[2] = 3;

        uint256[] memory unstETHIds2 = new uint256[](2);
        unstETHIds2[0] = 4;
        unstETHIds2[1] = 5;

        state.add(unstETHIds1);
        assertEq(state.batches.length, 2);
        assertEq(state.totalUnstETHCount, 3);

        state.add(unstETHIds2);
        assertEq(state.batches.length, 3);
        assertEq(state.totalUnstETHCount, 5);
    }

    function test_claimNextBatchSingleBatch() public {
        state.open();

        uint256[] memory unstETHIds = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            unstETHIds[i] = i + 1;
        }

        state.add(unstETHIds);
        assertEq(state.batches.length, 2);

        uint256 maxUnstETHIdsCount = 3;
        uint256[] memory claimedIds = state.claimNextBatch(maxUnstETHIdsCount);

        assertEq(claimedIds.length, maxUnstETHIdsCount);
        for (uint256 i = 0; i < maxUnstETHIdsCount; ++i) {
            assertEq(claimedIds[i], i + 1);
        }

        assertEq(state.totalUnstETHClaimed, maxUnstETHIdsCount);
    }

    function test_claimNextBatchMultipleBatches() public {
        state.open();

        uint256[] memory unstETHIds1 = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            unstETHIds1[i] = i + 1;
        }

        uint256[] memory unstETHIds2 = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            unstETHIds2[i] = i + 6;
        }

        state.add(unstETHIds1);
        state.add(unstETHIds2);
        assertEq(state.batches.length, 3);

        uint256 maxUnstETHIdsCount = 8;

        uint256[] memory unstETHIdsEvent = new uint256[](8);
        for (uint256 i = 0; i < 5; ++i) {
            unstETHIdsEvent[i] = i + 1;
        }
        for (uint256 i = 0; i < 3; ++i) {
            unstETHIdsEvent[i + 5] = i + 6;
        }
        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstETHIdsEvent);

        uint256[] memory claimedIds = state.claimNextBatch(maxUnstETHIdsCount);

        assertEq(claimedIds.length, maxUnstETHIdsCount);
        for (uint256 i = 0; i < maxUnstETHIdsCount; ++i) {
            assertEq(claimedIds[i], i + 1);
        }

        assertEq(state.totalUnstETHClaimed, maxUnstETHIdsCount);
    }

    function test_claimNextBatchExactBatch() public {
        state.open();

        uint256 maxUnstETHIdsCount = 5;
        uint256[] memory unstETHIds = new uint256[](maxUnstETHIdsCount);
        for (uint256 i = 0; i < maxUnstETHIdsCount; ++i) {
            unstETHIds[i] = i + 1;
        }

        state.add(unstETHIds);
        assertEq(state.batches.length, 2);

        uint256[] memory claimedIds = state.claimNextBatch(maxUnstETHIdsCount);

        assertEq(claimedIds.length, maxUnstETHIdsCount);
        for (uint256 i = 0; i < maxUnstETHIdsCount; ++i) {
            assertEq(claimedIds[i], i + 1);
        }

        assertEq(state.totalUnstETHClaimed, maxUnstETHIdsCount);
    }

    function test_claimNextBatchMoreThanAvailable() public {
        state.open();
        uint256 maxUnstETHIdsCount = 10;
        uint256 realUnstETHIdsCount = 5;
        uint256[] memory unstETHIds = new uint256[](realUnstETHIdsCount);
        for (uint256 i = 0; i < realUnstETHIdsCount; ++i) {
            unstETHIds[i] = i + 1;
        }

        state.add(unstETHIds);
        assertEq(state.batches.length, 2);

        vm.expectEmit();
        emit WithdrawalsBatchesQueue.UnstETHIdsClaimed(unstETHIds);
        uint256[] memory claimedIds = state.claimNextBatch(maxUnstETHIdsCount);

        assertEq(claimedIds.length, realUnstETHIdsCount);
        for (uint256 i = 0; i < realUnstETHIdsCount; ++i) {
            assertEq(claimedIds[i], i + 1);
        }

        assertEq(state.totalUnstETHClaimed, unstETHIds.length);
    }

    function test_getNextWithdrawalsBatchesSingleBatch() public {
        state.open();
        uint256[] memory unstETHIds = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            unstETHIds[i] = i + 1;
        }

        state.add(unstETHIds);
        assertEq(state.batches.length, 2);

        uint256 limit = 3;
        uint256[] memory nextIds = state.getNextWithdrawalsBatches(limit);

        assertEq(nextIds.length, limit);
        for (uint256 i = 0; i < limit; ++i) {
            assertEq(nextIds[i], i + 1);
        }

        assertEq(state.totalUnstETHClaimed, 0);
    }

    function test_getNextWithdrawalsBatchesMultipleBatches() public {
        state.open();
        uint256[] memory unstETHIds1 = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            unstETHIds1[i] = i + 1;
        }

        uint256[] memory unstETHIds2 = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            unstETHIds2[i] = i + 6;
        }

        state.add(unstETHIds1);
        state.add(unstETHIds2);

        assertEq(state.batches.length, 3);

        uint256 limit = 8;
        uint256[] memory nextIds = state.getNextWithdrawalsBatches(limit);

        assertEq(nextIds.length, limit);
        for (uint256 i = 0; i < limit; ++i) {
            assertEq(nextIds[i], i + 1);
        }

        assertEq(state.totalUnstETHClaimed, 0);
    }

    function test_getNextWithdrawalsBatchesExactBatch() public {
        state.open();
        uint256[] memory unstETHIds = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            unstETHIds[i] = i + 1;
        }

        state.add(unstETHIds);
        assertEq(state.batches.length, 2);

        uint256 limit = 5;
        uint256[] memory nextIds = state.getNextWithdrawalsBatches(limit);

        assertEq(nextIds.length, limit);
        for (uint256 i = 0; i < limit; ++i) {
            assertEq(nextIds[i], i + 1);
        }

        assertEq(state.totalUnstETHClaimed, 0);
    }

    function test_getNextWithdrawalsBatchesMoreThanAvailable() public {
        state.open();
        uint256[] memory unstETHIds = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            unstETHIds[i] = i + 1;
        }

        state.add(unstETHIds);
        assertEq(state.batches.length, 2);

        uint256 limit = 10;
        uint256[] memory nextIds = state.getNextWithdrawalsBatches(limit);

        assertEq(nextIds.length, 5);
        for (uint256 i = 0; i < 5; ++i) {
            assertEq(nextIds[i], i + 1);
        }

        assertEq(state.totalUnstETHClaimed, 0);
    }
}
