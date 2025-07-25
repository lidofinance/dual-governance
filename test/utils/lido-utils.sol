// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

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

import {CallsScriptBuilder} from "scripts/utils/CallsScriptBuilder.sol";
import {DecimalsFormatting} from "test/utils/formatting.sol";

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
address constant HOLESKY_HASH_CONSENSUS = 0xa067FC95c22D51c3bC35fd4BE37414Ee8cc890d2;
address constant HOLESKY_BURNER = 0x4E46BD7147ccf666E1d73A3A456fC7a68de82eCA;
address constant HOLESKY_ACCOUNTING_ORACLE = 0x4E97A3972ce8511D87F334dA17a2C332542a5246;
address constant HOLESKY_EL_REWARDS_VAULT = 0xE73a3602b99f1f913e72F8bdcBC235e206794Ac8;
address constant HOLESKY_WITHDRAWAL_VAULT = 0xF0179dEC45a37423EAD4FaD5fCb136197872EAd9;
address constant HOLESKY_ORACLE_REPORT_SANITY_CHECKER = 0x80D1B1fF6E84134404abA18A628347960c38ccA7;

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
address constant HOODI_HASH_CONSENSUS = 0x32EC59a78abaca3f91527aeB2008925D5AaC1eFC;
address constant HOODI_BURNER = 0x4e9A9ea2F154bA34BE919CD16a4A953DCd888165;
address constant HOODI_ACCOUNTING_ORACLE = 0xcb883B1bD0a41512b42D2dB267F2A2cd919FB216;
address constant HOODI_EL_REWARDS_VAULT = 0x9b108015fe433F173696Af3Aa0CF7CDb3E104258;
address constant HOODI_WITHDRAWAL_VAULT = 0x4473dCDDbf77679A643BdB654dbd86D67F8d32f2;
address constant HOODI_ORACLE_REPORT_SANITY_CHECKER = 0x26AED10459e1096d242ABf251Ff55f8DEaf52348;

address constant HOODI_DAO_ACL = 0x78780e70Eae33e2935814a327f7dB6c01136cc62;
address constant HOODI_LDO_TOKEN = 0xEf2573966D009CcEA0Fc74451dee2193564198dc;
address constant HOODI_DAO_AGENT = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD;
address constant HOODI_DAO_VOTING = 0x49B3512c44891bef83F8967d075121Bd1b07a01B;
address constant HOODI_DAO_TOKEN_MANAGER = 0x8ab4a56721Ad8e68c6Ad86F9D9929782A78E39E5;

Vm constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

library LidoUtils {
    using DecimalsFormatting for uint256;
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

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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

    function holesky() internal pure returns (Context memory ctx) {
        ctx.stETH = IStETH(HOLESKY_ST_ETH);
        ctx.wstETH = IWstETH(HOLESKY_WST_ETH);
        ctx.burner = IBurner(HOLESKY_BURNER);
        ctx.hashConsensus = IHashConsensus(HOLESKY_HASH_CONSENSUS);
        ctx.withdrawalQueue = IWithdrawalQueue(HOLESKY_WITHDRAWAL_QUEUE);
        ctx.accountingOracle = IAccountingOracle(HOLESKY_ACCOUNTING_ORACLE);
        ctx.oracleReportSanityChecker = IOracleReportSanityChecker(HOLESKY_ORACLE_REPORT_SANITY_CHECKER);

        ctx.elRewardsVault = HOLESKY_EL_REWARDS_VAULT;
        ctx.withdrawalVault = HOLESKY_WITHDRAWAL_VAULT;

        ctx.acl = IAragonACL(HOLESKY_DAO_ACL);
        ctx.agent = IAragonAgent(HOLESKY_DAO_AGENT);
        ctx.voting = IAragonVoting(HOLESKY_DAO_VOTING);
        ctx.ldoToken = IERC20(HOLESKY_LDO_TOKEN);
        ctx.tokenManager = IAragonForwarder(HOLESKY_DAO_TOKEN_MANAGER);
    }

    function hoodi() internal pure returns (Context memory ctx) {
        ctx.stETH = IStETH(HOODI_ST_ETH);
        ctx.wstETH = IWstETH(HOODI_WST_ETH);
        ctx.burner = IBurner(HOODI_BURNER);
        ctx.hashConsensus = IHashConsensus(HOODI_HASH_CONSENSUS);
        ctx.withdrawalQueue = IWithdrawalQueue(HOODI_WITHDRAWAL_QUEUE);
        ctx.accountingOracle = IAccountingOracle(HOODI_ACCOUNTING_ORACLE);
        ctx.oracleReportSanityChecker = IOracleReportSanityChecker(HOODI_ORACLE_REPORT_SANITY_CHECKER);

        ctx.elRewardsVault = HOODI_EL_REWARDS_VAULT;
        ctx.withdrawalVault = HOODI_WITHDRAWAL_VAULT;

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
        uint256 approximatedAmount =
            totalSupply * PercentD16.unwrap(percentage) / PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00));

        /// @dev Below transformation helps to fix the rounding issue
        while (
            self.stETH.getPooledEthByShares(self.stETH.getSharesByPooledEth(approximatedAmount))
                * PercentD16.unwrap(PercentsD16.fromBasisPoints(100_00)) / totalSupply < PercentD16.unwrap(percentage)
        ) {
            approximatedAmount++;
        }
        return approximatedAmount;
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

        // add 10 slots to be sure that the next frame starts
        uint256 nextFrameStartWithOffset = nextFrameStart + secondsPerSlot * 10;

        return ReportTimeElapsed({
            time: time,
            nextFrameStart: nextFrameStart,
            nextFrameStartWithOffset: nextFrameStartWithOffset,
            timeElapsed: nextFrameStartWithOffset - time
        });
    }

    function _getStakingModuleIdsWithNewlyExitedValidators() internal pure returns (uint256[] memory) {
        uint256[] memory stakingModuleIdsWithNewlyExitedValidators = new uint256[](1);
        stakingModuleIdsWithNewlyExitedValidators[0] = 1;
        return stakingModuleIdsWithNewlyExitedValidators;
    }

    function _getSharesToBurn(Context memory self) private view returns (uint256) {
        (uint256 coverShares, uint256 nonCoverShares) = self.burner.getSharesRequestedToBurn();
        return coverShares + nonCoverShares;
    }

    function _getPostCLBalance(Context memory self, uint256 clDiff) private view returns (uint256) {
        (,, uint256 beaconBalance) = self.stETH.getBeaconStat();
        return beaconBalance + clDiff;
    }

    function _getPostBeaconValidators(
        Context memory self,
        uint256 clAppearedValidators
    ) private view returns (uint256) {
        (, uint256 beaconValidators,) = self.stETH.getBeaconStat();
        return beaconValidators + clAppearedValidators;
    }

    struct SimulateReportParams {
        uint256 refSlot;
        uint256 beaconValidators;
        uint256 clBalance;
        uint256 withdrawalVaultBalance;
        uint256 elRewardsVaultBalance;
    }

    function simulateRebase(Context memory self, PercentD16 rebaseFactor) internal {
        performRebase(self, rebaseFactor, self.withdrawalQueue.getLastFinalizedRequestId());
    }

    function performRebase(Context memory self, PercentD16 rebaseFactor, uint256 lastUnstETHIdToFinalize) internal {
        // console.log("----- Perform Oracle rebase ----");

        vm.startPrank(address(self.agent));
        self.oracleReportSanityChecker.grantRole(
            self.oracleReportSanityChecker.ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE(), address(self.agent)
        );
        self.oracleReportSanityChecker.grantRole(
            self.oracleReportSanityChecker.REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE(), address(self.agent)
        );
        self.oracleReportSanityChecker.setAnnualBalanceIncreaseBPLimit(100_00);
        self.oracleReportSanityChecker.setRequestTimestampMargin(0);
        vm.stopPrank();

        uint256 clBalance = _sweepBufferedEther(self);

        uint256 shareRateBefore = self.stETH.getPooledEthByShares(10 ** 27);

        uint256 newCLBalance = PercentD16.unwrap(rebaseFactor) * clBalance / 10 ** 18;

        vm.deal(self.elRewardsVault, 0);
        _handleOracleReport(self, int256(newCLBalance) - int256(clBalance), lastUnstETHIdToFinalize);

        uint256 shareRateAfter = self.stETH.getPooledEthByShares(10 ** 27);

        // console.log("Share Rate Before: %s", shareRateBefore.formatRay());
        // console.log("Share Rate After: %s", shareRateAfter.formatRay());

        PercentD16 rebaseRate = PercentsD16.fromFraction(shareRateAfter, shareRateBefore);

        // TODO: try to decrease the error margin
        vm.assertApproxEqAbs(
            rebaseRate.toUint256(),
            rebaseFactor.toUint256(),
            PercentsD16.fromFraction(1, 1000).toUint256(), // 0.1% error margin
            "Rebase rate error is too high"
        );
    }

    function _sweepBufferedEther(Context memory self) internal returns (uint256 clBalance) {
        bytes32 bufferedEtherSlot = keccak256("lido.Lido.bufferedEther");
        bytes32 clBalanceSlot = keccak256("lido.Lido.beaconBalance");

        clBalance = uint256(vm.load(address(self.stETH), clBalanceSlot));
        uint256 bufferedEther = uint256(vm.load(address(self.stETH), bufferedEtherSlot));

        // for the simplicity of the accounting, move all buffered ether to the cl balance
        // as it was deposited
        if (bufferedEther > 0) {
            vm.deal(address(self.stETH), address(self.stETH).balance - bufferedEther);
            vm.deal(self.withdrawalVault, self.withdrawalVault.balance + bufferedEther);

            clBalance += bufferedEther;
            vm.store(address(self.stETH), bufferedEtherSlot, bytes32(0));
            vm.store(address(self.stETH), clBalanceSlot, bytes32(clBalance));

            (,, uint256 updatedCLBalance) = self.stETH.getBeaconStat();
            require(updatedCLBalance == clBalance, "Unexpected CL Balance");
            require(self.stETH.getBufferedEther() == 0, "Non Zero Buffered Ether");
        }
    }

    function _calculateUnfinalizedStETH(
        Context memory self,
        uint256 lastUnstETHIdToFinalize
    ) private view returns (uint256) {
        uint256 lastFinalizedUnstETHId = self.withdrawalQueue.getLastFinalizedRequestId();
        if (lastUnstETHIdToFinalize <= lastFinalizedUnstETHId) {
            return 0;
        }

        uint256 lastUnstETHId = self.withdrawalQueue.getLastRequestId();
        if (lastUnstETHIdToFinalize >= lastUnstETHId) {
            return self.withdrawalQueue.unfinalizedStETH();
        }

        uint256[] memory requestIdsToFinalize = new uint256[](lastUnstETHIdToFinalize - lastFinalizedUnstETHId);

        for (uint256 i = 0; i < requestIdsToFinalize.length; ++i) {
            requestIdsToFinalize[i] = lastFinalizedUnstETHId + i + 1;
        }

        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            self.withdrawalQueue.getWithdrawalStatus(requestIdsToFinalize);
        uint256 unfinalizedStETH = 0;

        for (uint256 i = 0; i < statuses.length; ++i) {
            unfinalizedStETH += statuses[i].amountOfStETH;
        }
        return unfinalizedStETH;
    }

    function _handleOracleReport(
        Context memory self,
        int256 clBalanceChange,
        uint256 lastUnstETHIdToFinalize
    ) internal returns (uint256 finalizedStETH) {
        (, uint256 beaconValidators, uint256 oldCLBalance) = self.stETH.getBeaconStat();
        uint256 newCLBalance = uint256(int256(oldCLBalance) + clBalanceChange);

        {
            finalizedStETH = _calculateUnfinalizedStETH(self, lastUnstETHIdToFinalize);
            // TODO: temporarily added 1 gwei to fix OutOfFunds error. Need to fix it properly in a separate PR.
            vm.deal(self.withdrawalVault, finalizedStETH + 1 gwei);

            newCLBalance -= finalizedStETH;
        }

        uint256 simulatedShareRate;
        uint256[] memory withdrawalBatches;
        {
            SimulateReportResult memory simulatedReport = _simulateReport(self, beaconValidators, newCLBalance);
            simulatedShareRate = simulatedReport.postTotalPooledEther * 10 ** 27 / simulatedReport.postTotalShares;

            if (finalizedStETH > 0) {
                IWithdrawalQueue.BatchesCalculationState memory batchesState = getFinalizationBatches(
                    self,
                    FinalizationBatchesParams({
                        shareRate: simulatedShareRate,
                        limitedWithdrawalVaultBalance: simulatedReport.withdrawals,
                        limitedElRewardsVaultBalance: simulatedReport.elRewards
                    })
                );

                withdrawalBatches = new uint256[](batchesState.batchesLength);

                for (uint256 i = 0; i < batchesState.batchesLength; ++i) {
                    withdrawalBatches[i] = batchesState.batches[i];
                }
            }
        }

        {
            // TODO: temporarily added 1 gwei to fix OutOfFunds error. Need to fix it properly in a separate PR.
            vm.deal(self.withdrawalVault, self.withdrawalVault.balance + 1 gwei);
            vm.startPrank(address(self.accountingOracle));
            _handleOracleReport(
                self,
                HandleOracleReportParams({
                    reportTimestamp: block.timestamp,
                    timeElapsed: 1 days,
                    clValidators: beaconValidators,
                    clBalance: newCLBalance,
                    withdrawalVaultBalance: self.withdrawalVault.balance,
                    elRewardsVaultBalance: self.elRewardsVault.balance,
                    sharesRequestedToBurn: 0,
                    withdrawalFinalizationBatches: withdrawalBatches,
                    simulatedShareRate: simulatedShareRate
                })
            );
            vm.stopPrank();
        }
    }

    struct HandleOracleReportParams {
        // Oracle timings
        uint256 reportTimestamp;
        uint256 timeElapsed;
        // CL values
        uint256 clValidators;
        uint256 clBalance;
        // EL values
        uint256 withdrawalVaultBalance;
        uint256 elRewardsVaultBalance;
        uint256 sharesRequestedToBurn;
        // Decision about withdrawals processing
        uint256[] withdrawalFinalizationBatches;
        uint256 simulatedShareRate;
    }

    function _handleOracleReport(
        Context memory self,
        HandleOracleReportParams memory params
    ) private returns (SimulateReportResult memory res) {
        uint256[4] memory simulatedPostRebaseAmounts = self.stETH.handleOracleReport({
            _reportTimestamp: params.reportTimestamp,
            _timeElapsed: params.timeElapsed,
            _clValidators: params.clValidators,
            _clBalance: params.clBalance,
            _withdrawalVaultBalance: params.withdrawalVaultBalance,
            _elRewardsVaultBalance: params.elRewardsVaultBalance,
            _sharesRequestedToBurn: params.sharesRequestedToBurn,
            _withdrawalFinalizationBatches: params.withdrawalFinalizationBatches,
            _simulatedShareRate: params.simulatedShareRate
        });

        res.postTotalPooledEther = simulatedPostRebaseAmounts[0];
        res.postTotalShares = simulatedPostRebaseAmounts[1];
        res.withdrawals = simulatedPostRebaseAmounts[2];
        res.elRewards = simulatedPostRebaseAmounts[3];
    }

    function _simulateReport(
        Context memory self,
        uint256 beaconValidators,
        uint256 newCLBalance
    ) internal returns (SimulateReportResult memory res) {
        uint256 snapshotId = vm.snapshot();
        vm.startPrank(address(self.accountingOracle));
        res = _handleOracleReport(
            self,
            HandleOracleReportParams({
                reportTimestamp: block.timestamp,
                timeElapsed: 1 days,
                clValidators: beaconValidators,
                clBalance: newCLBalance,
                withdrawalVaultBalance: self.withdrawalVault.balance,
                elRewardsVaultBalance: self.elRewardsVault.balance,
                sharesRequestedToBurn: 0,
                withdrawalFinalizationBatches: new uint256[](0),
                simulatedShareRate: 0
            })
        );
        vm.stopPrank();

        vm.revertTo(snapshotId);
    }

    struct SimulateReportResult {
        uint256 postTotalPooledEther;
        uint256 postTotalShares;
        uint256 withdrawals;
        uint256 elRewards;
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
        uint256 availableEth =
            params.limitedWithdrawalVaultBalance + params.limitedElRewardsVaultBalance + reservedBuffer;

        uint256 blockTimestamp = block.timestamp;
        uint256 maxTimestamp = blockTimestamp - limits.requestTimestampMargin;
        uint256 MAX_REQUESTS_PER_CALL = 1000;

        if (availableEth == 0) {
            revert("No available ETH");
        }

        batchesState.remainingEthBudget = availableEth;

        while (!batchesState.finished) {
            batchesState = self.withdrawalQueue.calculateFinalizationBatches(
                params.shareRate, maxTimestamp, MAX_REQUESTS_PER_CALL, batchesState
            );
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
