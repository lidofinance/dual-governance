// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

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
    event HashApproved(address to, bytes data, uint256 nonce, address indexed member);
    event ExecutionSuccess(bytes32 txHash);

    error ZeroQuorum();
    error NoQourum();
    error SenderIsNotMember();
    error SenderIsNotOwner();
    error NonceAlreadyUsed();

    address public nodeOperatorsRegistry;

    mapping(bytes32 txHash => uint256[] signers) signers;
    mapping(uint256 nodeOperatorId => mapping(bytes32 txHash => bool isApproved)) approves;

    uint256 public nonce;

    constructor(address _nodeOperatorsRegistry) {
        nodeOperatorsRegistry = _nodeOperatorsRegistry;
    }

    function execTransaction(address _to, bytes calldata _data, uint256 _value) public payable returns (bytes memory) {
        nonce++;
        bytes32 txHash = getTransactionHash(_to, _data, _value, nonce);

        if (hasQuorum(txHash) == false) {
            revert NoQourum();
        }
        return Address.functionCallWithValue(_to, _data, _value);
    }

    /**
     * @dev Marks a hash as approved. This can be used to validate a hash that is used by a signature.
     * @param _hashToApprove The hash that should be marked as approved for signatures that are verified by this contract.
     * @param _nodeOperatorId Node Operator ID of msg.sender
     */
    function approveHash(bytes32 _hashToApprove, uint256 _nodeOperatorId) public onlyNodeOperator(_nodeOperatorId) {
        approves[_nodeOperatorId][_hashToApprove] = true;
        signers[_hashToApprove].push(_nodeOperatorId);
    }

    /**
     * @dev Marks a hash as approved. This can be used to validate a hash that is used by a signature.
     * @param _hashToReject The hash that should be marked as approved for signatures that are verified by this contract.
     * @param _nodeOperatorId Node Operator ID of msg.sender
     */
    function rejectHash(bytes32 _hashToReject, uint256 _nodeOperatorId) public onlyNodeOperator(_nodeOperatorId) {
        approves[_nodeOperatorId][_hashToReject] = false;
        for (uint256 i = 0; i < signers[_hashToReject].length; ++i) {
            if (signers[_hashToReject][i] == _nodeOperatorId) {
                signers[_hashToReject][i] = signers[_hashToReject][signers[_hashToReject].length - 1];
                signers[_hashToReject].pop();
                break;
            }
        }
    }

    /// @dev Returns hash to be signed by owners.
    /// @param _to Destination address.
    /// @param _data Data payload.
    /// @param _nonce Transaction nonce.
    /// @return Transaction hash.
    function getTransactionHash(
        address _to,
        bytes calldata _data,
        uint256 _value,
        uint256 _nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_to, _data, _value, _nonce));
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
