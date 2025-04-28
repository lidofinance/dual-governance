// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IBurner} from "./interfaces/IBurner.sol";
import {IHashConsensus} from "./interfaces/IHashConsensus.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";
import {IAccountingOracle} from "./interfaces/IAccountingOracle.sol";
import {IOracleReportSanityChecker} from "./interfaces/IOracleReportSanityChecker.sol";

import {IAragonACL} from "./interfaces/IAragonACL.sol";
import {IAragonAgent} from "./interfaces/IAragonAgent.sol";
import {IAragonVoting} from "./interfaces/IAragonVoting.sol";
import {IAragonForwarder} from "./interfaces/IAragonForwarder.sol";

import {CallsScriptBuilder} from "scripts/utils/calls-script-builder.sol";

uint256 constant ST_ETH_TRANSFERS_SHARE_LOSS_COMPENSATION = 8; // TODO: evaluate min enough value

// ---
// Mainnet Addresses
// ---

address constant MAINNET_ST_ETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
address constant MAINNET_WST_ETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant MAINNET_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
address constant MAINNET_HASH_CONSENSUS = 0xD624B08C83bAECF0807Dd2c6880C3154a5F0B288;
address constant MAINNET_BURNER = 0xD15a672319Cf0352560eE76d9e89eAB0889046D3;
address constant MAINNET_ACCOUNTING_ORACLE = 0x852deD011285fe67063a08005c71a85690503Cee;
address constant MAINNET_EL_REWARDS_VAULT = 0x388C818CA8B9251b393131C08a736A67ccB19297;
address constant MAINNET_WITHDRAWAL_VAULT = 0xB9D7934878B5FB9610B3fE8A5e441e8fad7E293f;
address constant MAINNET_ORACLE_REPORT_SANITY_CHECKER = 0x6232397ebac4f5772e53285B26c47914E9461E75;

address constant MAINNET_DAO_ACL = 0x9895F0F17cc1d1891b6f18ee0b483B6f221b37Bb;
address constant MAINNET_LDO_TOKEN = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
address constant MAINNET_DAO_AGENT = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
address constant MAINNET_DAO_VOTING = 0x2e59A20f205bB85a89C53f1936454680651E618e;
address constant MAINNET_DAO_TOKEN_MANAGER = 0xf73a1260d222f447210581DDf212D915c09a3249;

// ---
// Holesky Addresses
// ---

address constant HOLESKY_ST_ETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
address constant HOLESKY_WST_ETH = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
address constant HOLESKY_WITHDRAWAL_QUEUE = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;

address constant HOLESKY_DAO_ACL = 0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC;
address constant HOLESKY_LDO_TOKEN = 0x14ae7daeecdf57034f3E9db8564e46Dba8D97344;
address constant HOLESKY_DAO_AGENT = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d;
address constant HOLESKY_DAO_VOTING = 0xdA7d2573Df555002503F29aA4003e398d28cc00f;
address constant HOLESKY_DAO_TOKEN_MANAGER = 0xFaa1692c6eea8eeF534e7819749aD93a1420379A;

// ---
// Hoodi Addresses
// ---

address constant HOODI_ST_ETH = 0x3508A952176b3c15387C97BE809eaffB1982176a;
address constant HOODI_WST_ETH = 0x7E99eE3C66636DE415D2d7C880938F2f40f94De4;
address constant HOODI_WITHDRAWAL_QUEUE = 0xfe56573178f1bcdf53F01A6E9977670dcBBD9186;

address constant HOODI_DAO_ACL = 0x78780e70Eae33e2935814a327f7dB6c01136cc62;
address constant HOODI_LDO_TOKEN = 0xEf2573966D009CcEA0Fc74451dee2193564198dc;
address constant HOODI_DAO_AGENT = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD;
address constant HOODI_DAO_VOTING = 0x49B3512c44891bef83F8967d075121Bd1b07a01B;
address constant HOODI_DAO_TOKEN_MANAGER = 0x8ab4a56721Ad8e68c6Ad86F9D9929782A78E39E5;

library LidoUtils {
    using CallsScriptBuilder for CallsScriptBuilder.Context;

    struct Context {
        // core
        IStETH stETH;
        IWstETH wstETH;
        IBurner burner;
        IHashConsensus hashConsensus;
        IWithdrawalQueue withdrawalQueue;
        IAccountingOracle accountingOracle;
        IOracleReportSanityChecker oracleReportSanityChecker;
        address elRewardsVault;
        address withdrawalVault;
        // aragon governance
        IAragonACL acl;
        IERC20 ldoToken;
        IAragonAgent agent;
        IAragonVoting voting;
        IAragonForwarder tokenManager;
    }

    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address internal constant DEFAULT_LDO_WHALE = address(0x1D0_1D0_1D0_1D0_1d0_1D0_1D0_1D0_1D0_1d0_1d0_1d0_1D0_1);

    function mainnet() internal pure returns (Context memory ctx) {
        ctx.stETH = IStETH(MAINNET_ST_ETH);
        ctx.wstETH = IWstETH(MAINNET_WST_ETH);
        ctx.burner = IBurner(MAINNET_BURNER);
        ctx.withdrawalQueue = IWithdrawalQueue(MAINNET_WITHDRAWAL_QUEUE);
        ctx.hashConsensus = IHashConsensus(MAINNET_HASH_CONSENSUS);
        ctx.accountingOracle = IAccountingOracle(MAINNET_ACCOUNTING_ORACLE);
        ctx.oracleReportSanityChecker = IOracleReportSanityChecker(MAINNET_ORACLE_REPORT_SANITY_CHECKER);

        ctx.elRewardsVault = MAINNET_EL_REWARDS_VAULT;
        ctx.withdrawalVault = MAINNET_WITHDRAWAL_VAULT;

        ctx.acl = IAragonACL(MAINNET_DAO_ACL);
        ctx.agent = IAragonAgent(MAINNET_DAO_AGENT);
        ctx.voting = IAragonVoting(MAINNET_DAO_VOTING);
        ctx.ldoToken = IERC20(MAINNET_LDO_TOKEN);
        ctx.tokenManager = IAragonForwarder(MAINNET_DAO_TOKEN_MANAGER);
    }

    // TODO: Add addresses for missing contracts
    function holesky() internal pure returns (Context memory ctx) {
        ctx.stETH = IStETH(HOLESKY_ST_ETH);
        ctx.wstETH = IWstETH(HOLESKY_WST_ETH);
        ctx.withdrawalQueue = IWithdrawalQueue(HOLESKY_WITHDRAWAL_QUEUE);

        ctx.acl = IAragonACL(HOLESKY_DAO_ACL);
        ctx.agent = IAragonAgent(HOLESKY_DAO_AGENT);
        ctx.voting = IAragonVoting(HOLESKY_DAO_VOTING);
        ctx.ldoToken = IERC20(HOLESKY_LDO_TOKEN);
        ctx.tokenManager = IAragonForwarder(HOLESKY_DAO_TOKEN_MANAGER);
    }

    // TODO: Add addresses for missing contracts
    function hoodi() internal pure returns (Context memory ctx) {
        ctx.stETH = IStETH(HOODI_ST_ETH);
        ctx.wstETH = IWstETH(HOODI_WST_ETH);
        ctx.withdrawalQueue = IWithdrawalQueue(HOODI_WITHDRAWAL_QUEUE);

        ctx.acl = IAragonACL(HOODI_DAO_ACL);
        ctx.agent = IAragonAgent(HOODI_DAO_AGENT);
        ctx.voting = IAragonVoting(HOODI_DAO_VOTING);
        ctx.ldoToken = IERC20(HOODI_LDO_TOKEN);
        ctx.tokenManager = IAragonForwarder(HOODI_DAO_TOKEN_MANAGER);
    }

    function calcAmountFromPercentageOfTVL(
        Context memory self,
        PercentD16 percentage
    ) internal view returns (uint256) {
        uint256 totalSupply = self.stETH.totalSupply();
        uint256 amount =
            totalSupply * PercentD16.unwrap(percentage) / PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00));

        /// @dev Below transformation helps to fix the rounding issue
        PercentD16 resulting = PercentsD16.fromFraction({numerator: amount, denominator: totalSupply});
        return amount * PercentD16.unwrap(percentage) / PercentD16.unwrap(resulting);
    }

    function calcSharesFromPercentageOfTVL(
        Context memory self,
        PercentD16 percentage
    ) internal view returns (uint256) {
        uint256 totalShares = self.stETH.getTotalShares();
        uint256 shares =
            totalShares * PercentD16.unwrap(percentage) / PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00));

        /// @dev Below transformation helps to fix the rounding issue
        PercentD16 resulting = PercentsD16.fromFraction({numerator: shares, denominator: totalShares});
        return shares * PercentD16.unwrap(percentage) / PercentD16.unwrap(resulting);
    }

    function calcAmountToDepositFromPercentageOfTVL(
        Context memory self,
        PercentD16 percentage
    ) internal view returns (uint256) {
        uint256 totalSupply = self.stETH.totalSupply();
        /// @dev Calculate amount and shares using the following rule:
        /// bal / (totalSupply + bal) = percentage => bal = totalSupply * percentage / (1 - percentage)
        uint256 amount = totalSupply * PercentD16.unwrap(percentage)
            / PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00) - percentage);

        /// @dev Below transformation helps to fix the rounding issue
        PercentD16 resulting = PercentsD16.fromFraction({numerator: amount, denominator: totalSupply + amount});
        return amount * PercentD16.unwrap(percentage) / PercentD16.unwrap(resulting);
    }

    function calcSharesToDepositFromPercentageOfTVL(
        Context memory self,
        PercentD16 percentage
    ) internal view returns (uint256) {
        uint256 totalShares = self.stETH.getTotalShares();
        /// @dev Calculate amount and shares using the following rule:
        /// bal / (totalShares + bal) = percentage => bal = totalShares * percentage / (1 - percentage)
        uint256 shares = totalShares * PercentD16.unwrap(percentage)
            / PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00) - percentage);

        /// @dev Below transformation helps to fix the rounding issue
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

    function _getSharesToBurn(Context memory self) private returns (uint256) {
        (uint256 coverShares, uint256 nonCoverShares) = self.burner.getSharesRequestedToBurn();
        return coverShares + nonCoverShares;
    }

    function _getPostCLBalance(Context memory self, uint256 clDiff) private returns (uint256) {
        (,, uint256 beaconBalance) = self.stETH.getBeaconStat();
        return beaconBalance + clDiff;
    }

    function _getPostBeaconValidators(Context memory self, uint256 clAppearedValidators) private returns (uint256) {
        (, uint256 beaconValidators,) = self.stETH.getBeaconStat();
        return beaconValidators + clAppearedValidators;
    }

    function waitNextAvailableReportTime(Context memory self) internal {
        (uint256 slotsPerEpoch,,) = self.hashConsensus.getChainConfig();
        (, uint256 epochsPerFrame,) = self.hashConsensus.getFrameConfig();
        (uint256 refSlot,) = self.hashConsensus.getCurrentFrame();

        uint256 slotsPerFrame = slotsPerEpoch * epochsPerFrame;

        ReportTimeElapsed memory timeElapsed = getReportTimeElapsed(self);

        vm.warp(block.timestamp + timeElapsed.timeElapsed);

        uint256 timeAfterWarp = block.timestamp;

        (uint256 nextRefSlot,) = self.hashConsensus.getCurrentFrame();

        if (nextRefSlot != refSlot + slotsPerFrame) {
            revert("Next frame refSlot is incorrect");
        }
    }

    struct ReportTimeElapsed {
        uint256 time;
        uint256 timeElapsed;
        uint256 nextFrameStart;
        uint256 nextFrameStartWithOffset;
    }

    function getReportTimeElapsed(Context memory self) internal returns (ReportTimeElapsed memory) {
        (uint256 slotsPerEpoch, uint256 secondsPerSlot, uint256 genesisTime) = self.hashConsensus.getChainConfig();
        (uint256 refSlot,) = self.hashConsensus.getCurrentFrame();
        (, uint256 epochsPerFrame,) = self.hashConsensus.getFrameConfig();
        uint256 time = block.timestamp;

        uint256 slotsPerFrame = slotsPerEpoch * epochsPerFrame;
        uint256 nextRefSlot = refSlot + slotsPerFrame;
        uint256 nextFrameStart = genesisTime + nextRefSlot * secondsPerSlot;

        // add 10 slots to be sure that the next frame starts
        uint256 nextFrameStartWithOffset = nextFrameStart + secondsPerSlot * 10;

        return ReportTimeElapsed({
            time: time,
            nextFrameStart: nextFrameStart,
            nextFrameStartWithOffset: nextFrameStartWithOffset,
            timeElapsed: nextFrameStartWithOffset - time
        });
    }

    // Simulates Oracle Report. The implementation is based on:
    //     https://github.com/lidofinance/core/blob/d186530e74e07569295ac5de399389e5438bf567/lib/protocol/helpers/accounting.ts#L75
    function report(Context memory self, uint256 lastReportId) internal {
        waitNextAvailableReportTime(self);
        uint256 withdrawalVaultBalanceBefore = address(self.withdrawalVault).balance;

        (uint256 refSlot,) = self.hashConsensus.getCurrentFrame();
        uint256 postCLBalance = _getPostCLBalance(self, 0);
        uint256 postBeaconValidators = _getPostBeaconValidators(self, 0);

        SimulateReportResult memory report = simulateReport(
            self,
            SimulateReportParams({
                refSlot: refSlot,
                beaconValidators: postBeaconValidators,
                clBalance: postCLBalance,
                withdrawalVaultBalance: self.withdrawalVault.balance,
                elRewardsVaultBalance: self.elRewardsVault.balance
            })
        );

        uint256 simulatedShareRate = report.postTotalPooledEther * 10 ** 27 / report.postTotalShares;

        uint256[] memory withdrawalBatches = getFinalizationBatches(
            self,
            FinalizationBatchesParams({
                shareRate: report.postTotalPooledEther * 10 ** 27 / report.postTotalShares,
                limitedWithdrawalVaultBalance: report.withdrawals,
                limitedElRewardsVaultBalance: report.elRewards
            })
        );

        if (withdrawalBatches.length > 0 && withdrawalBatches[withdrawalBatches.length - 1] > lastReportId) {
            withdrawalBatches[withdrawalBatches.length - 1] = lastReportId;
        }

        bool isBunkerMode = self.stETH.getTotalPooledEther() > report.postTotalPooledEther;

        uint256[] memory numExitedValidatorsByStakingModule = new uint256[](1);
        numExitedValidatorsByStakingModule[0] = 30;

        submitReport(
            self,
            SubmitReportParams({
                refSlot: refSlot,
                clBalance: postCLBalance,
                numValidators: postBeaconValidators,
                withdrawalVaultBalance: self.withdrawalVault.balance,
                elRewardsVaultBalance: self.elRewardsVault.balance,
                sharesRequestedToBurn: _getSharesToBurn(self),
                simulatedShareRate: simulatedShareRate,
                stakingModuleIdsWithNewlyExitedValidators: _getStakingModuleIdsWithNewlyExitedValidators(),
                numExitedValidatorsByStakingModule: new uint256[](0),
                withdrawalFinalizationBatches: withdrawalBatches,
                isBunkerMode: isBunkerMode,
                extraDataFormat: 0,
                extraDataHash: bytes32(0),
                extraDataItemsCount: 0,
                extraDataList: new bytes(0)
            })
        );
    }

    function _getStakingModuleIdsWithNewlyExitedValidators() internal returns (uint256[] memory) {
        uint256[] memory stakingModuleIdsWithNewlyExitedValidators = new uint256[](1);
        stakingModuleIdsWithNewlyExitedValidators[0] = 1;
        return stakingModuleIdsWithNewlyExitedValidators;
    }

    struct SimulateReportParams {
        uint256 refSlot;
        uint256 beaconValidators;
        uint256 clBalance;
        uint256 withdrawalVaultBalance;
        uint256 elRewardsVaultBalance;
    }

    struct SimulateReportResult {
        uint256 postTotalPooledEther;
        uint256 postTotalShares;
        uint256 withdrawals;
        uint256 elRewards;
    }

    function simulateReport(
        Context memory self,
        SimulateReportParams memory params
    ) internal returns (SimulateReportResult memory res) {
        (, uint256 secondsPerSlot, uint256 genesisTime) = self.hashConsensus.getChainConfig();
        uint256 reportTimestamp = genesisTime + params.refSlot * secondsPerSlot;

        uint256 snapshotId = vm.snapshot();

        vm.store(
            address(self.accountingOracle), keccak256("lido.BaseOracle.lastProcessingRefSlot"), bytes32(params.refSlot)
        );

        vm.prank(address(self.accountingOracle));

        uint256[4] memory postRebaseAmounts = self.stETH.handleOracleReport(
            reportTimestamp,
            1 days,
            params.beaconValidators,
            params.clBalance,
            params.withdrawalVaultBalance,
            params.elRewardsVaultBalance,
            0,
            new uint256[](0),
            0
        );

        res.postTotalPooledEther = postRebaseAmounts[0];
        res.postTotalShares = postRebaseAmounts[1];
        res.withdrawals = postRebaseAmounts[2];
        res.elRewards = postRebaseAmounts[3];

        vm.revertTo(snapshotId);
    }

    struct FinalizationBatchesParams {
        uint256 shareRate;
        uint256 limitedWithdrawalVaultBalance;
        uint256 limitedElRewardsVaultBalance;
    }

    function getFinalizationBatches(
        Context memory self,
        FinalizationBatchesParams memory params
    ) internal returns (uint256[] memory resBatches) {
        IOracleReportSanityChecker.LimitsList memory limits = self.oracleReportSanityChecker.getOracleReportLimits();
        uint256 bufferedEther = self.stETH.getBufferedEther();
        uint256 unfinalizedStETH = self.withdrawalQueue.unfinalizedStETH();

        uint256 reservedBuffer = Math.min(bufferedEther, unfinalizedStETH);
        uint256 availableEth =
            params.limitedWithdrawalVaultBalance + params.limitedElRewardsVaultBalance + reservedBuffer;

        uint256 blockTimestamp = block.timestamp;
        uint256 maxTimestamp = blockTimestamp - limits.requestTimestampMargin;
        uint256 MAX_REQUESTS_PER_CALL = 1000;

        if (availableEth == 0) {
            revert("No available ETH");
        }

        uint256[36] memory batches;

        IWithdrawalQueue.BatchesCalculationState memory batchesState = self.withdrawalQueue.calculateFinalizationBatches(
            params.shareRate,
            maxTimestamp,
            MAX_REQUESTS_PER_CALL,
            IWithdrawalQueue.BatchesCalculationState({
                remainingEthBudget: availableEth,
                finished: false,
                batches: batches,
                batchesLength: 0
            })
        );

        while (!batchesState.finished) {
            IWithdrawalQueue.BatchesCalculationState memory state = IWithdrawalQueue.BatchesCalculationState({
                remainingEthBudget: batchesState.remainingEthBudget,
                finished: batchesState.finished,
                batches: batchesState.batches,
                batchesLength: batchesState.batchesLength
            });

            batchesState = self.withdrawalQueue.calculateFinalizationBatches(
                params.shareRate, maxTimestamp, MAX_REQUESTS_PER_CALL, state
            );
        }

        uint256 nonZeroBatchesLength = 0;

        for (uint256 i = 0; i < batchesState.batches.length; ++i) {
            if (batchesState.batches[i] > 0) {
                nonZeroBatchesLength += 1;
            }
        }

        resBatches = new uint256[](nonZeroBatchesLength);

        uint256 j = 0;
        for (uint256 i = 0; i < batchesState.batches.length; ++i) {
            if (batchesState.batches[i] > 0) {
                resBatches[j] = batchesState.batches[i];
                ++j;
            }
        }
    }

    struct SubmitReportParams {
        uint256 refSlot;
        uint256 clBalance;
        uint256 numValidators;
        uint256 withdrawalVaultBalance;
        uint256 elRewardsVaultBalance;
        uint256 sharesRequestedToBurn;
        uint256 simulatedShareRate;
        uint256[] stakingModuleIdsWithNewlyExitedValidators;
        uint256[] numExitedValidatorsByStakingModule;
        uint256[] withdrawalFinalizationBatches;
        bool isBunkerMode;
        uint256 extraDataFormat;
        bytes32 extraDataHash;
        uint256 extraDataItemsCount;
        bytes extraDataList;
    }

    function submitReport(Context memory self, SubmitReportParams memory params) internal {
        uint256 consensusVersion = self.accountingOracle.getConsensusVersion();
        uint256 oracleVersion = self.accountingOracle.getContractVersion();

        IAccountingOracle.ReportData memory reportData = IAccountingOracle.ReportData({
            consensusVersion: self.accountingOracle.getConsensusVersion(),
            refSlot: params.refSlot,
            clBalanceGwei: params.clBalance / 1 gwei,
            numValidators: params.numValidators,
            withdrawalVaultBalance: params.withdrawalVaultBalance,
            elRewardsVaultBalance: params.elRewardsVaultBalance,
            sharesRequestedToBurn: params.sharesRequestedToBurn,
            simulatedShareRate: params.simulatedShareRate,
            stakingModuleIdsWithNewlyExitedValidators: params.stakingModuleIdsWithNewlyExitedValidators,
            numExitedValidatorsByStakingModule: params.numExitedValidatorsByStakingModule,
            withdrawalFinalizationBatches: params.withdrawalFinalizationBatches,
            isBunkerMode: params.isBunkerMode,
            extraDataFormat: params.extraDataFormat,
            extraDataHash: params.extraDataHash,
            extraDataItemsCount: params.extraDataItemsCount
        });

        bytes32 digest = keccak256(abi.encode(reportData));

        address submitter = reachConsensus(self, params.refSlot, digest, consensusVersion);

        vm.prank(submitter);
        self.accountingOracle.submitReportData(reportData, oracleVersion);

        vm.prank(submitter);
        if (params.extraDataFormat > 0) {
            self.accountingOracle.submitReportExtraDataList(params.extraDataList);
        } else {
            self.accountingOracle.submitReportExtraDataEmpty();
        }

        IAccountingOracle.ProcessingState memory state = self.accountingOracle.getProcessingState();

        if (state.currentFrameRefSlot != params.refSlot) {
            revert("Processing state ref slot is incorrect");
        }
    }

    function reachConsensus(
        Context memory self,
        uint256 refSlot,
        bytes32 reportHash,
        uint256 consensusVersion
    ) internal returns (address) {
        (address[] memory addresses,) = self.hashConsensus.getFastLaneMembers();

        address submitter;
        for (uint256 i = 0; i < addresses.length; ++i) {
            if (submitter == address(0)) {
                submitter = addresses[i];
            }
            vm.deal(addresses[i], 1 ether);
            vm.prank(addresses[i]);
            self.hashConsensus.submitReport(refSlot, reportHash, consensusVersion);
        }

        (, bytes32 consensusReport,) = self.hashConsensus.getConsensusState();

        if (consensusReport != reportHash) {
            revert("Consensus report is incorrect");
        }
        return submitter;
    }

    function finalizeWithdrawalQueue(Context memory self) internal {
        uint256 lastWithdrawalId = self.withdrawalQueue.getLastRequestId();
        uint256 lastFinalizedWithdrawalId = self.withdrawalQueue.getLastFinalizedRequestId();

        if (lastFinalizedWithdrawalId < lastWithdrawalId) {
            finalizeWithdrawalQueue(self, lastWithdrawalId);
        }
    }

    function finalizeWithdrawalQueue(Context memory self, uint256 id) internal {
        vm.deal(address(self.withdrawalQueue), 10_000_000 ether);
        uint256 finalizationShareRate = self.stETH.getPooledEthByShares(1e27) + 1e9; // TODO check finalization rate
        vm.prank(address(self.stETH));
        self.withdrawalQueue.finalize(id, finalizationShareRate);

        bytes32 lockedEtherAmountSlot = 0x0e27eaa2e71c8572ab988fef0b54cd45bbd1740de1e22343fb6cda7536edc12f; // keccak256("lido.WithdrawalQueue.lockedEtherAmount");

        vm.store(address(self.withdrawalQueue), lockedEtherAmountSlot, bytes32(address(self.withdrawalQueue).balance));
    }

    function finalizeWithdrawalQueueByOracleReport(Context memory self, uint256 id) internal {
        uint256 lastRequestId = self.withdrawalQueue.getLastRequestId();
        uint256 lastFinalizedId = self.withdrawalQueue.getLastFinalizedRequestId();

        if (lastRequestId == lastFinalizedId) {
            return;
        }

        uint256 totalAmountOfStETHToFinalize = 0;
        uint256[] memory requestIdsToFinalize = new uint256[](lastRequestId - lastFinalizedId);

        for (uint256 i = 0; i < requestIdsToFinalize.length; ++i) {
            requestIdsToFinalize[i] = lastFinalizedId + 1 + i;
        }

        IWithdrawalQueue.WithdrawalRequestStatus[] memory requestsToFinalize =
            self.withdrawalQueue.getWithdrawalStatus(requestIdsToFinalize);

        for (uint256 i = 0; i < requestsToFinalize.length; ++i) {
            totalAmountOfStETHToFinalize += requestsToFinalize[i].amountOfStETH;
        }

        vm.deal(address(self.withdrawalVault), address(self.withdrawalVault).balance + totalAmountOfStETHToFinalize);

        report(self, lastRequestId);
    }

    /// @param rebaseFactor - rebase factor with 10 ** 16 precision
    /// 10 ** 18     => equal to no rebase
    /// 10 ** 18 - 1 => equal to decrease equal to 10 ** -18 %
    /// 10 ** 18 + 1 => equal to increase equal to 10 ** -18 %
    function simulateRebase(Context memory self, PercentD16 rebaseFactor) internal {
        bytes32 clBeaconBalanceSlot = keccak256("lido.Lido.beaconBalance");
        uint256 totalSupply = self.stETH.totalSupply();

        uint256 oldClBalance = uint256(vm.load(address(self.stETH), clBeaconBalanceSlot));
        uint256 newClBalance = PercentD16.unwrap(rebaseFactor) * oldClBalance / 10 ** 18;

        vm.store(address(self.stETH), clBeaconBalanceSlot, bytes32(newClBalance));

        // validate that total supply of the token updated expectedly
        if (rebaseFactor > PercentsD16.fromBasisPoints(100_00)) {
            uint256 clBalanceDelta = newClBalance - oldClBalance;
            assert(self.stETH.totalSupply() == totalSupply + clBalanceDelta);
        } else {
            uint256 clBalanceDelta = oldClBalance - newClBalance;
            assert(self.stETH.totalSupply() == totalSupply - clBalanceDelta);
        }
    }

    function removeStakingLimit(Context memory self) external {
        bytes32 stakingLimitSlot = keccak256("lido.Lido.stakeLimit");
        uint256 stakingLimitEncodedData = uint256(vm.load(address(self.stETH), stakingLimitSlot));
        // See the self encoding here: https://github.com/lidofinance/lido-dao/blob/5fcedc6e9a9f3ec154e69cff47c2b9e25503a78a/contracts/0.4.24/lib/StakeLimitUtils.sol#L10
        // To remove staking limit, most significant 96 bits must be set to zero
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

        // need to increase block number since MiniMe snapshotting relies on it
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

    // Creates vote with given description and script, votes for it, and waits until it can be executed
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
}
