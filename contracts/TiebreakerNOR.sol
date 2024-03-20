// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface INodeOperatorsRegistry {
    function getNodeOperator(
        uint256 _id,
        bool _fullInfo
    )
        external
        view
        returns (
            bool active,
            string memory name,
            address rewardAddress,
            uint64 stakingLimit,
            uint64 stoppedValidators,
            uint64 totalSigningKeys,
            uint64 usedSigningKeys
        );

    function getNodeOperatorsCount() external view returns (uint256);
    function getActiveNodeOperatorsCount() external view returns (uint256);
    function getNodeOperatorIsActive(uint256 _nodeOperatorId) external view returns (bool);
}

/**
 * A contract provides ability to execute locked proposals.
 */
contract TiebreakerNOR {
    event HashApproved(bytes32 indexed approvedHash, uint256 nodeOperatorId, address indexed owner);
    event ExecutionSuccess(bytes32 txHash);
    event MemberAdded(address indexed newMember);

    error Initialized();
    error IsNotMember();
    error ZeroQuorum();
    error NoQourum();
    error SenderIsNotMember();
    error SenderIsNotOwner();
    error ExecutionFailed();

    bool isInitialized;
    address public nodeOperatorsRegistry;

    mapping(uint256 => mapping(bytes32 => bool)) public approves;
    mapping(bytes32 => uint256[]) signers;

    uint256 public nonce;

    function initialize(address _nodeOperatorsRegistry) public {
        if (isInitialized) {
            revert Initialized();
        }

        isInitialized = true;
        nodeOperatorsRegistry = _nodeOperatorsRegistry;
    }

    function execTransaction(address _to, bytes calldata _data) public payable returns (bool, bytes memory) {
        nonce++;
        bytes32 txHash = getTransactionHash(_to, _data, nonce);

        if (hasQuorum(txHash) == false) {
            revert NoQourum();
        }

        (bool success, bytes memory data) = _to.call(_data);
        if (success == false) {
            revert ExecutionFailed();
        }

        emit ExecutionSuccess(txHash);

        return (success, data);
    }

    /**
     * @dev Marks a hash as approved. This can be used to validate a hash that is used by a signature.
     * @param _hashToApprove The hash that should be marked as approved for signatures that are verified by this contract.
     */
    function approveHash(bytes32 _hashToApprove, uint256 _nodeOperatorId) public onlyNodeOperator(_nodeOperatorId) {
        approves[_nodeOperatorId][_hashToApprove] = true;
        signers[_hashToApprove].push(_nodeOperatorId);
        emit HashApproved(_hashToApprove, _nodeOperatorId, msg.sender);
    }

    /// @dev Returns hash to be signed by owners.
    /// @param _to Destination address.
    /// @param _data Data payload.
    /// @param _nonce Transaction nonce.
    /// @return Transaction hash.
    function getTransactionHash(address _to, bytes calldata _data, uint256 _nonce) public pure returns (bytes32) {
        return keccak256(abi.encode(_to, _data, _nonce));
    }

    function hasQuorum(bytes32 _txHash) public view returns (bool) {
        uint256 activeNOCount = INodeOperatorsRegistry(nodeOperatorsRegistry).getActiveNodeOperatorsCount();
        uint256 quorum = activeNOCount / 2 + 1;

        uint256 supportersCount = 0;

        for (uint256 i = 0; i < signers[_txHash].length; ++i) {
            if (INodeOperatorsRegistry(nodeOperatorsRegistry).getNodeOperatorIsActive(signers[_txHash][i]) == true) {
                supportersCount++;
            }
        }

        return supportersCount >= quorum;
    }

    modifier onlyNodeOperator(uint256 _nodeOperatorId) {
        (
            bool active,
            , //string memory name,
            address rewardAddress,
            , //uint64 stakingLimit,
            , //uint64 stoppedValidators,
            , //uint64 totalSigningKeys,
                //uint64 usedSigningKeys
        ) = INodeOperatorsRegistry(nodeOperatorsRegistry).getNodeOperator(_nodeOperatorId, false);

        if (active == false || msg.sender != rewardAddress) {
            revert SenderIsNotMember();
        }
        _;
    }
}
