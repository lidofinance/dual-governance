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

    function getCurrentStakeLimit() external pure returns (uint256) {
        return type(uint256).max;
    }

    function rebaseTotalPooledEther(PercentD16 rebaseFactor) public {
        _totalPooledEther = rebaseFactor.toUint256() * _totalPooledEther / HUNDRED_PERCENT_D16;
    }

    function setTotalPooledEther(uint256 ethAmount) public {
        _totalPooledEther = ethAmount;
    }

    function mint(address account, uint256 ethAmount) external {
        _mint(account, ethAmount);
    }

    function burn(address account, uint256 ethAmount) external {
        uint256 sharesToBurn = this.getSharesByPooledEth(ethAmount);
        _burnShares(account, sharesToBurn);
        _totalPooledEther -= ethAmount;
        _emitTransferEvents(account, address(0), ethAmount, sharesToBurn);
    }

    function submit(address /* _referral */ ) external payable returns (uint256) {
        return _mint(msg.sender, msg.value);
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }

    function _mint(address account, uint256 ethAmount) internal returns (uint256 sharesAmount) {
        sharesAmount = getSharesByPooledEth(ethAmount);

        _mintShares(account, sharesAmount);
        _totalPooledEther += ethAmount;

        _emitTransferAfterMintingShares(account, sharesAmount);
    }
}
