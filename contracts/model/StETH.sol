pragma solidity 0.8.23;

contract StETH {
    uint256 public totalPooledEther;
    uint256 public totalShares;
    mapping(address => uint256) public shares;
    mapping(address => mapping(address => uint256)) public allowances;

    function setTotalPooledEther(uint256 _value) external {
        totalPooledEther = _value;
    }

    function setTotalShares(uint256 _value) external {
        totalShares = _value;
    }

    function setShares(address _account, uint256 _value) external {
        shares[_account] = _value;
    }

    function totalSupply() external view returns (uint256) {
        return totalPooledEther;
    }

    function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
        return _ethAmount * totalShares / totalPooledEther;
    }

    function getPooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
        return _sharesAmount * totalPooledEther / totalShares;
    }

    function _sharesOf(address _account) internal view returns (uint256) {
        return shares[_account];
    }

    function sharesOf(address _account) external view returns (uint256) {
        return _sharesOf(_account);
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function balanceOf(address _account) external view returns (uint256) {
        return getPooledEthByShares(_sharesOf(_account));
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

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        uint256 sharesAmount = getSharesByPooledEth(_amount);
        _transferShares(msg.sender, _recipient, sharesAmount);
        return true;
    }

    function transferShares(address _recipient, uint256 _sharesAmount) external returns (bool) {
        _transferShares(msg.sender, _recipient, _sharesAmount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 currentAllowance = allowances[_sender][msg.sender];
        require(currentAllowance >= _amount, "ALLOWANCE_EXCEEDED");

        uint256 sharesAmount = getSharesByPooledEth(_amount);

        _transferShares(_sender, _recipient, sharesAmount);
        allowances[_sender][msg.sender] = currentAllowance - _amount;

        return true;
    }

    function _approve(address _owner, address _spender, uint256 _amount) internal {
        require(_owner != address(0), "APPROVE_FROM_ZERO_ADDR");
        require(_spender != address(0), "APPROVE_TO_ZERO_ADDR");

        allowances[_owner][_spender] = _amount;
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }
}
