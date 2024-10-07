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
import {IAragonVoting} from "contracts/interfaces/IAragonVoting.sol";
import {IAragonForwarder} from "./interfaces/IAragonForwarder.sol";

import {EvmScriptUtils} from "./evm-script-utils.sol";

import {
    ST_ETH,
    WST_ETH,
    WITHDRAWAL_QUEUE,
    DAO_ACL,
    LDO_TOKEN,
    DAO_AGENT,
    DAO_VOTING,
    DAO_TOKEN_MANAGER
} from "addresses/mainnet-addresses.sol";

uint256 constant ST_ETH_TRANSFERS_SHARE_LOSS_COMPENSATION = 8; // TODO: evaluate min enough value

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
        ctx.stETH = IStETH(ST_ETH);
        ctx.wstETH = IWstETH(WST_ETH);
        ctx.withdrawalQueue = IWithdrawalQueue(WITHDRAWAL_QUEUE);

        ctx.acl = IAragonACL(DAO_ACL);
        ctx.agent = IAragonAgent(DAO_AGENT);
        ctx.voting = IAragonVoting(DAO_VOTING);
        ctx.ldoToken = IERC20(LDO_TOKEN);
        ctx.tokenManager = IAragonForwarder(DAO_TOKEN_MANAGER);
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

    function executeVote(Context memory self, uint256 voteId) internal {
        self.voting.executeVote(voteId);
    }
}
