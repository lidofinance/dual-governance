// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * Simplified abstract model of the Escrow contract. Includes the following simplifications:
 *
 * - To make calculations simpler and focus on the core logic, this model uses a single,
 *   non-rebasable fakeETH token to signal support instead of stETH, wstETH and unstETH.
 *
 * - The model does not interact with the WithdrawalQueue, instead only simulates it by
 *   keeping track of withdrawal requests internally.
 *
 * - Replaces requestNextWithdrawalBatch and claimNextWithdrawalBatch with simpler non-batch
 *   requestNextWithdrawal and claimNextWithdrawal functions that process a single request.
 */
contract Escrow {
    enum State {
        SignallingEscrow,
        RageQuitEscrow
    }

    enum WithdrawalRequestStatus {
        Requested,
        Finalized,
        Claimed
    }

    State public currentState;

    address public dualGovernance;
    ERC20 public fakeETH;
    mapping(address => uint256) public balances;
    uint256 public totalStaked;
    uint256 public totalWithdrawalRequestAmount;
    uint256 public totalClaimedEthAmount;
    uint256 public totalWithdrawnPostRageQuit;
    mapping(address => uint256) public lastLockedTimes; // Track the last time tokens were locked by each user
    uint256 public withdrawalRequestCount;
    mapping(uint256 => WithdrawalRequestStatus) public withdrawalRequestStatus;
    mapping(uint256 => uint256) public withdrawalRequestAmount;
    uint256 public rageQuitExtensionDelayPeriodEnd;
    uint256 public rageQuitSequenceNumber;
    uint256 public rageQuitEthClaimTimelockStart;

    // Constants
    uint256 public constant RAGE_QUIT_EXTENSION_DELAY = 7 days;
    uint256 public constant RAGE_QUIT_ETH_CLAIM_MIN_TIMELOCK = 60 days;
    uint256 public constant RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_START_SEQ_NUMBER = 2;
    uint256 public constant RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFFS_0 = 0;
    uint256 public constant RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFFS_1 = 1; // Placeholder value
    uint256 public constant RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFFS_2 = 2; // Placeholder value
    uint256 public constant SIGNALLING_ESCROW_MIN_LOCK_TIME = 5 hours; // Minimum time that funds must be locked before they can be unlocked

    uint256 public constant MIN_WITHDRAWAL_AMOUNT = 100;
    uint256 public constant MAX_WITHDRAWAL_AMOUNT = 1000 * 1e18;

    constructor(address _dualGovernance, address _fakeETH) {
        currentState = State.SignallingEscrow;
        dualGovernance = _dualGovernance;
        fakeETH = ERC20(_fakeETH);
    }

    // Locks a specified amount of tokens.
    function lock(uint256 amount) external {
        require(currentState == State.SignallingEscrow, "Cannot lock in current state.");
        require(amount > 0, "Amount must be greater than zero.");
        require(fakeETH.allowance(msg.sender, address(this)) >= amount, "Need allowance to transfer tokens.");
        require(fakeETH.balanceOf(msg.sender) >= amount, "Not enough balance.");
        fakeETH.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        totalStaked += amount;
        lastLockedTimes[msg.sender] = block.timestamp;
    }

    // Unlocks a specified amount of tokens.
    function unlock(uint256 amount) external {
        require(currentState == State.SignallingEscrow, "Cannot unlock in current state.");
        require(
            block.timestamp >= lastLockedTimes[msg.sender] + SIGNALLING_ESCROW_MIN_LOCK_TIME, "Lock period not expired."
        );
        require(balances[msg.sender] >= amount, "Insufficient balances.");
        fakeETH.transfer(msg.sender, amount);
        balances[msg.sender] -= amount;
        totalStaked -= amount;
    }

    // Returns total rage quit support as a percentage of the total supply.
    function getRageQuitSupport() external view returns (uint256) {
        return totalStaked * 10 ** 18 / fakeETH.totalSupply();
    }

    // Transitions the escrow to the RageQuitEscrow state and initiates withdrawal processes.
    function startRageQuit() external {
        require(msg.sender == dualGovernance, "Only DualGovernance can start rage quit.");
        require(currentState == State.SignallingEscrow, "Already in RageQuit or invalid state.");
        currentState = State.RageQuitEscrow;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // Initiates a withdrawal request.
    function requestNextWithdrawal() external {
        require(currentState == State.RageQuitEscrow, "Withdrawal only allowed in RageQuit state.");
        require(
            totalStaked - totalWithdrawalRequestAmount >= MIN_WITHDRAWAL_AMOUNT,
            "Withdrawal requests already concluded."
        );

        uint256 amount = min(totalStaked, MAX_WITHDRAWAL_AMOUNT);

        withdrawalRequestStatus[withdrawalRequestCount] = WithdrawalRequestStatus.Requested;
        withdrawalRequestAmount[withdrawalRequestCount] = amount;
        withdrawalRequestCount++;

        totalWithdrawalRequestAmount += amount;
    }

    // Claims the ETH associated with a finalized withdrawal request.
    function claimNextWithdrawal(uint256 requestId, uint256 hint) external {
        require(currentState == State.RageQuitEscrow, "Withdrawal only allowed in RageQuit state.");
        require(
            withdrawalRequestStatus[requestId] == WithdrawalRequestStatus.Finalized,
            "Withdrawal request must be finalized and not claimed."
        );

        withdrawalRequestStatus[requestId] = WithdrawalRequestStatus.Claimed;
        totalClaimedEthAmount += withdrawalRequestAmount[requestId];

        if (totalStaked - totalClaimedEthAmount < MIN_WITHDRAWAL_AMOUNT) {
            rageQuitExtensionDelayPeriodEnd = block.timestamp + RAGE_QUIT_EXTENSION_DELAY;
        }
    }

    // Check if the RageQuitExtensionDelay has passed since all withdrawals were finalized.
    function isRageQuitFinalized() public view returns (bool) {
        return currentState == State.RageQuitEscrow && totalStaked - totalClaimedEthAmount < MIN_WITHDRAWAL_AMOUNT
            && rageQuitExtensionDelayPeriodEnd < block.timestamp;
    }

    // Called by the governance to initiate ETH claim timelock.
    function startEthClaimTimelock(uint256 _rageQuitSequenceNumber) external {
        require(msg.sender == dualGovernance, "Only DualGovernance can start ETH claim timelock.");

        rageQuitSequenceNumber = _rageQuitSequenceNumber;
        rageQuitEthClaimTimelockStart = block.timestamp;
    }

    // Timelock between exit from Rage Quit state and when stakers are allowed to withdraw funds.
    // Quadratic on the rage quit sequence number.
    function rageQuitEthClaimTimelock() public view returns (uint256) {
        uint256 ethClaimTimelock = RAGE_QUIT_ETH_CLAIM_MIN_TIMELOCK;

        if (rageQuitSequenceNumber >= RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_START_SEQ_NUMBER) {
            uint256 c0 = RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFFS_0;
            uint256 c1 = RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFFS_1;
            uint256 c2 = RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFFS_2;

            uint256 x = rageQuitSequenceNumber - RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_START_SEQ_NUMBER;

            ethClaimTimelock += c0 + c1 * x + c2 * (x ** 2);
        }

        return ethClaimTimelock;
    }

    // Withdraws all locked funds after the RageQuit delay has passed.
    function withdraw() public {
        require(currentState == State.RageQuitEscrow, "Withdrawal only allowed in RageQuit state.");
        require(isRageQuitFinalized(), "Rage quit process not yet finalized.");
        require(
            rageQuitEthClaimTimelockStart + rageQuitEthClaimTimelock() < block.timestamp,
            "Rage quit ETH claim timelock has not elapsed."
        );
        uint256 stakedAmount = balances[msg.sender];
        require(stakedAmount > 0, "No funds to withdraw.");
        uint256 totalEth = address(this).balance; // Total ETH held by contract
        require(totalEth > stakedAmount, "Not enough balance.");

        balances[msg.sender] = 0;

        // Transfer ETH equivalent
        payable(msg.sender).transfer(stakedAmount);
    }
}
