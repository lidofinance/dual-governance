// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PercentD16, PercentsD16, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IBurner} from "./interfaces/IBurner.sol";
import {IHashConsensus} from "./interfaces/IHashConsensus.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";
import {IAccountingOracle} from "./interfaces/IAccountingOracle.sol";
import {IOracleReportSanityChecker} from "./interfaces/IOracleReportSanityChecker.sol";
import {IStakingRouter} from "./interfaces/IStakingRouter.sol";
import {ILidoLocator} from "./interfaces/ILidoLocator.sol";
import {IAccounting} from "./interfaces/IAccounting.sol";

import {IAragonACL} from "./interfaces/IAragonACL.sol";
import {IAragonAgent} from "./interfaces/IAragonAgent.sol";
import {IAragonVoting} from "./interfaces/IAragonVoting.sol";
import {IAragonForwarder} from "./interfaces/IAragonForwarder.sol";

import {CallsScriptBuilder} from "scripts/utils/CallsScriptBuilder.sol";
import {DecimalsFormatting} from "test/utils/formatting.sol";

import {Uint256ArrayBuilder} from "test/utils/uint256-array-builder.sol";

// ---
// Mainnet Addresses
// ---

address constant MAINNET_LIDO_LOCATOR = 0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb;
address constant MAINNET_ST_ETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
address constant MAINNET_WST_ETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant MAINNET_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
address constant MAINNET_HASH_CONSENSUS = 0xD624B08C83bAECF0807Dd2c6880C3154a5F0B288;
address constant MAINNET_BURNER = 0xE76c52750019b80B43E36DF30bf4060EB73F573a;
address constant MAINNET_EL_REWARDS_VAULT = 0x388C818CA8B9251b393131C08a736A67ccB19297;
address constant MAINNET_WITHDRAWAL_VAULT = 0xB9D7934878B5FB9610B3fE8A5e441e8fad7E293f;
address constant MAINNET_STAKING_ROUTER = 0xFdDf38947aFB03C621C71b06C9C70bce73f12999;
address constant MAINNET_VEBO = 0x0De4Ea0184c2ad0BacA7183356Aea5B8d5Bf5c6e;

address constant MAINNET_DAO_ACL = 0x9895F0F17cc1d1891b6f18ee0b483B6f221b37Bb;
address constant MAINNET_LDO_TOKEN = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
address constant MAINNET_DAO_AGENT = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
address constant MAINNET_DAO_VOTING = 0x2e59A20f205bB85a89C53f1936454680651E618e;
address constant MAINNET_DAO_TOKEN_MANAGER = 0xf73a1260d222f447210581DDf212D915c09a3249;

address constant MAINNET_DISCONNECTED_ESCROW = 0xA8F14D033f377779274Ae016584a05bF14Dccaf8;
address constant MAINNET_DISCONNECTED_DUAL_GOVERNANCE = 0xcdF49b058D606AD34c5789FD8c3BF8B3E54bA2db;

// ---
// Holesky Addresses
// ---

address constant HOLESKY_LIDO_LOCATOR = 0x28FAB2059C713A7F9D8c86Db49f9bb0e96Af1ef8;
address constant HOLESKY_ST_ETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
address constant HOLESKY_WST_ETH = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
address constant HOLESKY_WITHDRAWAL_QUEUE = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
address constant HOLESKY_HASH_CONSENSUS = 0xa067FC95c22D51c3bC35fd4BE37414Ee8cc890d2;
address constant HOLESKY_BURNER = 0x4E46BD7147ccf666E1d73A3A456fC7a68de82eCA;
address constant HOLESKY_EL_REWARDS_VAULT = 0xE73a3602b99f1f913e72F8bdcBC235e206794Ac8;
address constant HOLESKY_WITHDRAWAL_VAULT = 0xF0179dEC45a37423EAD4FaD5fCb136197872EAd9;
address constant HOLESKY_STAKING_ROUTER = 0xd6EbF043D30A7fe46D1Db32BA90a0A51207FE229;
address constant HOLESKY_VEBO = 0xffDDF7025410412deaa05E3E1cE68FE53208afcb;

address constant HOLESKY_DAO_ACL = 0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC;
address constant HOLESKY_LDO_TOKEN = 0x14ae7daeecdf57034f3E9db8564e46Dba8D97344;
address constant HOLESKY_DAO_AGENT = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d;
address constant HOLESKY_DAO_VOTING = 0xdA7d2573Df555002503F29aA4003e398d28cc00f;
address constant HOLESKY_DAO_TOKEN_MANAGER = 0xFaa1692c6eea8eeF534e7819749aD93a1420379A;

// ---
// Hoodi Addresses
// ---

address constant HOODI_LIDO_LOCATOR = 0xe2EF9536DAAAEBFf5b1c130957AB3E80056b06D8;
address constant HOODI_ST_ETH = 0x3508A952176b3c15387C97BE809eaffB1982176a;
address constant HOODI_WST_ETH = 0x7E99eE3C66636DE415D2d7C880938F2f40f94De4;
address constant HOODI_WITHDRAWAL_QUEUE = 0xfe56573178f1bcdf53F01A6E9977670dcBBD9186;
address constant HOODI_HASH_CONSENSUS = 0x32EC59a78abaca3f91527aeB2008925D5AaC1eFC;
address constant HOODI_BURNER = 0xb2c99cd38a2636a6281a849C8de938B3eF4A7C3D;
address constant HOODI_EL_REWARDS_VAULT = 0x9b108015fe433F173696Af3Aa0CF7CDb3E104258;
address constant HOODI_WITHDRAWAL_VAULT = 0x4473dCDDbf77679A643BdB654dbd86D67F8d32f2;
address constant HOODI_STAKING_ROUTER = 0xCc820558B39ee15C7C45B59390B503b83fb499A8;
address constant HOODI_VEBO = 0x8664d394C2B3278F26A1B44B967aEf99707eeAB2;

address constant HOODI_DAO_ACL = 0x78780e70Eae33e2935814a327f7dB6c01136cc62;
address constant HOODI_LDO_TOKEN = 0xEf2573966D009CcEA0Fc74451dee2193564198dc;
address constant HOODI_DAO_AGENT = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD;
address constant HOODI_DAO_VOTING = 0x49B3512c44891bef83F8967d075121Bd1b07a01B;
address constant HOODI_DAO_TOKEN_MANAGER = 0x8ab4a56721Ad8e68c6Ad86F9D9929782A78E39E5;

// ---
// SRV3 Storage Slots
// ---

bytes32 constant CL_VALIDATORS_BALANCE_AND_CL_PENDING_BALANCE_SLOT =
    keccak256("lido.Lido.clValidatorsBalanceAndClPendingBalance");
bytes32 constant BUFFERED_ETHER_AND_DEPOSITED_POST_REPORT_SLOT =
    keccak256("lido.Lido.bufferedEtherAndDepositedPostReport");
bytes32 constant SANITY_CHECKER_LAST_VAULT_BALANCE_AFTER_TRANSFER_SLOT = bytes32(uint256(4));

library LidoUtils {
    using DecimalsFormatting for uint256;
    using DecimalsFormatting for PercentD16;
    using CallsScriptBuilder for CallsScriptBuilder.Context;
    using Uint256ArrayBuilder for Uint256ArrayBuilder.Context;

    uint256 internal constant MAX_REQUESTS_PER_CALL = 1000;
    uint256 internal constant UINT128_LOW_MASK = ~uint128(0);
    uint256 internal constant UINT128_HIGH_MASK = ~uint256(0) << 128;

    struct Context {
        // core
        ILidoLocator lidoLocator;
        IStETH stETH;
        IWstETH wstETH;
        IBurner burner;
        IHashConsensus hashConsensus;
        IWithdrawalQueue withdrawalQueue;
        address vebo;
        IAccountingOracle accountingOracle;
        IOracleReportSanityChecker oracleReportSanityChecker;
        address elRewardsVault;
        address withdrawalVault;
        IStakingRouter stakingRouter;
        // aragon governance
        IAragonACL acl;
        IERC20 ldoToken;
        IAragonAgent agent;
        IAragonVoting voting;
        IAragonForwarder tokenManager;
    }

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant DEFAULT_LDO_WHALE = address(0x1D01D01D01D01d01D01D01D01D01d01d01d01D01);

    function mainnet() internal view returns (Context memory ctx) {
        ctx.lidoLocator = ILidoLocator(MAINNET_LIDO_LOCATOR);
        ctx.stETH = IStETH(MAINNET_ST_ETH);
        ctx.wstETH = IWstETH(MAINNET_WST_ETH);
        ctx.burner = IBurner(MAINNET_BURNER);
        ctx.withdrawalQueue = IWithdrawalQueue(MAINNET_WITHDRAWAL_QUEUE);
        ctx.hashConsensus = IHashConsensus(MAINNET_HASH_CONSENSUS);
        ctx.accountingOracle = ctx.lidoLocator.accountingOracle();
        ctx.oracleReportSanityChecker = ctx.lidoLocator.oracleReportSanityChecker();
        ctx.stakingRouter = IStakingRouter(MAINNET_STAKING_ROUTER);
        ctx.vebo = MAINNET_VEBO;

        ctx.elRewardsVault = MAINNET_EL_REWARDS_VAULT;
        ctx.withdrawalVault = MAINNET_WITHDRAWAL_VAULT;

        ctx.acl = IAragonACL(MAINNET_DAO_ACL);
        ctx.agent = IAragonAgent(MAINNET_DAO_AGENT);
        ctx.voting = IAragonVoting(MAINNET_DAO_VOTING);
        ctx.ldoToken = IERC20(MAINNET_LDO_TOKEN);
        ctx.tokenManager = IAragonForwarder(MAINNET_DAO_TOKEN_MANAGER);
    }

    function holesky() internal view returns (Context memory ctx) {
        ctx.lidoLocator = ILidoLocator(HOLESKY_LIDO_LOCATOR);
        ctx.stETH = IStETH(HOLESKY_ST_ETH);
        ctx.wstETH = IWstETH(HOLESKY_WST_ETH);
        ctx.burner = IBurner(HOLESKY_BURNER);
        ctx.hashConsensus = IHashConsensus(HOLESKY_HASH_CONSENSUS);
        ctx.withdrawalQueue = IWithdrawalQueue(HOLESKY_WITHDRAWAL_QUEUE);
        ctx.accountingOracle = ctx.lidoLocator.accountingOracle();
        ctx.oracleReportSanityChecker = ctx.lidoLocator.oracleReportSanityChecker();
        ctx.stakingRouter = IStakingRouter(HOLESKY_STAKING_ROUTER);
        ctx.vebo = HOLESKY_VEBO;

        ctx.elRewardsVault = HOLESKY_EL_REWARDS_VAULT;
        ctx.withdrawalVault = HOLESKY_WITHDRAWAL_VAULT;

        ctx.acl = IAragonACL(HOLESKY_DAO_ACL);
        ctx.agent = IAragonAgent(HOLESKY_DAO_AGENT);
        ctx.voting = IAragonVoting(HOLESKY_DAO_VOTING);
        ctx.ldoToken = IERC20(HOLESKY_LDO_TOKEN);
        ctx.tokenManager = IAragonForwarder(HOLESKY_DAO_TOKEN_MANAGER);
    }

    function hoodi() internal view returns (Context memory ctx) {
        ctx.lidoLocator = ILidoLocator(HOODI_LIDO_LOCATOR);
        ctx.stETH = IStETH(HOODI_ST_ETH);
        ctx.wstETH = IWstETH(HOODI_WST_ETH);
        ctx.burner = IBurner(HOODI_BURNER);
        ctx.hashConsensus = IHashConsensus(HOODI_HASH_CONSENSUS);
        ctx.withdrawalQueue = IWithdrawalQueue(HOODI_WITHDRAWAL_QUEUE);
        ctx.accountingOracle = ctx.lidoLocator.accountingOracle();
        ctx.oracleReportSanityChecker = ctx.lidoLocator.oracleReportSanityChecker();
        ctx.stakingRouter = IStakingRouter(HOODI_STAKING_ROUTER);
        ctx.vebo = HOODI_VEBO;

        ctx.elRewardsVault = HOODI_EL_REWARDS_VAULT;
        ctx.withdrawalVault = HOODI_WITHDRAWAL_VAULT;

        ctx.acl = IAragonACL(HOODI_DAO_ACL);
        ctx.agent = IAragonAgent(HOODI_DAO_AGENT);
        ctx.voting = IAragonVoting(HOODI_DAO_VOTING);
        ctx.ldoToken = IERC20(HOODI_LDO_TOKEN);
        ctx.tokenManager = IAragonForwarder(HOODI_DAO_TOKEN_MANAGER);
    }

    struct DevnetDeploymentParams {
        address stEth;
        address wstETH;
        address burner;
        address hashConsensus;
        address withdrawalQueue;
        address accountingOracle;
        address oracleReportSanityChecker;
        address stakingRouter;
        address elRewardsVault;
        address withdrawalVault;
        address daoAcl;
        address daoAgent;
        address voting;
        address ldoToken;
        address daoTokenManager;
        address lidoLocator;
    }

    function devnetDeployment(DevnetDeploymentParams memory params) internal pure returns (Context memory ctx) {
        ctx.stETH = IStETH(params.stEth);
        ctx.wstETH = IWstETH(params.wstETH);
        ctx.burner = IBurner(params.burner);
        ctx.hashConsensus = IHashConsensus(params.hashConsensus);
        ctx.withdrawalQueue = IWithdrawalQueue(params.withdrawalQueue);
        ctx.accountingOracle = IAccountingOracle(params.accountingOracle);
        ctx.oracleReportSanityChecker = IOracleReportSanityChecker(params.oracleReportSanityChecker);
        ctx.stakingRouter = IStakingRouter(params.stakingRouter);
        ctx.lidoLocator = ILidoLocator(params.lidoLocator);

        ctx.elRewardsVault = params.elRewardsVault;
        ctx.withdrawalVault = params.withdrawalVault;

        ctx.acl = IAragonACL(params.daoAcl);
        ctx.agent = IAragonAgent(params.daoAgent);
        ctx.voting = IAragonVoting(params.voting);
        ctx.ldoToken = IERC20(params.ldoToken);
        ctx.tokenManager = IAragonForwarder(params.daoTokenManager);
    }

    function calcAmountFromPercentageOfTVL(Context memory self, PercentD16 percentage) internal view returns (uint256) {
        uint256 totalSupply = self.stETH.totalSupply();
        uint256 approximatedAmount =
            totalSupply * PercentD16.unwrap(percentage) / PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00));

        // Adjust for rounding issues
        while (
            self.stETH.getPooledEthByShares(self.stETH.getSharesByPooledEth(approximatedAmount))
                    * PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00)) / totalSupply
                < PercentD16.unwrap(percentage)
        ) {
            approximatedAmount++;
        }
        return approximatedAmount;
    }

    function calcSharesFromPercentageOfTVL(Context memory self, PercentD16 percentage) internal view returns (uint256) {
        uint256 totalShares = self.stETH.getTotalShares();
        uint256 shares =
            totalShares * PercentD16.unwrap(percentage) / PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00));

        // Adjust for rounding issues
        PercentD16 resulting = PercentsD16.fromFraction({numerator: shares, denominator: totalShares});
        return shares * PercentD16.unwrap(percentage) / PercentD16.unwrap(resulting);
    }

    function calcAmountToDepositFromPercentageOfTVL(
        Context memory self,
        PercentD16 percentage
    ) internal view returns (uint256) {
        uint256 totalSupply = self.stETH.totalSupply();
        // Calculate amount using: bal / (totalSupply + bal) = percentage => bal = totalSupply * percentage / (1 - percentage)
        uint256 amount = totalSupply * PercentD16.unwrap(percentage)
            / PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00) - percentage);

        // Adjust for rounding issues
        PercentD16 resulting = PercentsD16.fromFraction({numerator: amount, denominator: totalSupply + amount});
        return amount * PercentD16.unwrap(percentage) / PercentD16.unwrap(resulting);
    }

    function calcSharesToDepositFromPercentageOfTVL(
        Context memory self,
        PercentD16 percentage
    ) internal view returns (uint256) {
        uint256 totalShares = self.stETH.getTotalShares();
        // Calculate shares using: bal / (totalShares + bal) = percentage => bal = totalShares * percentage / (1 - percentage)
        uint256 shares = totalShares * PercentD16.unwrap(percentage)
            / PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00) - percentage);

        // Adjust for rounding issues
        PercentD16 resulting = PercentsD16.fromFraction({numerator: shares, denominator: totalShares + shares});
        return shares * PercentD16.unwrap(percentage) / PercentD16.unwrap(resulting);
    }

    function submitStETH(
        Context memory self,
        address account,
        uint256 balance
    ) internal returns (uint256 sharesMinted) {
        vm.deal(account, balance + 0.1 ether);

        vm.prank(account);
        sharesMinted = self.stETH.submit{value: balance}(address(0));
    }

    function submitWstETH(
        Context memory self,
        address account,
        uint256 balance
    ) internal returns (uint256 wstEthMinted) {
        uint256 stEthAmount = self.wstETH.getStETHByWstETH(balance);
        submitStETH(self, account, stEthAmount);

        vm.startPrank(account);
        self.stETH.approve(address(self.wstETH), stEthAmount);
        wstEthMinted = self.wstETH.wrap(stEthAmount);
        vm.stopPrank();
    }

    struct ReportTimeElapsed {
        uint256 time;
        uint256 timeElapsed;
        uint256 nextFrameStart;
        uint256 nextFrameStartWithOffset;
    }

    function getReportTimeElapsed(Context memory self) internal view returns (ReportTimeElapsed memory) {
        (uint256 slotsPerEpoch, uint256 secondsPerSlot, uint256 genesisTime) = self.hashConsensus.getChainConfig();
        (uint256 refSlot,) = self.hashConsensus.getCurrentFrame();
        (, uint256 epochsPerFrame,) = self.hashConsensus.getFrameConfig();
        uint256 time = block.timestamp;

        uint256 slotsPerFrame = slotsPerEpoch * epochsPerFrame;
        uint256 nextRefSlot = refSlot + slotsPerFrame;
        uint256 nextFrameStart = genesisTime + nextRefSlot * secondsPerSlot;

        // Add 10 slots to ensure the next frame starts
        uint256 nextFrameStartWithOffset = nextFrameStart + secondsPerSlot * 10;

        return ReportTimeElapsed({
            time: time,
            nextFrameStart: nextFrameStart,
            nextFrameStartWithOffset: nextFrameStartWithOffset,
            timeElapsed: nextFrameStartWithOffset - time
        });
    }

    function performRebase(Context memory self, PercentD16 rebaseFactor) internal {
        performRebase(self, rebaseFactor, self.withdrawalQueue.getLastFinalizedRequestId());
    }

    function performRebase(Context memory self, PercentD16 rebaseFactor, uint256 lastUnstETHIdToFinalize) internal {
        {
            uint256 lastRequestId = self.withdrawalQueue.getLastRequestId();
            if (lastUnstETHIdToFinalize > lastRequestId) {
                lastUnstETHIdToFinalize = lastRequestId;
            }
        }

        uint256 shareRateBefore = self.stETH.getPooledEthByShares(10 ** 27);
        uint256 targetShareRate = shareRateBefore * PercentD16.unwrap(rebaseFactor) / HUNDRED_PERCENT_D16;
        vm.startPrank(address(self.agent));
        self.oracleReportSanityChecker
            .grantRole(self.oracleReportSanityChecker.ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE(), address(self.agent));
        self.oracleReportSanityChecker
            .grantRole(self.oracleReportSanityChecker.REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE(), address(self.agent));
        self.oracleReportSanityChecker.setAnnualBalanceIncreaseBPLimit(100_00);
        self.oracleReportSanityChecker.setRequestTimestampMargin(0);
        vm.stopPrank();

        // Ignore EL rewards vault balance for test simplicity
        vm.deal(self.elRewardsVault, 0);
        // Ignore untracked withdrawals for test simplicity
        vm.deal(self.withdrawalVault, 0);
        vm.store(address(self.oracleReportSanityChecker), SANITY_CHECKER_LAST_VAULT_BALANCE_AFTER_TRANSFER_SLOT, 0);

        uint256 clBalance = _sweepBufferedEther(self);

        uint256 newCLBalance;
        {
            uint256 totalPooledEther = self.stETH.getTotalPooledEther();
            uint256 internalEther = totalPooledEther - self.stETH.getExternalEther();
            uint256 rebaseFactorValue = PercentD16.unwrap(rebaseFactor);

            if (rebaseFactorValue > HUNDRED_PERCENT_D16) {
                (uint256 modulesFee, uint256 treasuryFee, uint256 feeBasePrecision) =
                    self.stakingRouter.getStakingFeeAggregateDistribution();

                uint256 rebaseAmount = internalEther * (rebaseFactorValue - HUNDRED_PERCENT_D16) / HUNDRED_PERCENT_D16;
                uint256 grossRewards = rebaseAmount * feeBasePrecision / (feeBasePrecision - modulesFee - treasuryFee);

                newCLBalance = clBalance + grossRewards;
            } else if (rebaseFactorValue < HUNDRED_PERCENT_D16) {
                uint256 rebaseAmount = internalEther * (HUNDRED_PERCENT_D16 - rebaseFactorValue) / HUNDRED_PERCENT_D16;

                newCLBalance = clBalance - rebaseAmount;
            } else {
                newCLBalance = clBalance;
            }
        }

        _handleOracleReport(self, int256(newCLBalance) - int256(clBalance), lastUnstETHIdToFinalize, targetShareRate);

        vm.assertEq(
            self.withdrawalQueue.getLastFinalizedRequestId(),
            lastUnstETHIdToFinalize,
            "Unexpected last finalized request id"
        );
        PercentD16 rebaseRate;

        {
            uint256 shareRateAfter = self.stETH.getPooledEthByShares(10 ** 27);
            rebaseRate = PercentsD16.fromFraction(shareRateAfter, shareRateBefore);
        }
        // NOTE: tolerance of 10^12 out of 10^18 (~0.0001 basis points) accounts for integer rounding
        // in the fee gross-up calculation. Observed delta ~256 gwei on mainnet fork.
        uint256 actual = rebaseRate.toUint256();
        uint256 expected = rebaseFactor.toUint256();
        uint256 delta = actual > expected ? actual - expected : expected - actual;
        if (delta > 100 wei) {
            _logRebaseDeviation(self, rebaseRate, rebaseFactor, delta);
        }
        vm.assertApproxEqAbs(actual, expected, 1_000 gwei, "Rebase rate error is too high");
    }

    function _logRebaseDeviation(
        Context memory self,
        PercentD16 rebaseRate,
        PercentD16 rebaseFactor,
        uint256 delta
    ) internal view {
        console.log(
            "WARNING: rebase rate deviation: actual %s, expected %s, diff %s",
            rebaseRate.format(),
            rebaseFactor.format(),
            PercentsD16.from(delta).format()
        );
        uint256 externalEther = self.stETH.getExternalEther();
        uint256 totalPooledEther = self.stETH.getTotalPooledEther();
        console.log(
            "  externalEther: %s, internalEther: %s",
            externalEther.formatEther(),
            (totalPooledEther - externalEther).formatEther()
        );
        console.log(
            "  totalPooledEther: %s, totalShares: %s, externalShares: %s",
            totalPooledEther.formatEther(),
            self.stETH.getTotalShares().formatEther(),
            self.stETH.getSharesByPooledEth(externalEther).formatEther()
        );
    }

    function _sweepBufferedEther(Context memory self) internal returns (uint256 fullClBalance) {
        uint256 clValidatorsBalance =
            getLowUint128(address(self.stETH), CL_VALIDATORS_BALANCE_AND_CL_PENDING_BALANCE_SLOT);
        uint256 clPendingBalance =
            getHighUint128(address(self.stETH), CL_VALIDATORS_BALANCE_AND_CL_PENDING_BALANCE_SLOT);
        uint256 bufferedEther = getLowUint128(address(self.stETH), BUFFERED_ETHER_AND_DEPOSITED_POST_REPORT_SLOT);

        require(bufferedEther == address(self.stETH).balance, "Buffered Ether mismatch");

        fullClBalance = clValidatorsBalance + clPendingBalance;

        if (bufferedEther > 0) {
            vm.deal(address(self.stETH), 0);
            fullClBalance += bufferedEther;

            setLowUint128(
                address(self.stETH),
                CL_VALIDATORS_BALANCE_AND_CL_PENDING_BALANCE_SLOT,
                clValidatorsBalance + bufferedEther
            );
            setLowUint128(address(self.stETH), BUFFERED_ETHER_AND_DEPOSITED_POST_REPORT_SLOT, 0);

            (uint256 updatedClValidatorsBalance, uint256 updatedClPendingBalance,,) = self.stETH.getBalanceStats();
            require(updatedClValidatorsBalance + updatedClPendingBalance == fullClBalance, "Unexpected CL balance");
            require(self.stETH.getBufferedEther() == 0, "Non-zero buffered ether");
        }
    }

    function _handleOracleReport(
        Context memory self,
        int256 clBalanceChange,
        uint256 lastUnstETHIdToFinalize,
        uint256 targetShareRate
    ) internal {
        Uint256ArrayBuilder.Context memory withdrawalBatches;
        uint256 preClPendingBalance;
        uint256 reportClPendingBalance;
        uint256 newCLBalance;
        {
            (uint256 clValidatorsBalance, uint256 clPendingBalance,, uint256 depositedForCurrentReport) =
                self.stETH.getBalanceStats();
            preClPendingBalance = clPendingBalance;
            reportClPendingBalance = clPendingBalance + depositedForCurrentReport;
            newCLBalance = uint256(int256(clValidatorsBalance + clPendingBalance) + clBalanceChange);
        }

        if (lastUnstETHIdToFinalize > self.withdrawalQueue.getLastFinalizedRequestId()) {
            IWithdrawalQueue.BatchesCalculationState memory batchesState = getFinalizationBatches(
                self,
                FinalizationBatchesParams({
                    shareRate: targetShareRate,
                    limitedWithdrawalVaultBalance: newCLBalance,
                    limitedElRewardsVaultBalance: 0
                })
            );

            withdrawalBatches = Uint256ArrayBuilder.create(batchesState.batchesLength);
            for (uint256 i = 0; i < batchesState.batchesLength; ++i) {
                if (batchesState.batches[i] < lastUnstETHIdToFinalize) {
                    withdrawalBatches.addItem(batchesState.batches[i]);
                } else {
                    withdrawalBatches.addItem(lastUnstETHIdToFinalize);
                    break;
                }
            }

            vm.deal(self.withdrawalVault, newCLBalance);

            uint256 ethToCutFromCL;
            {
                IAccounting.CalculatedValues memory simulatedUpdate = self.lidoLocator.accounting()
                    .simulateOracleReport(
                        IAccounting.ReportValues({
                            timestamp: block.timestamp,
                            timeElapsed: 1 days,
                            clValidatorsBalance: 0,
                            clPendingBalance: 0,
                            withdrawalVaultBalance: self.withdrawalVault.balance,
                            elRewardsVaultBalance: self.elRewardsVault.balance,
                            sharesRequestedToBurn: 0,
                            withdrawalFinalizationBatches: withdrawalBatches.getResult(),
                            simulatedShareRate: targetShareRate
                        })
                    );

                ethToCutFromCL = (simulatedUpdate.sharesToBurnForWithdrawals * targetShareRate / 10 ** 27);

                if (targetShareRate > self.stETH.getPooledEthByShares(10 ** 27)) {
                    (uint256 modulesFee, uint256 treasuryFee, uint256 feeBasePrecision) =
                        self.stakingRouter.getStakingFeeAggregateDistribution();
                    ethToCutFromCL += (ethToCutFromCL - simulatedUpdate.etherToFinalizeWQ) * (modulesFee + treasuryFee)
                        / (feeBasePrecision - modulesFee - treasuryFee);
                }

                vm.deal(self.withdrawalVault, simulatedUpdate.etherToFinalizeWQ);
            }

            newCLBalance -= ethToCutFromCL;
        }

        // waiting 1 block time to avoid report timestamp and newly created withdrawal requests time collision
        vm.warp(block.timestamp + 12 seconds);

        _handleOracleReport(
            self,
            IAccounting.ReportValues({
                timestamp: block.timestamp - 1,
                timeElapsed: 1 days,
                clValidatorsBalance: newCLBalance - preClPendingBalance,
                clPendingBalance: reportClPendingBalance,
                withdrawalVaultBalance: self.withdrawalVault.balance,
                elRewardsVaultBalance: self.elRewardsVault.balance,
                sharesRequestedToBurn: 0,
                withdrawalFinalizationBatches: withdrawalBatches.getResult(),
                simulatedShareRate: targetShareRate
            })
        );
    }

    function _handleOracleReport(Context memory self, IAccounting.ReportValues memory params) private {
        vm.startPrank(address(self.accountingOracle));
        self.lidoLocator.accounting().handleOracleReport(params);
        vm.stopPrank();
    }

    struct FinalizationBatchesParams {
        uint256 shareRate;
        uint256 limitedWithdrawalVaultBalance;
        uint256 limitedElRewardsVaultBalance;
    }

    function getFinalizationBatches(
        Context memory self,
        FinalizationBatchesParams memory params
    ) internal view returns (IWithdrawalQueue.BatchesCalculationState memory batchesState) {
        IOracleReportSanityChecker.LimitsList memory limits = self.oracleReportSanityChecker.getOracleReportLimits();
        uint256 bufferedEther = self.stETH.getBufferedEther();
        uint256 unfinalizedStETH = self.withdrawalQueue.unfinalizedStETH();

        uint256 reservedBuffer = Math.min(bufferedEther, unfinalizedStETH);
        batchesState.remainingEthBudget =
            params.limitedWithdrawalVaultBalance + params.limitedElRewardsVaultBalance + reservedBuffer;

        uint256 blockTimestamp = block.timestamp;
        uint256 maxTimestamp = blockTimestamp - limits.requestTimestampMargin;

        while (!batchesState.finished && batchesState.remainingEthBudget != 0) {
            batchesState = self.withdrawalQueue
                .calculateFinalizationBatches(params.shareRate, maxTimestamp, MAX_REQUESTS_PER_CALL, batchesState);
        }
    }

    function finalizeWithdrawalQueue(Context memory self) internal {
        performRebase(self, PercentsD16.fromBasisPoints(100_00), self.withdrawalQueue.getLastRequestId());
    }

    function finalizeWithdrawalQueue(Context memory self, uint256 id) internal {
        performRebase(self, PercentsD16.fromBasisPoints(100_00), id);
    }

    function removeStakingLimit(Context memory self) external {
        bytes32 stakingLimitSlot = keccak256("lido.Lido.stakeLimit");
        uint256 stakingLimitEncodedData = uint256(vm.load(address(self.stETH), stakingLimitSlot));
        // See the encoding here: https://github.com/lidofinance/lido-dao/blob/5fcedc6e9a9f3ec154e69cff47c2b9e25503a78a/contracts/0.4.24/lib/StakeLimitUtils.sol#L10
        // To remove staking limit, set the most significant 96 bits to zero
        stakingLimitEncodedData &= 2 ** 160 - 1;
        vm.store(address(self.stETH), stakingLimitSlot, bytes32(stakingLimitEncodedData));
        assert(self.stETH.getCurrentStakeLimit() == type(uint256).max);
    }

    // ---
    // ACL
    // ---

    function hasPermission(
        Context memory self,
        address entity,
        address app,
        bytes32 role
    ) internal view returns (bool) {
        return self.acl.hasPermission(entity, app, role);
    }

    function grantPermission(Context memory self, address app, bytes32 role, address grantee) internal {
        if (!self.acl.hasPermission(grantee, app, role)) {
            address manager = self.acl.getPermissionManager(app, role);
            vm.prank(manager);
            self.acl.grantPermission(grantee, app, role);
            assert(self.acl.hasPermission(grantee, app, role));
        }
    }

    // ---
    // Aragon Governance
    // ---

    function setupLDOWhale(Context memory self, address account) internal {
        vm.startPrank(address(self.agent));
        self.ldoToken.transfer(account, self.ldoToken.balanceOf(address(self.agent)));
        vm.stopPrank();

        assert(self.ldoToken.balanceOf(account) >= self.voting.minAcceptQuorumPct());

        // Increase block number since MiniMe snapshotting relies on it
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 15);
    }

    function supportVoteAndWaitTillDecided(Context memory self, uint256 voteId, address voter) internal {
        supportVote(self, voteId, voter);
        vm.warp(block.timestamp + self.voting.voteTime());
    }

    function supportVoteAndWaitTillDecided(Context memory self, uint256 voteId) internal {
        if (self.ldoToken.balanceOf(DEFAULT_LDO_WHALE) < self.voting.minAcceptQuorumPct()) {
            setupLDOWhale(self, DEFAULT_LDO_WHALE);
        }
        supportVoteAndWaitTillDecided(self, voteId, DEFAULT_LDO_WHALE);
    }

    function supportVote(Context memory self, uint256 voteId, address voter) internal {
        vote(self, voteId, voter, true);
    }

    function vote(Context memory self, uint256 voteId, address voter, bool support) internal {
        vm.prank(voter);
        self.voting.vote(voteId, support, false);
    }

    function adoptVote(
        Context memory self,
        string memory description,
        bytes memory script
    ) internal returns (uint256 voteId) {
        if (self.ldoToken.balanceOf(DEFAULT_LDO_WHALE) < self.voting.minAcceptQuorumPct()) {
            setupLDOWhale(self, DEFAULT_LDO_WHALE);
        }
        bytes memory voteScript = CallsScriptBuilder.create(
                address(self.voting), abi.encodeCall(self.voting.newVote, (script, description, false, false))
            ).getResult();

        voteId = self.voting.votesLength();

        vm.prank(DEFAULT_LDO_WHALE);
        self.tokenManager.forward(voteScript);
        supportVoteAndWaitTillDecided(self, voteId, DEFAULT_LDO_WHALE);
    }

    function executeVote(Context memory self, uint256 voteId) internal {
        self.voting.executeVote(voteId);
    }

    function getLastVoteId(Context memory self) internal view returns (uint256) {
        return self.voting.votesLength() - 1;
    }

    // ---
    // SRV3 Compact Unstructured Storage Helpers
    // ---

    function getLowUint128(address contractAddress, bytes32 position) internal view returns (uint256) {
        return uint256(vm.load(contractAddress, position)) & UINT128_LOW_MASK;
    }

    function getHighUint128(address contractAddress, bytes32 position) internal view returns (uint256) {
        return uint256(vm.load(contractAddress, position)) >> 128;
    }

    function setLowUint128(address contractAddress, bytes32 position, uint256 data) internal {
        uint256 high128 = uint256(vm.load(contractAddress, position)) & UINT128_HIGH_MASK;
        vm.store(contractAddress, position, bytes32(high128 | (data & UINT128_LOW_MASK)));
    }
}
