// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UnitTest} from "test/utils/unit-test.sol";
import {WithdrawalsBatchesQueue, State} from "contracts/libraries/WithdrawalBatchesQueue.sol";

contract WithdrawalsBatchesQueueTest is UnitTest {
    using WithdrawalsBatchesQueue for WithdrawalsBatchesQueue.Context;

    uint256 internal constant _DEFAULT_BOUNDARY_UNST_ETH_ID = 777;
    WithdrawalsBatchesQueue.Context internal _batchesQueue;

    // ---
    // open()
    // ---

    function test_open_HappyPath() external {
        assertEq(_batchesQueue.info.state, State.Absent);
        assertEq(_batchesQueue.batches.length, 0);

        _batchesQueue.open(_DEFAULT_BOUNDARY_UNST_ETH_ID);

        assertEq(_batchesQueue.info.state, State.Opened);
        assertEq(_batchesQueue.batches.length, 1);
        assertEq(_batchesQueue.batches[0].firstUnstETHId, _DEFAULT_BOUNDARY_UNST_ETH_ID);
        assertEq(_batchesQueue.batches[0].lastUnstETHId, _DEFAULT_BOUNDARY_UNST_ETH_ID);
    }

    function test_open_RevertOn_CallFromOpenedState() external {
        _batchesQueue.info.state = State.Opened;
        assertEq(_batchesQueue.info.state, State.Opened);

        vm.expectRevert(WithdrawalsBatchesQueue.WithdrawalBatchesQueueIsNotInAbsentState.selector);
        _batchesQueue.open(_DEFAULT_BOUNDARY_UNST_ETH_ID);
    }

    function test_open_Emit_WithdrawalBatchesQueueOpened() external {
        assertEq(_batchesQueue.info.state, State.Absent);

        vm.expectEmit(true, false, false, false);
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueOpened(_DEFAULT_BOUNDARY_UNST_ETH_ID);

        _batchesQueue.open(_DEFAULT_BOUNDARY_UNST_ETH_ID);
    }

    // ---
    // addUnstETHIds()
    // ---

    function test_addUnstETHIds_HappyPath_AddIntoNewBatch() external {
        _openBatchesQueue();

        uint256 unstETHIdsLength = 3;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;

        uint256[] memory unstETHIds =
            _generateFakeUnstETHIds({length: unstETHIdsLength, firstUnstETHId: firstUnstETHId});
        _batchesQueue.addUnstETHIds(unstETHIds);

        assertEq(_batchesQueue.batches.length, 2);
        assertEq(_batchesQueue.info.totalUnstETHIdsCount, unstETHIdsLength);
        assertEq(_batchesQueue.info.totalUnstETHIdsClaimed, 0);
        assertEq(_batchesQueue.info.lastClaimedBatchIndex, 0);
        assertEq(_batchesQueue.info.lastClaimedUnstETHIdIndex, 0);

        assertEq(_batchesQueue.batches[1].firstUnstETHId, firstUnstETHId);
        assertEq(_batchesQueue.batches[1].lastUnstETHId, firstUnstETHId + unstETHIdsLength - 1);
    }

    function test_addUnstETHIds_HappyPath_AddIntoSameBatch() external {
        _openBatchesQueue();

        uint256 firstAddingUnstETHIdsLength = 3;
        uint256 firstAddingFirstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;

        uint256[] memory firstAddingUnstETHIds =
            _generateFakeUnstETHIds({length: firstAddingUnstETHIdsLength, firstUnstETHId: firstAddingFirstUnstETHId});

        _batchesQueue.addUnstETHIds(firstAddingUnstETHIds);

        assertEq(_batchesQueue.batches.length, 2);
        assertEq(_batchesQueue.info.totalUnstETHIdsCount, firstAddingUnstETHIdsLength);
        assertEq(_batchesQueue.info.totalUnstETHIdsClaimed, 0);
        assertEq(_batchesQueue.info.lastClaimedBatchIndex, 0);
        assertEq(_batchesQueue.info.lastClaimedUnstETHIdIndex, 0);

        assertEq(_batchesQueue.batches[1].firstUnstETHId, firstAddingFirstUnstETHId);
        assertEq(_batchesQueue.batches[1].lastUnstETHId, firstAddingUnstETHIds[firstAddingUnstETHIds.length - 1]);

        uint256 secondAddingUnstETHIdsLength = 7;
        uint256 secondAddingFirstUnstETHId = firstAddingUnstETHIds[firstAddingUnstETHIds.length - 1] + 1;
        uint256[] memory secondAddingUnstETHIds =
            _generateFakeUnstETHIds({length: secondAddingUnstETHIdsLength, firstUnstETHId: secondAddingFirstUnstETHId});

        _batchesQueue.addUnstETHIds(secondAddingUnstETHIds);

        assertEq(_batchesQueue.batches.length, 2);
        assertEq(_batchesQueue.info.totalUnstETHIdsCount, firstAddingUnstETHIdsLength + secondAddingUnstETHIdsLength);
        assertEq(_batchesQueue.info.totalUnstETHIdsClaimed, 0);
        assertEq(_batchesQueue.info.lastClaimedBatchIndex, 0);
        assertEq(_batchesQueue.info.lastClaimedUnstETHIdIndex, 0);

        assertEq(_batchesQueue.batches[1].firstUnstETHId, firstAddingFirstUnstETHId);
        assertEq(_batchesQueue.batches[1].lastUnstETHId, secondAddingUnstETHIds[secondAddingUnstETHIds.length - 1]);
    }

    function testFuzz_addUnstETHIds_HappyPath(
        uint256 seedUnstETHId,
        uint16 unstETHIdsCount,
        uint256 firstUnstETHId
    ) external {
        vm.assume(unstETHIdsCount > 0);
        vm.assume(firstUnstETHId > seedUnstETHId);
        vm.assume(type(uint256).max - unstETHIdsCount >= firstUnstETHId);

        _openBatchesQueue(seedUnstETHId);

        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});
        _batchesQueue.addUnstETHIds(unstETHIds);

        assertEq(_batchesQueue.batches.length, 2, "Invalid batches length");
        assertEq(_batchesQueue.batches[1].firstUnstETHId, firstUnstETHId, "Invalid firstUnstETHId value");
        assertEq(
            _batchesQueue.batches[1].lastUnstETHId, firstUnstETHId + unstETHIdsCount - 1, "Invalid lastUnstETHId value"
        );
    }

    function test_addUnstETHIds_RevertOn_QueueNotInOpenedState() external {
        vm.expectRevert(WithdrawalsBatchesQueue.WithdrawalBatchesQueueIsNotInOpenedState.selector);
        _batchesQueue.addUnstETHIds(new uint256[](0));
    }

    function test_addUnstETHIds_RevertOn_EmptyUnstETHIdsArray() external {
        _openBatchesQueue();

        vm.expectRevert(WithdrawalsBatchesQueue.EmptyBatch.selector);
        _batchesQueue.addUnstETHIds(new uint256[](0));
    }

    function test_addUnstETHIds_RevertOn_NonSequentialUnstETHIds() external {
        _openBatchesQueue();

        uint256 unstETHIdsCount = 5;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID;
        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});

        // violate the order of the NFT ids
        unstETHIds[2] = unstETHIds[3];

        vm.expectRevert();
        _batchesQueue.addUnstETHIds(unstETHIds);
    }

    function test_addUnstETHIds_RevertOn_FirstAddedUnstETHIdLessThanLastAddedUnstETHId() external {
        _openBatchesQueue();

        uint256 unstETHIdsCount = 5;
        uint256[] memory invalidUnstETHIdsSequence =
            _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: _DEFAULT_BOUNDARY_UNST_ETH_ID - 1});

        // check for the empty queue & boundary item
        vm.expectRevert(WithdrawalsBatchesQueue.InvalidUnstETHIdsSequence.selector);
        _batchesQueue.addUnstETHIds(invalidUnstETHIdsSequence);

        // check for the non empty queue
        uint256[] memory validUnstETHIdsSequence =
            _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: _DEFAULT_BOUNDARY_UNST_ETH_ID + 1});
        _batchesQueue.addUnstETHIds(validUnstETHIdsSequence);

        vm.expectRevert(WithdrawalsBatchesQueue.InvalidUnstETHIdsSequence.selector);
        _batchesQueue.addUnstETHIds(invalidUnstETHIdsSequence);
    }

    function test_addUnstETHIds_RevertOn_FirstAddedUnstETHIdEqualToLastAddedUnstETHId() external {
        _openBatchesQueue();

        uint256 unstETHIdsCount = 5;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID;
        uint256[] memory invalidUnstETHIdsSequence =
            _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});

        // check for the empty queue & boundary item
        vm.expectRevert(WithdrawalsBatchesQueue.InvalidUnstETHIdsSequence.selector);
        _batchesQueue.addUnstETHIds(invalidUnstETHIdsSequence);

        // check for the non empty queue
        uint256[] memory validUnstETHIdsSequence =
            _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: _DEFAULT_BOUNDARY_UNST_ETH_ID + 1});
        _batchesQueue.addUnstETHIds(validUnstETHIdsSequence);

        invalidUnstETHIdsSequence = _generateFakeUnstETHIds({
            length: unstETHIdsCount,
            firstUnstETHId: validUnstETHIdsSequence[validUnstETHIdsSequence.length - 1]
        });

        vm.expectRevert(WithdrawalsBatchesQueue.InvalidUnstETHIdsSequence.selector);
        _batchesQueue.addUnstETHIds(invalidUnstETHIdsSequence);
    }

    function test_addUnstETHIds_Emit_UnstETHIdsAdded() external {
        _openBatchesQueue();

        uint256 unstETHIdsCount = 7;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});

        vm.expectEmit(true, false, false, false);
        emit WithdrawalsBatchesQueue.UnstETHIdsAdded(unstETHIds);

        _batchesQueue.addUnstETHIds(unstETHIds);
    }

    // ---
    // claimNextBatch()
    // ---

    function test_claimNextBatch_HappyPath_MultipleBatches() external {
        _openBatchesQueue();

        uint256 firstBatchUnstETHIdsCount = 5;
        uint256 firstBatchFirstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory firstUnstETHIdsBatch =
            _generateFakeUnstETHIds({length: firstBatchUnstETHIdsCount, firstUnstETHId: firstBatchFirstUnstETHId});
        _batchesQueue.addUnstETHIds(firstUnstETHIdsBatch);
        assertEq(_batchesQueue.info.totalUnstETHIdsCount, firstBatchUnstETHIdsCount);

        uint256 secondBatchUnstETHIdsCount = 13;
        uint256 secondBatchFirstUnstETHId = firstUnstETHIdsBatch[firstUnstETHIdsBatch.length - 1] + 1;
        uint256[] memory secondUnstETHIdsBatch =
            _generateFakeUnstETHIds({length: secondBatchUnstETHIdsCount, firstUnstETHId: secondBatchFirstUnstETHId});
        _batchesQueue.addUnstETHIds(secondUnstETHIdsBatch);
        assertEq(_batchesQueue.info.totalUnstETHIdsCount, firstBatchUnstETHIdsCount + secondBatchUnstETHIdsCount);

        uint256 firstResultingBatchUnstETHIdsCount = 8;
        uint256[] memory firstResultingBatch = _batchesQueue.claimNextBatch(firstResultingBatchUnstETHIdsCount);

        assertEq(firstResultingBatch.length, firstResultingBatchUnstETHIdsCount);

        // in the first resulting batch must be all unstETHIds from the first added batch of unstETHIds
        for (uint256 i = 0; i < firstBatchUnstETHIdsCount; ++i) {
            assertEq(firstResultingBatch[i], firstBatchFirstUnstETHId + i);
        }
        // the rest items is taken from the second adding batch
        uint256 firstResultingBatchUnstETHIdsFromSecondAddingBatch =
            firstResultingBatchUnstETHIdsCount - firstBatchUnstETHIdsCount;
        for (uint256 i = 0; i < firstResultingBatchUnstETHIdsFromSecondAddingBatch; ++i) {
            assertEq(firstResultingBatch[firstBatchUnstETHIdsCount + i], secondBatchFirstUnstETHId + i);
        }

        uint256[] memory secondResultingBatch = _batchesQueue.claimNextBatch(64);

        assertEq(
            secondResultingBatch.length,
            firstBatchUnstETHIdsCount + secondBatchUnstETHIdsCount - firstResultingBatchUnstETHIdsCount
        );

        // the rest items is taken from the second adding batch
        for (uint256 i = 0; i < secondResultingBatch.length; ++i) {
            assertEq(
                secondResultingBatch[i],
                secondBatchFirstUnstETHId + firstResultingBatchUnstETHIdsFromSecondAddingBatch + i
            );
        }
    }

    function test_claimNextBatch_HappyPath_SingleBatch() external {
        _openBatchesQueue();

        uint256 unstETHIdsCount = 5;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});

        _batchesQueue.addUnstETHIds(unstETHIds);
        assertEq(_batchesQueue.info.totalUnstETHIdsCount, unstETHIdsCount);
        assertEq(_batchesQueue.batches.length, 2);

        uint256 maxUnstETHIdsCount = 3;
        uint256[] memory claimedIds = _batchesQueue.claimNextBatch(maxUnstETHIdsCount);

        assertEq(claimedIds.length, maxUnstETHIdsCount);
        assertEq(_batchesQueue.info.totalUnstETHIdsClaimed, maxUnstETHIdsCount);

        for (uint256 i = 0; i < maxUnstETHIdsCount; ++i) {
            assertEq(claimedIds[i], _DEFAULT_BOUNDARY_UNST_ETH_ID + i + 1);
        }
    }

    // ---
    // close()
    // ---

    function test_close_HappyPath() external {
        _openBatchesQueue();
        assertEq(_batchesQueue.info.state, State.Opened);

        _batchesQueue.close();
        assertEq(_batchesQueue.info.state, State.Closed);
    }

    function test_close_RevertOn_QueueNotInOpenedState() external {
        vm.expectRevert(WithdrawalsBatchesQueue.WithdrawalBatchesQueueIsNotInOpenedState.selector);
        _batchesQueue.close();

        _batchesQueue.open({boundaryUnstETHId: 1});
        _batchesQueue.close();

        vm.expectRevert(WithdrawalsBatchesQueue.WithdrawalBatchesQueueIsNotInOpenedState.selector);
        _batchesQueue.close();
    }

    function test_close_Emit_WithdrawalBatchesQueueClosed() external {
        _openBatchesQueue();
        assertEq(_batchesQueue.info.state, State.Opened);

        vm.expectEmit(true, false, false, false);
        emit WithdrawalsBatchesQueue.WithdrawalBatchesQueueClosed();

        _batchesQueue.close();
    }

    // ---
    // calcRequestAmounts()
    // ---

    function test_calcRequestAmounts_HappyPath_WithoutReminder() external {
        _openBatchesQueue();
        assertEq(_batchesQueue.info.state, State.Opened);

        uint256 minRequestAmount = 1;
        uint256 maxRequestAmount = 10;
        uint256 remainingAmount = 50;

        uint256[] memory requestAmounts = WithdrawalsBatchesQueue.calcRequestAmounts({
            minRequestAmount: minRequestAmount,
            maxRequestAmount: maxRequestAmount,
            remainingAmount: remainingAmount
        });

        uint256[] memory expected = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            expected[i] = 10;
        }

        assertEq(requestAmounts.length, expected.length);
        for (uint256 i = 0; i < requestAmounts.length; ++i) {
            assertEq(requestAmounts[i], expected[i]);
        }
    }

    function test_calcRequestAmounts_HappyPath_WithReminder() external {
        _openBatchesQueue();
        assertEq(_batchesQueue.info.state, State.Opened);

        uint256 minRequestAmount = 1;
        uint256 maxRequestAmount = 10;
        uint256 remainingAmount = 55;

        uint256[] memory requestAmounts = WithdrawalsBatchesQueue.calcRequestAmounts({
            minRequestAmount: minRequestAmount,
            maxRequestAmount: maxRequestAmount,
            remainingAmount: remainingAmount
        });

        uint256[] memory expected = new uint256[](6);
        for (uint256 i = 0; i < 5; ++i) {
            expected[i] = 10;
        }
        expected[5] = 5;

        assertEq(requestAmounts.length, expected.length);
        for (uint256 i = 0; i < requestAmounts.length; ++i) {
            assertEq(requestAmounts[i], expected[i]);
        }
    }

    // ---
    // getNextWithdrawalsBatches()
    // ---

    function test_getNextWithdrawalsBatches_HappyPath_SingleBatch() external {
        _openBatchesQueue();

        uint256 unstETHIdsCount = 5;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});

        _batchesQueue.addUnstETHIds(unstETHIds);
        assertEq(_batchesQueue.batches.length, 2);

        uint256 limit = 3;
        uint256[] memory nextIds = _batchesQueue.getNextWithdrawalsBatches(limit);

        assertEq(nextIds.length, limit);
        for (uint256 i = 0; i < limit; ++i) {
            assertEq(nextIds[i], _DEFAULT_BOUNDARY_UNST_ETH_ID + i + 1);
        }

        assertEq(_batchesQueue.info.totalUnstETHIdsClaimed, 0);
    }

    function test_getNextWithdrawalsBatches_HappyPath_MultipleBatches() external {
        _openBatchesQueue();

        uint256 firstAddingUnstETHIdsCount = 5;
        uint256 firstAddingFirstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory firstAddingUnstETHIds =
            _generateFakeUnstETHIds({length: firstAddingUnstETHIdsCount, firstUnstETHId: firstAddingFirstUnstETHId});
        _batchesQueue.addUnstETHIds(firstAddingUnstETHIds);

        uint256 secondAddingUnstETHIdsCount = 9;
        uint256 secondAddingFirstUnstETHId = firstAddingUnstETHIds[firstAddingUnstETHIds.length - 1] + 2;
        uint256[] memory secondAddingUnstETHIds =
            _generateFakeUnstETHIds({length: secondAddingUnstETHIdsCount, firstUnstETHId: secondAddingFirstUnstETHId});
        _batchesQueue.addUnstETHIds(secondAddingUnstETHIds);

        assertEq(_batchesQueue.batches.length, 3);

        uint256 limit = 7;
        uint256[] memory nextIds = _batchesQueue.getNextWithdrawalsBatches(limit);

        assertEq(nextIds.length, limit);
        for (uint256 i = 0; i < firstAddingUnstETHIdsCount; ++i) {
            assertEq(nextIds[i], _DEFAULT_BOUNDARY_UNST_ETH_ID + i + 1);
        }

        for (uint256 i = 0; i < limit - firstAddingUnstETHIdsCount; ++i) {
            assertEq(
                nextIds[firstAddingUnstETHIdsCount + i], firstAddingUnstETHIds[firstAddingUnstETHIds.length - 1] + i + 2
            );
        }

        assertEq(_batchesQueue.info.totalUnstETHIdsClaimed, 0);
    }

    function test_getNextWithdrawalsBatches_HappyPath_ExactBatch() external {
        _openBatchesQueue();

        uint256 unstETHIdsCount = 5;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});

        _batchesQueue.addUnstETHIds(unstETHIds);
        assertEq(_batchesQueue.batches.length, 2);

        uint256 limit = 5;
        uint256[] memory nextIds = _batchesQueue.getNextWithdrawalsBatches(limit);

        assertEq(nextIds.length, limit);
        for (uint256 i = 0; i < limit; ++i) {
            assertEq(nextIds[i], _DEFAULT_BOUNDARY_UNST_ETH_ID + i + 1);
        }

        assertEq(_batchesQueue.info.totalUnstETHIdsClaimed, 0);
    }

    function test_getNextWithdrawalsBatches_HappyPath_MoreThanAvailable() external {
        _openBatchesQueue();

        uint256 unstETHIdsCount = 5;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});

        _batchesQueue.addUnstETHIds(unstETHIds);
        assertEq(_batchesQueue.batches.length, 2);

        uint256 limit = 10;
        uint256[] memory nextIds = _batchesQueue.getNextWithdrawalsBatches(limit);

        assertEq(nextIds.length, 5);
        for (uint256 i = 0; i < 5; ++i) {
            assertEq(nextIds[i], _DEFAULT_BOUNDARY_UNST_ETH_ID + i + 1);
        }

        assertEq(_batchesQueue.info.totalUnstETHIdsClaimed, 0);
    }

    // ---
    // getBoundaryUnstETHId()
    // ---

    function test_getBoundaryUnstETHId_HappyPath() external {
        _openBatchesQueue();

        assertEq(_batchesQueue.getBoundaryUnstETHId(), _DEFAULT_BOUNDARY_UNST_ETH_ID);

        uint256 unstETHIdsCount = 5;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});
        _batchesQueue.addUnstETHIds(unstETHIds);

        assertEq(_batchesQueue.getBoundaryUnstETHId(), _DEFAULT_BOUNDARY_UNST_ETH_ID);

        _batchesQueue.close();
        assertEq(_batchesQueue.getBoundaryUnstETHId(), _DEFAULT_BOUNDARY_UNST_ETH_ID);
    }

    function test_getBoundaryUnstETHId_RevertOn_QueueInAbsentState() external {
        vm.expectRevert(WithdrawalsBatchesQueue.WithdrawalBatchesQueueIsInAbsentState.selector);
        _batchesQueue.getBoundaryUnstETHId();
    }

    // ---
    // getTotalUnstETHIdsCount()
    // ---

    function test_getTotalUnstETHIdsCount_HappyPath() external {
        assertEq(_batchesQueue.getTotalUnstETHIdsCount(), 0);

        _openBatchesQueue();
        assertEq(_batchesQueue.getTotalUnstETHIdsCount(), 0);

        uint256 unstETHIdsCount = 5;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});
        _batchesQueue.addUnstETHIds(unstETHIds);
        assertEq(_batchesQueue.getTotalUnstETHIdsCount(), 5);

        _batchesQueue.close();
        assertEq(_batchesQueue.getTotalUnstETHIdsCount(), 5);
    }

    // ---
    // getLastClaimedOrBoundaryUnstETHId()
    // ---

    function test_getLastClaimedOrBoundaryUnstETHId_HappyPath_EmptyQueueReturnsBoundaryUnstETHId() external {
        _openBatchesQueue();
        assertEq(_batchesQueue.getLastClaimedOrBoundaryUnstETHId(), _DEFAULT_BOUNDARY_UNST_ETH_ID);
    }

    function test_getLastClaimedOrBoundaryUnstETHId_HappyPath_NotEmptyQueueReturnsLastClaimedUnstETHId() external {
        _openBatchesQueue();
        uint256 unstETHIdsCount = 5;
        uint256 firstUnstETHId = _DEFAULT_BOUNDARY_UNST_ETH_ID + 1;
        uint256[] memory unstETHIds = _generateFakeUnstETHIds({length: unstETHIdsCount, firstUnstETHId: firstUnstETHId});
        _batchesQueue.addUnstETHIds(unstETHIds);
        assertEq(_batchesQueue.getTotalUnstETHIdsCount(), 5);

        assertEq(_batchesQueue.getLastClaimedOrBoundaryUnstETHId(), _DEFAULT_BOUNDARY_UNST_ETH_ID);

        uint256 maxUnstETHIdsCount = 3;
        _batchesQueue.claimNextBatch(maxUnstETHIdsCount);
        assertEq(_batchesQueue.getLastClaimedOrBoundaryUnstETHId(), unstETHIds[2]);

        _batchesQueue.claimNextBatch(maxUnstETHIdsCount);
        assertEq(_batchesQueue.getLastClaimedOrBoundaryUnstETHId(), unstETHIds[unstETHIds.length - 1]);
    }

    function test_getLastClaimedOrBoundaryUnstETHId_RevertOn_AbsentQueueState() external {
        vm.expectRevert(WithdrawalsBatchesQueue.WithdrawalBatchesQueueIsInAbsentState.selector);
        _batchesQueue.getLastClaimedOrBoundaryUnstETHId();
    }

    // ---
    // isClosed()
    // ---

    function test_isClosed_HappyPath() external {
        assertEq(_batchesQueue.isClosed(), false);

        _openBatchesQueue();
        assertEq(_batchesQueue.isClosed(), false);

        _batchesQueue.close();
        assertEq(_batchesQueue.isClosed(), true);
    }

    // ---
    // Helper Methods
    // ---

    function _openBatchesQueue() internal {
        _openBatchesQueue(_DEFAULT_BOUNDARY_UNST_ETH_ID);
    }

    function _openBatchesQueue(uint256 seedUnstETHId) internal {
        _batchesQueue.open(seedUnstETHId);
        assertEq(_batchesQueue.batches.length, 1);
        assertEq(_batchesQueue.info.state, State.Opened);
    }

    function _generateFakeUnstETHIds(uint256 length, uint256 firstUnstETHId) internal returns (uint256[] memory res) {
        res = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            res[i] = firstUnstETHId + i;
        }
    }

    function assertEq(State a, State b) internal {
        assertEq(uint256(a), uint256(b));
    }
}
