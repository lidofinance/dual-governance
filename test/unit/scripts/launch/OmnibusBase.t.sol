// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OmnibusBase} from "scripts/utils/OmnibusBase.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {IForwarder} from "scripts/launch/interfaces/IForwarder.sol";
import {IVoting} from "scripts/launch/interfaces/IVoting.sol";
import {CallsScriptBuilder} from "scripts/utils/CallsScriptBuilder.sol";

contract TestOmnibus is OmnibusBase {
    OmnibusBase.VoteItem[] private voteItems;

    constructor(address voting) OmnibusBase(voting) {}

    function setVoteItems(OmnibusBase.VoteItem[] memory _voteItems) external {
        delete voteItems;
        for (uint256 i = 0; i < _voteItems.length; i++) {
            voteItems.push(_voteItems[i]);
        }
    }

    function getVoteItems() public view override returns (VoteItem[] memory) {
        return voteItems;
    }

    function testForwardCall(
        address forwarder,
        address target,
        bytes calldata data
    ) external pure returns (ScriptCall memory) {
        return _forwardCall(forwarder, target, data);
    }

    function testVotingCall(address target, bytes calldata data) external pure returns (ScriptCall memory) {
        return _votingCall(target, data);
    }
}

contract OmnibusBaseTest is Test {
    using CallsScriptBuilder for CallsScriptBuilder.Context;

    uint256 public constant VOTE_ID = 42;
    uint256 public constant ITEMS_COUNT = 2;

    address public immutable VOTING_MOCK = makeAddr("VOTING_MOCK");
    address public immutable FORWARDER_MOCK = makeAddr("AGENT_MOCK");
    address public immutable TARGET_ADDRESS_MOCK_1 = makeAddr("TARGET_ADDRESS_MOCK_1");
    address public immutable TARGET_ADDRESS_MOCK_2 = makeAddr("TARGET_ADDRESS_MOCK_2");
    address public immutable TARGET_ADDRESS_MOCK_3 = makeAddr("TARGET_ADDRESS_MOCK_3");

    TestOmnibus public omnibusBase;

    function setUp() external {
        omnibusBase = new TestOmnibus(VOTING_MOCK);
    }

    function test_getEVMScript_HappyPath() external {
        OmnibusBase.VoteItem[] memory items = new OmnibusBase.VoteItem[](2);

        bytes memory callData1 = abi.encodeWithSignature("someFunction(uint256)", 123);
        items[0] = OmnibusBase.VoteItem({
            description: "First vote item",
            call: OmnibusBase.ScriptCall(TARGET_ADDRESS_MOCK_1, callData1)
        });

        bytes memory callData2 = abi.encodeWithSignature("anotherFunction(address)", address(0x456));
        items[1] = OmnibusBase.VoteItem({
            description: "Second vote item",
            call: OmnibusBase.ScriptCall(TARGET_ADDRESS_MOCK_2, callData2)
        });

        omnibusBase.setVoteItems(items);

        this.external__assertEVMScript(omnibusBase.getEVMScript(), items);
    }

    function test_ValidateVote_HappyPath() external {
        OmnibusBase.VoteItem[] memory items = new OmnibusBase.VoteItem[](3);

        bytes memory callData1 = abi.encodeWithSignature("someFunction(uint256)", 123);
        items[0] = OmnibusBase.VoteItem({
            description: "First vote item",
            call: OmnibusBase.ScriptCall(TARGET_ADDRESS_MOCK_1, callData1)
        });

        bytes memory callData2 = abi.encodeWithSignature("anotherFunction(address)", address(0x456));
        items[1] = OmnibusBase.VoteItem({
            description: "Second vote item",
            call: OmnibusBase.ScriptCall(TARGET_ADDRESS_MOCK_2, callData2)
        });

        bytes memory callData3 = abi.encodeWithSignature("anotherFunction()");
        items[2] = OmnibusBase.VoteItem({
            description: "Second vote item",
            call: OmnibusBase.ScriptCall(TARGET_ADDRESS_MOCK_3, callData3)
        });

        omnibusBase.setVoteItems(items);

        bytes memory script = omnibusBase.getEVMScript();

        this.external__assertEVMScript(script, items);

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

        vm.mockCall(VOTING_MOCK, abi.encodeWithSelector(IVoting.getVote.selector, VOTE_ID), mockReturn);

        assertTrue(omnibusBase.isValidVoteScript(VOTE_ID));
    }

    function test_validateVote_IvalidCallScript() external {
        OmnibusBase.VoteItem[] memory items = new OmnibusBase.VoteItem[](2);

        bytes memory callData1 = abi.encodeWithSignature("someFunction(uint256)", 123);
        items[0] = OmnibusBase.VoteItem({
            description: "First vote item",
            call: OmnibusBase.ScriptCall(TARGET_ADDRESS_MOCK_1, callData1)
        });

        bytes memory callData2 = abi.encodeWithSignature("anotherFunction(address)", address(0x456));
        items[1] = OmnibusBase.VoteItem({
            description: "Second vote item",
            call: OmnibusBase.ScriptCall(TARGET_ADDRESS_MOCK_2, callData2)
        });

        omnibusBase.setVoteItems(items);

        bytes memory differentScript = CallsScriptBuilder.create(items[1].call.to, items[1].call.data).addCall(
            items[0].call.to, items[0].call.data
        ).getResult();
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

        vm.mockCall(VOTING_MOCK, abi.encodeWithSelector(IVoting.getVote.selector, VOTE_ID), mockReturn);

        assertFalse(omnibusBase.isValidVoteScript(VOTE_ID));
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
            CallsScriptBuilder.create().getResult(), // empty script
            uint256(0) // phase
        );

        vm.mockCall(VOTING_MOCK, abi.encodeWithSelector(IVoting.getVote.selector, VOTE_ID), mockReturn);

        assertTrue(omnibusBase.isValidVoteScript(VOTE_ID));
    }

    function test_votingCall_HappyPath() external view {
        bytes memory callData = abi.encodeWithSignature("someFunction(uint256)", 123);
        OmnibusBase.ScriptCall memory call = omnibusBase.testVotingCall(TARGET_ADDRESS_MOCK_1, callData);

        assertEq(call.to, TARGET_ADDRESS_MOCK_1);
        assertEq(call.data, callData);
    }

    function test_forwardCall_HappyPath() external view {
        bytes memory callData = abi.encodeWithSignature("someFunction(uint256)", 123);
        OmnibusBase.ScriptCall memory call =
            omnibusBase.testForwardCall(FORWARDER_MOCK, TARGET_ADDRESS_MOCK_2, callData);

        assertEq(call.to, FORWARDER_MOCK);
        bytes memory encodedScript = CallsScriptBuilder.create(TARGET_ADDRESS_MOCK_2, callData).getResult();
        assertEq(call.data, abi.encodeCall(IForwarder.forward, (encodedScript)));
    }

    function external__assertEVMScript(bytes calldata script, OmnibusBase.VoteItem[] calldata items) external pure {
        if (items.length == 0) {
            // Empty script always equal to spec id
            assertEq(CallsScriptBuilder.create().getResult(), script);
        }

        uint256 specIdSize = 4;
        uint256 addrSize = 20;
        uint256 callDataLengthSize = 4;

        uint256 scriptIndex = specIdSize;
        for (uint256 i = 0; i < items.length; ++i) {
            OmnibusBase.VoteItem memory item = items[i];
            address target = address(bytes20(script[scriptIndex:scriptIndex + addrSize]));
            scriptIndex += addrSize;
            uint32 callDataLength = uint32(bytes4(script[scriptIndex:scriptIndex + callDataLengthSize]));
            scriptIndex += callDataLengthSize;
            bytes memory callData = script[scriptIndex:scriptIndex + callDataLength];
            scriptIndex += callDataLength;

            assertEq(target, item.call.to);
            assertEq(callData, item.call.data);
        }
        assertEq(scriptIndex, script.length);
    }
}
