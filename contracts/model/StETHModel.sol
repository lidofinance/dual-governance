pragma solidity 0.8.23;

contract StETHModel {
    uint256 private totalPooledEther;
    uint256 private totalShares;
    mapping(address => uint256) private shares;
    mapping(address => mapping(address => uint256)) private allowances;

    uint256 internal constant INFINITE_ALLOWANCE = type(uint256).max;

    function setTotalPooledEther(uint256 _value) external {
        // Assumption: totalPooledEther is not zero
        require(_value != 0);
        totalPooledEther = _value;
    }

    function setTotalShares(uint256 _value) external {
        // Assumption: totalShares is not zero
        require(_value != 0);
        totalShares = _value;
    }

    function setShares(address _account, uint256 _value) external {
        shares[_account] = _value;
    }

    function setAllowances(address _owner, address _spender, uint256 _amount) external {
        allowances[_owner][_spender] = _amount;
    }

    function totalSupply() external view returns (uint256) {
        // Assumption: totalPooledEther is not zero
        require(totalPooledEther != 0);
        return totalPooledEther;
    }

    function getTotalPooledEther() external view returns (uint256) {
        // Assumption: totalPooledEther is not zero
        require(totalPooledEther != 0);
        return totalPooledEther;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return getPooledEthByShares(shares[_account]);
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        _spendAllowance(_sender, msg.sender, _amount);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool) {
        _approve(msg.sender, _spender, allowances[msg.sender][_spender] + _addedValue);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool) {
        uint256 currentAllowance = allowances[msg.sender][_spender];
        require(currentAllowance >= _subtractedValue, "ALLOWANCE_BELOW_ZERO");
        _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
        return true;
    }

    function getTotalShares() external view returns (uint256) {
        // Assumption: totalShares is not zero
        require(totalShares != 0);
        return totalShares;
    }

    function sharesOf(address _account) external view returns (uint256) {
        return shares[_account];
    }

    function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
        // Assumption: totalPooledEther and totalShares are not zero
        require(totalPooledEther != 0);
        require(totalShares != 0);
        // Assumption: no overflow
        unchecked {
            require((_ethAmount * totalShares) / totalShares == _ethAmount);
        }
        return _ethAmount * totalShares / totalPooledEther;
    }

    function getPooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
        // Assumption: totalPooledEther and totalShares are not zero
        require(totalPooledEther != 0);
        require(totalShares != 0);
        // Assumption: no overflow
        unchecked {
            require((_sharesAmount * totalPooledEther) / totalPooledEther == _sharesAmount);
        }
        return _sharesAmount * totalPooledEther / totalShares;
    }

    function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256) {
        _transferShares(msg.sender, _recipient, _sharesAmount);
        uint256 tokensAmount = getPooledEthByShares(_sharesAmount);
        return tokensAmount;
    }

    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        uint256 tokensAmount = getPooledEthByShares(_sharesAmount);
        _spendAllowance(_sender, msg.sender, tokensAmount);
        _transferShares(_sender, _recipient, _sharesAmount);
        return tokensAmount;
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) internal {
        uint256 _sharesToTransfer = getSharesByPooledEth(_amount);
        _transferShares(_sender, _recipient, _sharesToTransfer);
    }

    function _approve(address _owner, address _spender, uint256 _amount) internal {
        require(_owner != address(0), "APPROVE_FROM_ZERO_ADDR");
        require(_spender != address(0), "APPROVE_TO_ZERO_ADDR");

        allowances[_owner][_spender] = _amount;
    }

    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal {
        uint256 currentAllowance = allowances[_owner][_spender];
        if (currentAllowance != INFINITE_ALLOWANCE) {
            require(currentAllowance >= _amount, "ALLOWANCE_EXCEEDED");
            _approve(_owner, _spender, currentAllowance - _amount);
        }
    }

    function _transferShares(address _sender, address _recipient, uint256 _sharesAmount) internal {
        require(_sender != address(0), "TRANSFER_FROM_ZERO_ADDR");
        require(_recipient != address(0), "TRANSFER_TO_ZERO_ADDR");
        require(_recipient != address(this), "TRANSFER_TO_STETH_CONTRACT");

        uint256 currentSenderShares = shares[_sender];
        require(_sharesAmount <= currentSenderShares, "BALANCE_EXCEEDED");

        shares[_sender] = currentSenderShares - _sharesAmount;
        shares[_recipient] = shares[_recipient] + _sharesAmount;
    }
}
