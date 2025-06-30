pragma solidity >=0.8.0;

import "../../../contracts/interfaces/IStETH.sol";

contract DummyStETH is IStETH {
    uint256 internal totalShares;
    mapping(address => uint256) private shares;
    mapping(address => mapping(address => uint256)) private allowances;

    function getTotalShares() external view returns (uint256) {
        return totalShares;
    }

    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256) {
        return ethAmount * 3 / 5;
    }

    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256) {
        return sharesAmount * 5 / 3;
    }

    function transferShares(address to, uint256 amount) external returns (uint256) {
        _transferShares(msg.sender, to, amount);
        // 3/5 is used as an underapproximation here
        // uint256 tokensAmount = getPooledEthByShares(amount);
        uint256 tokensAmount = amount * 3 / 5;
        return tokensAmount;
    }

    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        uint256 tokensAmount = _sharesAmount * 5 / 3;
        _spendAllowance(_sender, msg.sender, _sharesAmount);
        _transferShares(_sender, _recipient, _sharesAmount);
        return tokensAmount;
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        _spendAllowance(_sender, msg.sender, _amount);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool) {
        _approve(msg.sender, _spender, allowances[msg.sender][_spender] + (_addedValue));
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool) {
        uint256 currentAllowance = allowances[msg.sender][_spender];
        require(currentAllowance >= _subtractedValue, "ALLOWANCE_BELOW_ZERO");
        _approve(msg.sender, _spender, currentAllowance - (_subtractedValue));
        return true;
    }

    function totalSupply() external view returns (uint256) {
        return totalShares * 5 / 3;
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function balanceOf(address _account) external view returns (uint256) {
        // return getPooledEthByShares(_sharesOf(_account));
        return _sharesOf(_account) * 5 / 3;
    }

    function _sharesOf(address account) internal view returns (uint256) {
        return shares[account];
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        uint256 sharesToTransfer = amount * 3 / 5;
        _transferShares(sender, recipient, sharesToTransfer);
    }

    function _transferShares(address sender, address recipient, uint256 sharesAmount) internal {
        require(sender != address(0), "TRANSFER_FROM_ZERO_ADDR");
        require(recipient != address(0), "TRANSFER_TO_ZERO_ADDR");
        require(recipient != address(this), "TRANSFER_TO_STETH_CONTRACT");

        uint256 currentSenderShares = shares[sender];
        require(sharesAmount <= currentSenderShares, "BALANCE_EXCEEDED");

        shares[sender] = currentSenderShares - (sharesAmount);
        shares[recipient] = shares[recipient] + (sharesAmount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowances[owner][spender];
        require(currentAllowance >= amount, "ALLOWANCE_EXCEEDED");
        _approve(owner, spender, currentAllowance - amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "APPROVE_FROM_ZERO_ADDR");
        require(spender != address(0), "APPROVE_TO_ZERO_ADDR");

        allowances[owner][spender] = amount;
    }
}
