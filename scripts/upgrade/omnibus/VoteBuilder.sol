// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/Strings.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {EvmScriptUtils} from "scripts/utils/evm-script-utils.sol";

import {Omnibus} from "./Omnibus.sol";

library VoteBuilder {
    struct State {
        uint256 index;
        Omnibus.VoteItem[] items;
    }

    function create(uint256 count) internal pure returns (State memory res) {
        res.items = new Omnibus.VoteItem[](count);
    }

    function add(
        State memory res,
        string memory description,
        EvmScriptUtils.EvmScriptCall memory call
    ) internal pure returns (State memory) {
        string memory indexNumber = string.concat(Strings.toString(res.index + 1), ". ");
        res.items[res.index++] = Omnibus.VoteItem({description: string.concat(indexNumber, description), call: call});
        return res;
    }
}
