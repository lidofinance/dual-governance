// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";
import {Configuration} from "contracts/Configuration.sol";

import {Escrow} from "contracts/Escrow.sol";
import {BurnerVault} from "contracts/BurnerVault.sol";

import "forge-std/Test.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/utils.sol";

import {DualGovernanceSetup} from "./setup.sol";

contract TestHelpers is DualGovernanceSetup {
    function rebase(int256 deltaBP) public {
        bytes32 CL_BALANCE_POSITION = 0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483; // keccak256("lido.Lido.beaconBalance");

        uint256 totalSupply = IERC20(ST_ETH).totalSupply();
        uint256 clBalance = uint256(vm.load(ST_ETH, CL_BALANCE_POSITION));

        int256 delta = (deltaBP * int256(totalSupply) / 10000);
        vm.store(ST_ETH, CL_BALANCE_POSITION, bytes32(uint256(int256(clBalance) + delta)));

        assertEq(
            uint256(int256(totalSupply) * deltaBP / 10000 + int256(totalSupply)),
            IERC20(ST_ETH).totalSupply(),
            "total supply"
        );
    }

    function finalizeWQ() public {
        uint256 lastRequestId = IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastRequestId();
        finalizeWQ(lastRequestId);
    }

    function finalizeWQ(uint256 id) public {
        uint256 finalizationShareRate = IStEth(ST_ETH).getPooledEthByShares(1e27) + 1e9; // TODO check finalization rate
        address lido = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        vm.prank(lido);
        IWithdrawalQueue(WITHDRAWAL_QUEUE).finalize(id, finalizationShareRate);

        bytes32 LOCKED_ETHER_AMOUNT_POSITION = 0x0e27eaa2e71c8572ab988fef0b54cd45bbd1740de1e22343fb6cda7536edc12f; // keccak256("lido.WithdrawalQueue.lockedEtherAmount");

        vm.store(WITHDRAWAL_QUEUE, LOCKED_ETHER_AMOUNT_POSITION, bytes32(address(WITHDRAWAL_QUEUE).balance));
    }
}

contract EscrowHappyPath is TestHelpers {
    Escrow internal escrow;
    BurnerVault internal burnerVault;
    GovernanceState__mock internal govState;

    address internal stEthHolder1;
    address internal stEthHolder2;

    address internal proxyAdmin = makeAddr("proxy_admin");

    function assertEq(Escrow.Balance memory a, Escrow.Balance memory b) internal {
        assertApproxEqAbs(a.stEth, b.stEth, 2, "StEth balance missmatched");
        assertApproxEqAbs(a.wstEth, b.wstEth, 2, "WstEth balance missmatched");
        assertEq(a.wqRequestsBalance, b.wqRequestsBalance, "WQ requests balance missmatched");
        assertEq(
            a.finalizedWqRequestsBalance, b.finalizedWqRequestsBalance, "Finalized WQ requests balance missmatched"
        );
    }

    function setUp() external {
        Utils.selectFork();
        Utils.removeLidoStakingLimit();

        TransparentUpgradeableProxy config;
        (, config,) = deployConfig(DAO_VOTING);

        Escrow escrowImpl;
        (escrowImpl, burnerVault) =
            deployEscrowImplementation(ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER, address(config));

        escrow =
            Escrow(payable(address(new TransparentUpgradeableProxy(address(escrowImpl), proxyAdmin, new bytes(0)))));

        govState = new GovernanceState__mock();

        escrow.initialize(address(govState));

        stEthHolder1 = makeAddr("steth_holder_1");
        Utils.setupStEthWhale(stEthHolder1);

        vm.startPrank(stEthHolder1);
        IERC20(ST_ETH).approve(WST_ETH, 1e30);

        IWstETH(WST_ETH).wrap(1e24);

        IERC20(ST_ETH).approve(address(escrow), 1e30);
        IERC20(WST_ETH).approve(address(escrow), 1e30);
        IERC20(WST_ETH).approve(address(WITHDRAWAL_QUEUE), 1e30);
        IERC20(ST_ETH).approve(address(WITHDRAWAL_QUEUE), 1e30);
        IWithdrawalQueue(WITHDRAWAL_QUEUE).setApprovalForAll(address(escrow), true);
        vm.stopPrank();

        stEthHolder2 = makeAddr("steth_holder_2");
        Utils.setupStEthWhale(stEthHolder2);

        vm.startPrank(stEthHolder2);
        IERC20(ST_ETH).approve(WST_ETH, 1e30);

        IWstETH(WST_ETH).wrap(1e24);

        IERC20(ST_ETH).approve(address(escrow), 1e30);
        IERC20(WST_ETH).approve(address(escrow), 1e30);
        IERC20(WST_ETH).approve(address(WITHDRAWAL_QUEUE), 1e30);
        IERC20(ST_ETH).approve(address(WITHDRAWAL_QUEUE), 1e30);
        IWithdrawalQueue(WITHDRAWAL_QUEUE).setApprovalForAll(address(escrow), true);
        vm.stopPrank();
    }

    function test_lock_unlock() public {
        uint256 amountToLock = 1e18;
        uint256 wstEthAmountToLock = IStEth(ST_ETH).getSharesByPooledEth(amountToLock);

        uint256 stEthBalanceBefore1 = IERC20(ST_ETH).balanceOf(stEthHolder1);
        uint256 wstEthBalanceBefore1 = IERC20(WST_ETH).balanceOf(stEthHolder1);
        uint256 stEthBalanceBefore2 = IERC20(ST_ETH).balanceOf(stEthHolder2);
        uint256 wstEthBalanceBefore2 = IERC20(WST_ETH).balanceOf(stEthHolder2);

        lockAssets(stEthHolder1, amountToLock, wstEthAmountToLock, new uint256[](0));
        lockAssets(stEthHolder2, 2 * amountToLock, 2 * wstEthAmountToLock, new uint256[](0));

        unlockAssets(stEthHolder1, true, true, new uint256[](0));
        unlockAssets(stEthHolder2, true, true, new uint256[](0));

        assertApproxEqAbs(IERC20(ST_ETH).balanceOf(stEthHolder1), stEthBalanceBefore1, 3);
        assertApproxEqAbs(IERC20(WST_ETH).balanceOf(stEthHolder1), wstEthBalanceBefore1, 3);
        assertApproxEqAbs(IERC20(ST_ETH).balanceOf(stEthHolder2), stEthBalanceBefore2, 3);
        assertApproxEqAbs(IERC20(WST_ETH).balanceOf(stEthHolder2), wstEthBalanceBefore2, 3);
    }

    function test_lock_unlock_w_rebase() public {
        uint256 amountToLock = 1e18;
        uint256 wstEthAmountToLock = IStEth(ST_ETH).getSharesByPooledEth(amountToLock);

        lockAssets(stEthHolder1, amountToLock, wstEthAmountToLock, new uint256[](0));
        lockAssets(stEthHolder2, 2 * amountToLock, 2 * wstEthAmountToLock, new uint256[](0));

        rebase(100);

        uint256 wstEthAmountToUnlock = IStEth(ST_ETH).getSharesByPooledEth(amountToLock);

        uint256 stEthBalanceBefore1 = IERC20(ST_ETH).balanceOf(stEthHolder1);
        uint256 wstEthBalanceBefore1 = IERC20(WST_ETH).balanceOf(stEthHolder1);
        uint256 stEthBalanceBefore2 = IERC20(ST_ETH).balanceOf(stEthHolder2);
        uint256 wstEthBalanceBefore2 = IERC20(WST_ETH).balanceOf(stEthHolder2);

        unlockAssets(stEthHolder1, true, true, new uint256[](0));
        unlockAssets(stEthHolder2, true, true, new uint256[](0));

        assertApproxEqAbs(IERC20(ST_ETH).balanceOf(stEthHolder1), stEthBalanceBefore1 + amountToLock, 3);
        assertApproxEqAbs(IERC20(WST_ETH).balanceOf(stEthHolder1), wstEthBalanceBefore1 + wstEthAmountToUnlock, 3);
        assertApproxEqAbs(IERC20(ST_ETH).balanceOf(stEthHolder2), stEthBalanceBefore2 + 2 * amountToLock, 3);
        assertApproxEqAbs(IERC20(WST_ETH).balanceOf(stEthHolder2), wstEthBalanceBefore2 + 2 * wstEthAmountToUnlock, 3);
    }

    function test_lock_unlock_w_negative_rebase() public {
        int256 rebaseBP = -100;
        uint256 amountToLock = 1e18;
        uint256 wstEthAmountToLock = IStEth(ST_ETH).getSharesByPooledEth(amountToLock);

        uint256 stEthBalanceBefore1 = IERC20(ST_ETH).balanceOf(stEthHolder1);
        uint256 wstEthBalanceBefore1 = IERC20(WST_ETH).balanceOf(stEthHolder1);
        uint256 stEthBalanceBefore2 = IERC20(ST_ETH).balanceOf(stEthHolder2);
        uint256 wstEthBalanceBefore2 = IERC20(WST_ETH).balanceOf(stEthHolder2);

        lockAssets(stEthHolder1, amountToLock, wstEthAmountToLock, new uint256[](0));
        lockAssets(stEthHolder2, 2 * amountToLock, 2 * wstEthAmountToLock, new uint256[](0));

        rebase(rebaseBP);
        escrow.burnRewards();

        unlockAssets(stEthHolder1, true, true, new uint256[](0));
        unlockAssets(stEthHolder2, true, true, new uint256[](0));

        assertApproxEqAbs(IERC20(ST_ETH).balanceOf(stEthHolder1), stEthBalanceBefore1 * 9900 / 10000, 3);
        assertApproxEqAbs(IERC20(WST_ETH).balanceOf(stEthHolder1), wstEthBalanceBefore1, 3);
        assertApproxEqAbs(IERC20(ST_ETH).balanceOf(stEthHolder2), stEthBalanceBefore2 * 9900 / 10000, 3);
        assertApproxEqAbs(IERC20(WST_ETH).balanceOf(stEthHolder2), wstEthBalanceBefore2, 3);
    }

    function test_lock_unlock_withdrawal_nfts() public {
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(stEthHolder1);
        uint256[] memory ids = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, stEthHolder1);

        lockAssets(stEthHolder1, 0, 0, ids);

        unlockAssets(stEthHolder1, false, false, ids);
    }

    function test_lock_withdrawal_nfts_reverts_on_finalized() public {
        uint256[] memory amounts = new uint256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(stEthHolder1);
        uint256[] memory ids = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, stEthHolder1);

        finalizeWQ();

        vm.prank(stEthHolder1);
        vm.expectRevert();
        escrow.lockWithdrawalNFT(ids);
    }

    function test_check_finalization() public {
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(stEthHolder1);
        uint256[] memory ids = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, stEthHolder1);

        lockAssets(stEthHolder1, 0, 0, ids);

        Escrow.Balance memory balance = escrow.balanceOf(stEthHolder1);
        assertEq(balance.wqRequestsBalance, 2 * 1e18);
        assertEq(balance.finalizedWqRequestsBalance, 0);

        finalizeWQ(ids[0]);
        escrow.checkForFinalization(ids);

        balance = escrow.balanceOf(stEthHolder1);
        assertEq(balance.wqRequestsBalance, 1e18);
        assertEq(balance.finalizedWqRequestsBalance, 1e18);
    }

    function test_get_signaling_state() public {
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        uint256 totalSupply = IERC20(ST_ETH).totalSupply();

        vm.prank(stEthHolder1);
        uint256[] memory ids = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, stEthHolder1);

        lockAssets(stEthHolder1, 1e18, IStEth(ST_ETH).getSharesByPooledEth(1e18), ids);

        Escrow.Balance memory balance = escrow.balanceOf(stEthHolder1);
        assertEq(balance.wqRequestsBalance, 2 * 1e18);
        assertEq(balance.finalizedWqRequestsBalance, 0);

        (uint256 totalSupport, uint256 rageQuitSupport) = escrow.getSignallingState();
        assertEq(totalSupport, 4 * 1e18 * 1e18 / totalSupply);
        assertEq(rageQuitSupport, 4 * 1e18 * 1e18 / totalSupply);

        finalizeWQ(ids[0]);
        escrow.checkForFinalization(ids);

        balance = escrow.balanceOf(stEthHolder1);
        assertEq(balance.wqRequestsBalance, 1e18);
        assertEq(balance.finalizedWqRequestsBalance, 1e18);

        (totalSupport, rageQuitSupport) = escrow.getSignallingState();
        assertEq(totalSupport, 4 * 1e18 * 1e18 / totalSupply);
        assertEq(rageQuitSupport, 3 * 1e18 * 1e18 / totalSupply);
    }

    function test_rage_quit() public {
        uint256 requestAmount = 1000 * 1e18;
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            amounts[i] = requestAmount;
        }

        vm.prank(stEthHolder1);
        uint256[] memory ids = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, stEthHolder1);

        lockAssets(stEthHolder1, 20 * requestAmount, IStEth(ST_ETH).getSharesByPooledEth(20 * requestAmount), ids);

        rebase(100);

        vm.expectRevert();
        escrow.startRageQuit();

        vm.prank(address(govState));
        escrow.startRageQuit();

        assertEq(IWithdrawalQueue(WITHDRAWAL_QUEUE).balanceOf(address(escrow)), 10);

        escrow.requestNextWithdrawalsBatch(10);

        assertEq(IWithdrawalQueue(WITHDRAWAL_QUEUE).balanceOf(address(escrow)), 20);

        escrow.requestNextWithdrawalsBatch(200);

        assertEq(IWithdrawalQueue(WITHDRAWAL_QUEUE).balanceOf(address(escrow)), 50);
        assertEq(escrow.isRageQuitFinalized(), false);

        vm.deal(WITHDRAWAL_QUEUE, 1000 * requestAmount);
        finalizeWQ();

        uint256[] memory hints = IWithdrawalQueue(WITHDRAWAL_QUEUE).findCheckpointHints(
            ids,
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastCheckpointIndex() - 2,
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastCheckpointIndex()
        );

        escrow.claimWithdrawalRequests(ids, hints);

        assertEq(escrow.isRageQuitFinalized(), true);

        vm.expectRevert();
        vm.prank(stEthHolder1);
        escrow.claimETH();

        uint256[] memory escrowRequestIds = new uint256[](40);
        for (uint256 i = 0; i < 40; ++i) {
            escrowRequestIds[i] = ids[9] + i + 1;
        }

        uint256[] memory escrowRequestHints = IWithdrawalQueue(WITHDRAWAL_QUEUE).findCheckpointHints(
            escrowRequestIds,
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastCheckpointIndex() - 2,
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastCheckpointIndex()
        );

        vm.expectRevert();
        vm.prank(stEthHolder1);
        escrow.claimETH();

        escrow.claimNextETHBatch(escrowRequestIds, escrowRequestHints);

        vm.prank(stEthHolder1);
        escrow.claimETH();
    }

    function test_wq_requests_only_happy_path() public {
        uint256 requestAmount = 10 * 1e18;
        uint256 requestsCount = 10;
        uint256[] memory amounts = new uint256[](requestsCount);
        for (uint256 i = 0; i < requestsCount; ++i) {
            amounts[i] = requestAmount;
        }

        vm.prank(stEthHolder1);
        uint256[] memory ids = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, stEthHolder1);

        lockAssets(stEthHolder1, 0, 0, ids);

        vm.prank(address(govState));
        escrow.startRageQuit();

        vm.deal(WITHDRAWAL_QUEUE, 100 * requestAmount);
        finalizeWQ();

        uint256[] memory hints = IWithdrawalQueue(WITHDRAWAL_QUEUE).findCheckpointHints(
            ids,
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastCheckpointIndex() - 2,
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastCheckpointIndex()
        );

        escrow.claimWithdrawalRequests(ids, hints);

        assertEq(escrow.isRageQuitFinalized(), true);

        vm.prank(stEthHolder1);
        escrow.claimETH();
    }

    function lockAssets(
        address owner,
        uint256 stEthAmountToLock,
        uint256 wstEthAmountToLock,
        uint256[] memory wqRequestIds
    ) public {
        vm.startPrank(owner);

        Escrow.Balance memory balanceBefore = escrow.balanceOf(owner);
        uint256 stEthBalanceBefore = IERC20(ST_ETH).balanceOf(owner);
        uint256 wstEthBalanceBefore = IERC20(WST_ETH).balanceOf(owner);
        if (stEthAmountToLock > 0) {
            escrow.lockStEth(stEthAmountToLock);
        }
        if (wstEthAmountToLock > 0) {
            escrow.lockWstEth(wstEthAmountToLock);
        }

        uint256 wqRequestsAmount = 0;
        if (wqRequestIds.length > 0) {
            WithdrawalRequestStatus[] memory statuses =
                IWithdrawalQueue(WITHDRAWAL_QUEUE).getWithdrawalStatus(wqRequestIds);

            for (uint256 i = 0; i < wqRequestIds.length; ++i) {
                assertEq(statuses[i].isFinalized, false);
                wqRequestsAmount += statuses[i].amountOfStETH;
            }

            escrow.lockWithdrawalNFT(wqRequestIds);
        }

        assertEq(
            escrow.balanceOf(owner),
            Escrow.Balance(
                balanceBefore.stEth + stEthAmountToLock,
                balanceBefore.wstEth + wstEthAmountToLock,
                balanceBefore.wqRequestsBalance + wqRequestsAmount,
                balanceBefore.finalizedWqRequestsBalance,
                0,
                new uint256[](0)
            )
        );

        assertApproxEqAbs(IERC20(ST_ETH).balanceOf(owner), stEthBalanceBefore - stEthAmountToLock, 3);
        assertEq(IERC20(WST_ETH).balanceOf(owner), wstEthBalanceBefore - wstEthAmountToLock);

        vm.stopPrank();
    }

    function unlockAssets(address owner, bool unlockStEth, bool unlockWstEth, uint256[] memory wqRequestIds) public {
        unlockAssets(owner, unlockStEth, unlockWstEth, wqRequestIds, 0);
    }

    function unlockAssets(
        address owner,
        bool unlockStEth,
        bool unlockWstEth,
        uint256[] memory wqRequestIds,
        int256 rebaseBP
    ) public {
        vm.startPrank(owner);

        Escrow.Balance memory balanceBefore = escrow.balanceOf(owner);
        uint256 stEthBalanceBefore = IERC20(ST_ETH).balanceOf(owner);
        uint256 wstEthBalanceBefore = IERC20(WST_ETH).balanceOf(owner);

        if (unlockStEth) {
            escrow.unlockStEth();
        }
        if (unlockWstEth) {
            escrow.unlockWstEth();
        }

        uint256 wqRequestsAmount = 0;
        if (wqRequestIds.length > 0) {
            WithdrawalRequestStatus[] memory statuses =
                IWithdrawalQueue(WITHDRAWAL_QUEUE).getWithdrawalStatus(wqRequestIds);

            for (uint256 i = 0; i < wqRequestIds.length; ++i) {
                assertEq(statuses[i].owner, address(escrow));
                wqRequestsAmount += statuses[i].amountOfStETH;
            }

            escrow.unlockWithdrawalNFT(wqRequestIds);
        }

        assertEq(
            escrow.balanceOf(owner),
            Escrow.Balance(
                unlockStEth ? 0 : balanceBefore.stEth,
                unlockWstEth ? 0 : balanceBefore.wstEth,
                balanceBefore.wqRequestsBalance - wqRequestsAmount,
                balanceBefore.finalizedWqRequestsBalance,
                0,
                new uint256[](0)
            )
        );

        uint256 expectedStEthAmount = uint256(int256(balanceBefore.stEth) * (10000 + rebaseBP) / 10000);
        uint256 expectedWstEthAmount = uint256(int256(balanceBefore.wstEth) * (10000 + rebaseBP) / 10000);

        assertApproxEqAbs(IERC20(ST_ETH).balanceOf(owner), stEthBalanceBefore + expectedStEthAmount, 3);
        assertApproxEqAbs(IERC20(WST_ETH).balanceOf(owner), wstEthBalanceBefore + expectedWstEthAmount, 3);

        vm.stopPrank();
    }
}

contract GovernanceState__mock {
    enum State {
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
        RageQuitAccumulation,
        RageQuit
    }

    State public state = State.Normal;

    function setState(State _nextState) public {
        state = _nextState;
    }

    function activateNextState() public returns (State) {
        return state;
    }
}
