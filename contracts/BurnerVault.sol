// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IWstETH {
    function unwrap(uint256 wstETHAmount) external returns (uint256);
}

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
}

interface IBurner {
    function requestBurnMyStETH(uint256 _stETHAmountToBurn) external;
}

contract BurnerVault {
    address immutable BURNER;
    address immutable ST_ETH;
    address immutable WST_ETH;

    constructor(address burner, address stEth, address wstEth) {
        BURNER = burner;
        ST_ETH = stEth;
        WST_ETH = wstEth;
    }

    function requestBurning() public {
        uint256 wstEthBalance = IERC20(WST_ETH).balanceOf(address(this));
        if (wstEthBalance > 0) {
            IWstETH(WST_ETH).unwrap(wstEthBalance);
        }

        uint256 stEthBalance = IERC20(ST_ETH).balanceOf(address(this));
        if (stEthBalance > 0) {
            IBurner(BURNER).requestBurnMyStETH(stEthBalance);
        }
    }
}
