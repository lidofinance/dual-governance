pragma solidity 0.8.23;

import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import "./mainnet-addresses.sol";
import "./interfaces.sol";


contract Target is Test {
    address internal _expectedCaller;

    function expectCalledBy(address expectedCaller) external {
        _expectedCaller = expectedCaller;
    }

    function doSmth(uint256 /* value */) external {
        if (_expectedCaller != address(0)) {
            assertEq(msg.sender, _expectedCaller, "unexpected caller");
            _expectedCaller = address(0);
        }
    }
}


library Utils {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    struct EvmScriptCall {
        address target;
        bytes data;
    }

    function selectFork() internal {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(18984396);
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
            script = bytes.concat(
                script,
                bytes20(call.target),
                bytes4(uint32(call.data.length)),
                call.data
            );
        }

        return script;
    }

    function setupLdoWhale(address addr) internal {
        vm.startPrank(DAO_AGENT);
        IERC20(LDO_TOKEN).transfer(addr, IERC20(LDO_TOKEN).balanceOf(DAO_AGENT));
        vm.stopPrank();
        console.log("LDO whale %x balance: %d at block %d", addr, IERC20(LDO_TOKEN).balanceOf(addr), block.number);
        assert(IERC20(LDO_TOKEN).balanceOf(addr) >= IAragonVoting(DAO_VOTING).minAcceptQuorumPct());
        // need to increase block number since MiniMe snapshotting relies on it
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 15);
    }

    function grantPermission(address app, bytes32 role, address grantee) internal {
        IAragonACL acl = IAragonACL(DAO_ACL);
        address manager = acl.getPermissionManager(app, role);
        vm.prank(manager);
        acl.grantPermission(grantee, app, role);
        assert(acl.hasPermission(grantee, app, role));
    }

    function supportVoteAndWaitTillDecided(uint256 voteId, address voter) internal {
        supportVote(voteId, voter);
        vm.warp(block.timestamp + IAragonVoting(DAO_VOTING).voteTime());
    }

    function supportVote(uint256 voteId, address voter) internal {
        vote(voteId, voter, true);
    }

    function vote(uint256 voteId, address voter, bool support) internal {
        console.log("voting from %x at block %d", voter, block.number);
        vm.prank(voter);
        IAragonVoting(DAO_VOTING).vote(voteId, support, false);
    }
}
