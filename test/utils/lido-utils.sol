// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";

import {IAragonACL} from "./interfaces/IAragonACL.sol";
import {IAragonAgent} from "./interfaces/IAragonAgent.sol";
import {IAragonVoting} from "./interfaces/IAragonVoting.sol";
import {IAragonForwarder} from "./interfaces/IAragonForwarder.sol";

import {EvmScriptUtils} from "./evm-script-utils.sol";

uint256 constant ST_ETH_TRANSFERS_SHARE_LOSS_COMPENSATION = 8; // TODO: evaluate min enough value

// ---
// Mainnet Addresses
// ---

address constant MAINNET_ST_ETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
address constant MAINNET_WST_ETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant MAINNET_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

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

library LidoUtils {
    struct Context {
        // core
        IStETH stETH;
        IWstETH wstETH;
        IWithdrawalQueue withdrawalQueue;
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
        ctx.withdrawalQueue = IWithdrawalQueue(MAINNET_WITHDRAWAL_QUEUE);

        ctx.acl = IAragonACL(MAINNET_DAO_ACL);
        ctx.agent = IAragonAgent(MAINNET_DAO_AGENT);
        ctx.voting = IAragonVoting(MAINNET_DAO_VOTING);
        ctx.ldoToken = IERC20(MAINNET_LDO_TOKEN);
        ctx.tokenManager = IAragonForwarder(MAINNET_DAO_TOKEN_MANAGER);
    }

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

    function finalizeWithdrawalQueue(Context memory self) internal {
        finalizeWithdrawalQueue(self, self.withdrawalQueue.getLastRequestId());
    }

    function finalizeWithdrawalQueue(Context memory self, uint256 id) internal {
        vm.deal(address(self.withdrawalQueue), 10_000_000 ether);
        uint256 finalizationShareRate = self.stETH.getPooledEthByShares(1e27) + 1e9; // TODO check finalization rate
        vm.prank(address(self.stETH));
        self.withdrawalQueue.finalize(id, finalizationShareRate);

        bytes32 lockedEtherAmountSlot = 0x0e27eaa2e71c8572ab988fef0b54cd45bbd1740de1e22343fb6cda7536edc12f; // keccak256("lido.WithdrawalQueue.lockedEtherAmount");

        vm.store(address(self.withdrawalQueue), lockedEtherAmountSlot, bytes32(address(self.withdrawalQueue).balance));
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
        bytes memory voteScript = EvmScriptUtils.encodeEvmCallScript(
            address(self.voting), abi.encodeCall(self.voting.newVote, (script, description, false, false))
        );

        voteId = self.voting.votesLength();

        vm.prank(DEFAULT_LDO_WHALE);
        self.tokenManager.forward(voteScript);
        supportVoteAndWaitTillDecided(self, voteId, DEFAULT_LDO_WHALE);
    }

    function adoptVoteEVMScript(
        Context memory self,
        bytes memory evmScript,
        string memory description
    ) internal returns (uint256 voteId) {
        if (self.ldoToken.balanceOf(DEFAULT_LDO_WHALE) < self.voting.minAcceptQuorumPct()) {
            setupLDOWhale(self, DEFAULT_LDO_WHALE);
        }

        bytes memory voteScript = EvmScriptUtils.encodeEvmCallScript(
            address(self.voting), abi.encodeCall(self.voting.newVote, (evmScript, description, false, false))
        );

        vm.prank(DEFAULT_LDO_WHALE);
        self.tokenManager.forward(voteScript);

        voteId = self.voting.votesLength() - 1;

        supportVoteAndWaitTillDecided(self, voteId, DEFAULT_LDO_WHALE);
    }

    function executeVote(Context memory self, uint256 voteId) internal {
        self.voting.executeVote(voteId);
    }

    function getLastVoteId(Context memory self) internal view returns (uint256) {
        return self.voting.votesLength() - 1;
    }
}
