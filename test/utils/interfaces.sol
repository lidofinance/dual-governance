pragma solidity 0.8.26;

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

interface IDangerousContract {
    function doRegularStaff(uint256 magic) external;
    function doRugPool() external;
    function doControversialStaff() external;
}
