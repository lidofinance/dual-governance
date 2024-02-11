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

        uint256 totalSuply = IERC20(ST_ETH).totalSupply();
        uint256 clBalance = uint256(vm.load(ST_ETH, CL_BALANCE_POSITION));

        int256 delta = (deltaBP * int256(totalSuply) / 10000);
        vm.store(ST_ETH, CL_BALANCE_POSITION, bytes32(uint256(int256(clBalance) + delta)));

        assertEq(
            uint256(int256(totalSuply) * deltaBP / 10000 + int256(totalSuply)),
            IERC20(ST_ETH).totalSupply(),
            "total supply"
        );
    }
}

contract EscrowHappyPath is TestHelpers {
    Escrow internal escrow;
    BurnerVault internal burnerVault;

    address internal stEthHolder1;
    address internal stEthHolder2;

    function assertEq(Escrow.Balance memory a, Escrow.Balance memory b) internal {
        assertApproxEqAbs(a.stEth, b.stEth, 2, "StEth balance missmatched");
        assertApproxEqAbs(a.wstEth, b.wstEth, 2, "WstEth balance missmatched");
        assertEq(a.wqRequestsBalance, b.wqRequestsBalance, "WQ requests balance missmatched");
        assertEq(
            a.finalizedWqRequestsBalance, b.finalizedWqRequestsBalance, "Finilized WQ requests balance missmatched"
        );
    }

    function setUp() external {
        Utils.selectFork();
        Utils.removeLidoStakingLimit();

        TransparentUpgradeableProxy config;
        (, config,) = deployConfig(DAO_VOTING);

        (escrow, burnerVault) = deployEscrowImplementation(ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER, address(config));

        GovernanceState__mock govState = new GovernanceState__mock();

        escrow.initialize(address(govState));

        stEthHolder1 = makeAddr("steth_holder_1");
        Utils.setupStEthWhale(stEthHolder1);

        vm.startPrank(stEthHolder1);
        IERC20(ST_ETH).approve(WST_ETH, 1e30);

        IWstETH(WST_ETH).wrap(1e20);

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

        IWstETH(WST_ETH).wrap(1e20);

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
        uint256[] memory ids = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawalsWstETH(amounts, stEthHolder1);

        lockAssets(stEthHolder1, 0, 0, ids);

        unlockAssets(stEthHolder1, false, false, ids);
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
                balanceBefore.finalizedWqRequestsBalance
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
                balanceBefore.finalizedWqRequestsBalance
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
