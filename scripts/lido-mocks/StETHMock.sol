// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PercentD16, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";
import {StETHBase} from "./StETHBase.sol";

contract StETHMock is StETHBase {
    constructor() {
        _totalPooledEther = 100 wei;
        _mintInitialShares(100 wei);
    }

    function name() external pure override returns (string memory) {
        return "StETHMock";
    }

    function symbol() external pure override returns (string memory) {
        return "MStETH";
    }

    function rebaseTotalPooledEther(PercentD16 rebaseFactor) public {
        _totalPooledEther = rebaseFactor.toUint256() * _totalPooledEther / HUNDRED_PERCENT_D16;
    }

    function setTotalPooledEther(uint256 ethAmount) public {
        _totalPooledEther = ethAmount;
    }

    function mint(address account, uint256 ethAmount) external {
        uint256 sharesAmount = getSharesByPooledEth(ethAmount);

        _mintShares(account, sharesAmount);
        _totalPooledEther += ethAmount;

        _emitTransferAfterMintingShares(account, sharesAmount);
    }

    function burn(address account, uint256 ethAmount) external {
        uint256 sharesToBurn = this.getSharesByPooledEth(ethAmount);
        _burnShares(account, sharesToBurn);
        _totalPooledEther -= ethAmount;
        _emitTransferEvents(account, address(0), ethAmount, sharesToBurn);
    }
}
