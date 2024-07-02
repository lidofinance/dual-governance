pragma solidity 0.8.23;

// solhint-disable-next-line
import "forge-std/console2.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {Percents, percents} from "../utils/percents.sol";

import "./mainnet-addresses.sol";
import "./interfaces.sol";

// May be used as a mock contract to collect method calls
contract TargetMock {
    struct Call {
        uint256 value;
        address sender;
        uint256 blockNumber;
        bytes data;
    }

    Call[] public calls;

    function getCallsLength() external view returns (uint256) {
        return calls.length;
    }

    function getCalls() external view returns (Call[] memory calls_) {
        calls_ = calls;
    }

    function reset() external {
        for (uint256 i = 0; i < calls.length; ++i) {
            calls.pop();
        }
    }

    fallback() external payable {
        calls.push(Call({value: msg.value, sender: msg.sender, blockNumber: block.number, data: msg.data}));
    }
}

library Utils {
    using stdStorage for StdStorage;

    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    struct EvmScriptCall {
        address target;
        bytes data;
    }

    function selectFork() internal {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(20218312);
    }

    function encodeEvmCallScript(address target, bytes memory data) internal pure returns (bytes memory) {
        EvmScriptCall[] memory calls = new EvmScriptCall[](1);
        calls[0] = EvmScriptCall(target, data);
        return encodeEvmCallScript(calls);
    }

    function encodeEvmCallScript(EvmScriptCall[] memory calls) internal pure returns (bytes memory) {
        bytes memory script = new bytes(4);
        script[3] = 0x01;

        for (uint256 i = 0; i < calls.length; ++i) {
            EvmScriptCall memory call = calls[i];
            script = bytes.concat(script, bytes20(call.target), bytes4(uint32(call.data.length)), call.data);
        }

        return script;
    }

    function setupLdoWhale(address addr) internal {
        vm.startPrank(DAO_AGENT);
        IERC20(LDO_TOKEN).transfer(addr, IERC20(LDO_TOKEN).balanceOf(DAO_AGENT));
        vm.stopPrank();
        // solhint-disable-next-line
        console.log(
            "LDO whale %x balance: %d LDO at block %d", addr, IERC20(LDO_TOKEN).balanceOf(addr) / 10 ** 18, block.number
        );
        assert(IERC20(LDO_TOKEN).balanceOf(addr) >= IAragonVoting(DAO_VOTING).minAcceptQuorumPct());
        // need to increase block number since MiniMe snapshotting relies on it
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 15);
    }

    function setupStETHWhale(address addr) internal returns (uint256 shares, uint256 balance) {
        // 15% of total stETH supply
        return setupStETHWhale(addr, percents("30.00"));
    }

    function setupStETHWhale(
        address addr,
        Percents memory totalSupplyPercentage
    ) internal returns (uint256 shares, uint256 balance) {
        uint256 ST_ETH_TRANSFERS_SHARE_LOSS_COMPENSATION = 8; // TODO: evaluate min enough value
        // bal / (totalSupply + bal) = percentage => bal = totalSupply * percentage / (1 - percentage)
        shares = ST_ETH_TRANSFERS_SHARE_LOSS_COMPENSATION
            + IStEth(ST_ETH).getTotalShares() * totalSupplyPercentage.value
                / (100 * 10 ** totalSupplyPercentage.precision - totalSupplyPercentage.value);
        // to compensate StETH wei lost on submit/transfers, generate slightly larger eth amount
        return depositStETH(addr, IStEth(ST_ETH).getPooledEthByShares(shares));
    }

    function depositStETH(
        address addr,
        uint256 amountToMint
    ) internal returns (uint256 sharesMinted, uint256 amountMinted) {
        uint256 sharesBalanceBefore = IStEth(ST_ETH).sharesOf(addr);
        uint256 amountBalanceBefore = IStEth(ST_ETH).balanceOf(addr);

        // solhint-disable-next-line
        console.log("setting ETH balance of address %x to %d ETH", addr, amountToMint / 10 ** 18);
        vm.deal(addr, amountToMint);
        vm.prank(addr);
        IStEth(ST_ETH).submit{value: amountToMint}(address(0));

        sharesMinted = IStEth(ST_ETH).sharesOf(addr) - sharesBalanceBefore;
        amountMinted = IStEth(ST_ETH).balanceOf(addr) - amountBalanceBefore;

        // solhint-disable-next-line
        console.log("stETH balance of address %x: %d stETH", addr, (amountMinted) / 10 ** 18);
    }

    function removeLidoStakingLimit() external {
        grantPermission(ST_ETH, IStEth(ST_ETH).STAKING_CONTROL_ROLE(), address(this));
        (, bool isStakingLimitSet,,,,,) = IStEth(ST_ETH).getStakeLimitFullInfo();
        if (isStakingLimitSet) {
            IStEth(ST_ETH).removeStakingLimit();
        }
        // solhint-disable-next-line
        console.log("Lido staking limit removed");
    }

    function grantPermission(address app, bytes32 role, address grantee) internal {
        IAragonACL acl = IAragonACL(DAO_ACL);
        if (!acl.hasPermission(grantee, app, role)) {
            // solhint-disable-next-line
            console.log("granting permission %x on %x to %x", uint256(role), app, grantee);
            address manager = acl.getPermissionManager(app, role);
            vm.prank(manager);
            acl.grantPermission(grantee, app, role);
            assert(acl.hasPermission(grantee, app, role));
        }
    }

    function supportVoteAndWaitTillDecided(uint256 voteId, address voter) internal {
        supportVote(voteId, voter);
        vm.warp(block.timestamp + IAragonVoting(DAO_VOTING).voteTime());
    }

    function supportVote(uint256 voteId, address voter) internal {
        vote(voteId, voter, true);
    }

    function vote(uint256 voteId, address voter, bool support) internal {
        // solhint-disable-next-line
        console.log("voting from %x at block %d", voter, block.number);
        vm.prank(voter);
        IAragonVoting(DAO_VOTING).vote(voteId, support, false);
    }

    // Creates vote with given description and script, votes for it, and waits until it can be executed
    function adoptVote(
        address voting,
        string memory description,
        bytes memory script
    ) internal returns (uint256 voteId) {
        uint256 ldoWhalePrivateKey = uint256(keccak256(abi.encodePacked("LDO_WHALE")));
        address ldoWhale = vm.addr(ldoWhalePrivateKey);
        if (IERC20(LDO_TOKEN).balanceOf(ldoWhale) < IAragonVoting(DAO_VOTING).minAcceptQuorumPct()) {
            setupLdoWhale(ldoWhale);
        }
        bytes memory voteScript = Utils.encodeEvmCallScript(
            voting, abi.encodeCall(IAragonVoting.newVote, (script, description, false, false))
        );

        voteId = IAragonVoting(voting).votesLength();

        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(voteScript);
        supportVoteAndWaitTillDecided(voteId, ldoWhale);
    }

    function executeVote(address voting, uint256 voteId) internal {
        IAragonVoting(voting).executeVote(voteId);
    }

    function predictDeployedAddress(address _origin, uint256 _nonce) public pure returns (address) {
        bytes memory data;
        if (_nonce == 0x00) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
        } else if (_nonce <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(uint8(_nonce)));
        } else if (_nonce <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce));
        } else if (_nonce <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce));
        } else if (_nonce <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce));
        }
        return address(uint160(uint256(keccak256(data))));
    }
}
