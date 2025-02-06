// Represents a symbolic/dummy ERC20 token

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

contract DummyERC20MintBurn {
    uint256 t;
    mapping(address => uint256) b;
    mapping(address => mapping(address => uint256)) a;

    string public name;
    string public symbol;
    uint256 public decimals;

    function myAddress() external view returns (address) {
        return address(this);
    }

    function totalSupply() external view returns (uint256) {
        return t;
    }

    function balanceOf(address account) external view returns (uint256) {
        return b[account];
    }

    function _mint(address to, uint256 amount) internal {
        b[to] += amount;
        t += amount;
    }

    function _burn(address to, uint256 amount) internal {
        b[to] -= amount;
        t -= amount;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        b[msg.sender] -= amount;
        b[recipient] += amount;

        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return a[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        a[msg.sender][spender] = amount;

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        b[sender] -= amount;
        b[recipient] += amount;
        a[sender][msg.sender] -= amount;

        return true;
    }
}
