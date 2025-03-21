// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OmnibusBase} from "scripts/upgrade/OmnibusBase.sol";
import {EvmScriptUtils} from "test/utils/evm-script-utils.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {IForwarder} from "scripts/upgrade/interfaces/IForwarder.sol";
import {IVoting} from "scripts/upgrade/interfaces/IVoting.sol";

contract TestOmnibus is OmnibusBase {
    address private constant forwarderAddress = address(0x123);
    address private constant votingAddress = address(0x456);
    uint256 private constant items = 2;

    OmnibusBase.VoteItem[] private voteItems;

    function setVoteItems(OmnibusBase.VoteItem[] memory _voteItems) external {
        delete voteItems;
        for (uint256 i = 0; i < _voteItems.length; i++) {
            voteItems.push(_voteItems[i]);
        }
    }

    function getVoteItems() public view override returns (VoteItem[] memory) {
        return voteItems;
    }

    function _voting() internal pure override returns (address) {
        return votingAddress;
    }

    function _forwarder() internal pure override returns (address) {
        return forwarderAddress;
    }

    function _voteItemsCount() internal pure override returns (uint256) {
        return items;
    }

    function testForwardCall(
        address target,
        bytes calldata data
    ) external pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return _forwardCall(target, data);
    }

    function testVotingCall(
        address target,
        bytes calldata data
    ) external pure returns (EvmScriptUtils.EvmScriptCall memory) {
        return _votingCall(target, data);
    }

    function testExecutorCall(address target, bytes calldata payload) external pure returns (ExternalCall memory) {
        return _executorCall(target, payload);
    }

    function testForwardCallFromExecutor(
        address target,
        bytes calldata data
    ) external pure returns (ExternalCall memory) {
        return _forwardCallFromExecutor(target, data);
    }

    function publicValidateVote(uint256 voteId) external view returns (bool) {
        return validateVote(voteId);
    }
}

contract OmnibusBaseTest is Test {
    address public constant VOTING = address(0x456);
    address public constant FORWARDER = address(0x123);
    address public constant TARGET_ADDRESS = address(0x123);
    uint256 public constant VOTE_ID = 42;
    uint256 public constant ITEMS_COUNT = 2;

    TestOmnibus public omnibusBase;

    function setUp() external {
        omnibusBase = new TestOmnibus();
    }

    function test_getEVMCallScript_HappyPath() external {
        OmnibusBase.VoteItem[] memory items = new OmnibusBase.VoteItem[](2);

        bytes memory callData1 = abi.encodeWithSignature("someFunction(uint256)", 123);
        items[0] = OmnibusBase.VoteItem({
            description: "First vote item",
            call: EvmScriptUtils.EvmScriptCall(TARGET_ADDRESS, callData1)
        });

        bytes memory callData2 = abi.encodeWithSignature("anotherFunction(address)", address(0x456));
        items[1] = OmnibusBase.VoteItem({
            description: "Second vote item",
            call: EvmScriptUtils.EvmScriptCall(TARGET_ADDRESS, callData2)
        });

        omnibusBase.setVoteItems(items);

        bytes memory actualScript = omnibusBase.getEVMCallScript();

        assertTrue(actualScript.length > 0);
        assertTrue(_contains(actualScript, abi.encodePacked(TARGET_ADDRESS)));
        assertTrue(_contains(actualScript, callData1));
        assertTrue(_contains(actualScript, callData2));
    }

    function test_ValidateVote_HappyPath() external {
        OmnibusBase.VoteItem[] memory items = new OmnibusBase.VoteItem[](2);

        bytes memory callData1 = abi.encodeWithSignature("someFunction(uint256)", 123);
        items[0] = OmnibusBase.VoteItem({
            description: "First vote item",
            call: EvmScriptUtils.EvmScriptCall(TARGET_ADDRESS, callData1)
        });

        bytes memory callData2 = abi.encodeWithSignature("anotherFunction(address)", address(0x456));
        items[1] = OmnibusBase.VoteItem({
            description: "Second vote item",
            call: EvmScriptUtils.EvmScriptCall(TARGET_ADDRESS, callData2)
        });

        omnibusBase.setVoteItems(items);

        bytes memory script = omnibusBase.getEVMCallScript();

        bytes memory mockReturn = abi.encode(
            true, // open
            false, // executed
            uint64(0), // startDate
            uint64(0), // snapshotBlock
            uint64(0), // supportRequired
            uint64(0), // minAcceptQuorum
            uint256(0), // yea
            uint256(0), // nay
            uint256(0), // votingPower
            script, // script
            uint256(0) // phase
        );

        vm.mockCall(VOTING, abi.encodeWithSelector(IVoting.getVote.selector, VOTE_ID), mockReturn);

        bool isValid = omnibusBase.publicValidateVote(VOTE_ID);
        assertTrue(isValid);
    }

    function test_validateVote_IvalidCallScript() external {
        OmnibusBase.VoteItem[] memory items = new OmnibusBase.VoteItem[](2);

        bytes memory callData1 = abi.encodeWithSignature("someFunction(uint256)", 123);
        items[0] = OmnibusBase.VoteItem({
            description: "First vote item",
            call: EvmScriptUtils.EvmScriptCall(TARGET_ADDRESS, callData1)
        });

        bytes memory callData2 = abi.encodeWithSignature("anotherFunction(address)", address(0x456));
        items[1] = OmnibusBase.VoteItem({
            description: "Second vote item",
            call: EvmScriptUtils.EvmScriptCall(TARGET_ADDRESS, callData2)
        });

        omnibusBase.setVoteItems(items);

        bytes memory differentScript = abi.encodeWithSignature("differentFunction()");
        bytes memory mockReturn = abi.encode(
            true, // open
            false, // executed
            uint64(0), // startDate
            uint64(0), // snapshotBlock
            uint64(0), // supportRequired
            uint64(0), // minAcceptQuorum
            uint256(0), // yea
            uint256(0), // nay
            uint256(0), // votingPower
            differentScript, // script
            uint256(0) // phase
        );

        vm.mockCall(VOTING, abi.encodeWithSelector(IVoting.getVote.selector, VOTE_ID), mockReturn);

        assertFalse(omnibusBase.publicValidateVote(VOTE_ID));
    }

    function test_validateVote_EmptyScript() external {
        omnibusBase.setVoteItems(new OmnibusBase.VoteItem[](0));

        bytes memory mockReturn = abi.encode(
            true, // open
            false, // executed
            uint64(0), // startDate
            uint64(0), // snapshotBlock
            uint64(0), // supportRequired
            uint64(0), // minAcceptQuorum
            uint256(0), // yea
            uint256(0), // nay
            uint256(0), // votingPower
            bytes(""), // empty script
            uint256(0) // phase
        );

        vm.mockCall(VOTING, abi.encodeWithSelector(IVoting.getVote.selector, VOTE_ID), mockReturn);

        omnibusBase.publicValidateVote(VOTE_ID);
    }

    function test_VotingCall_HappyPath() external view {
        bytes memory callData = abi.encodeWithSignature("someFunction(uint256)", 123);
        EvmScriptUtils.EvmScriptCall memory call = omnibusBase.testVotingCall(TARGET_ADDRESS, callData);

        assertEq(call.target, TARGET_ADDRESS);
        assertEq(call.data, callData);
    }

    function test_ForwardCall_HappyPath() external view {
        bytes memory callData = abi.encodeWithSignature("someFunction(uint256)", 123);
        EvmScriptUtils.EvmScriptCall memory call = omnibusBase.testForwardCall(TARGET_ADDRESS, callData);

        assertEq(call.target, FORWARDER);

        bytes memory encodedScript = EvmScriptUtils.encodeEvmCallScript(TARGET_ADDRESS, callData);
        bytes memory expectedData = abi.encodeCall(IForwarder.forward, (encodedScript));
        assertEq(call.data, expectedData);
    }

    function test_ExecutorCall_HappyPath() external view {
        bytes memory payload = abi.encodeWithSignature("someFunction(uint256)", 123);
        ExternalCall memory call = omnibusBase.testExecutorCall(TARGET_ADDRESS, payload);

        assertEq(call.target, TARGET_ADDRESS);
        assertEq(call.value, 0);
        assertEq(call.payload, payload);
    }

    function test_ForwardCallFromExecutor_HappyPath() external view {
        bytes memory callData = abi.encodeWithSignature("someFunction(uint256)", 123);
        ExternalCall memory call = omnibusBase.testForwardCallFromExecutor(TARGET_ADDRESS, callData);

        assertEq(call.target, FORWARDER);
        assertEq(call.value, 0);

        bytes memory encodedScript = EvmScriptUtils.encodeEvmCallScript(TARGET_ADDRESS, callData);
        bytes memory expectedPayload = abi.encodeCall(IForwarder.forward, (encodedScript));
        assertEq(call.payload, expectedPayload);
    }

    function _contains(bytes memory source, bytes memory search) internal pure returns (bool) {
        if (search.length > source.length) return false;
        for (uint256 i = 0; i <= source.length - search.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < search.length; j++) {
                if (source[i + j] != search[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
