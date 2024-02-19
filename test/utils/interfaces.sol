pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

struct WithdrawalRequestStatus {
    uint256 amountOfStETH;
    uint256 amountOfShares;
    address owner;
    uint256 timestamp;
    bool isFinalized;
    bool isClaimed;
}

interface IAragonAgent {
    function RUN_SCRIPT_ROLE() external pure returns (bytes32);
}

interface IAragonVoting {
    function newVote(
        bytes calldata script,
        string calldata metadata,
        bool castVote,
        bool executesIfDecided_deprecated
    ) external returns (uint256 voteId);

    function CREATE_VOTES_ROLE() external view returns (bytes32);
    function vote(uint256 voteId, bool support, bool executesIfDecided_deprecated) external;
    function canExecute(uint256 voteId) external view returns (bool);
    function executeVote(uint256 voteId) external;
    function votesLength() external view returns (uint256);
    function voteTime() external view returns (uint64);
    function minAcceptQuorumPct() external view returns (uint64);
}

interface IAragonACL {
    function getPermissionManager(address app, bytes32 role) external view returns (address);
    function grantPermission(address grantee, address app, bytes32 role) external;
    function hasPermission(address who, address app, bytes32 role) external view returns (bool);
}

interface IAragonForwarder {
    function forward(bytes memory evmScript) external;
}

interface IStEth {
    function STAKING_CONTROL_ROLE() external view returns (bytes32);
    function submit(address referral) external payable returns (uint256);
    function removeStakingLimit() external;
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
}

interface IWstETH {
    function wrap(uint256 stETHAmount) external returns (uint256);
    function unwrap(uint256 wstETHAmount) external returns (uint256);
}

interface IWithdrawalQueue {
    function PAUSE_ROLE() external pure returns (bytes32);
    function RESUME_ROLE() external pure returns (bytes32);

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);
    function requestWithdrawalsWstETH(uint256[] calldata amounts, address owner) external returns (uint256[] memory);
    function requestWithdrawals(uint256[] calldata amounts, address owner) external returns (uint256[] memory);
    function setApprovalForAll(address _operator, bool _approved) external;
    function balanceOf(address owner) external view returns (uint256);
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);
    function getLastRequestId() external view returns (uint256);
    function findCheckpointHints(
        uint256[] calldata _requestIds,
        uint256 _firstIndex,
        uint256 _lastIndex
    ) external view returns (uint256[] memory hintIds);
    function getLastCheckpointIndex() external view returns (uint256);
    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external;
    function getLastFinalizedRequestId() external view returns (uint256);
    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function isPaused() external view returns (bool);
}
