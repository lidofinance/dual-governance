// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * A contract provides ability to execute .
 */
contract Tiebreaker {
    event HashApproved(bytes32 indexed approvedHash, address indexed owner);
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

    address public owner;

    address[] membersList;
    mapping(address => bool) members;
    uint256 quorum;

    mapping(address => mapping(bytes32 => bool)) public approves;
    mapping(bytes32 => address[]) signers;

    uint256 public nonce;

    function initialize(address _owner, address[] memory _members, uint256 _quorum) public {
        if (isInitialized) {
            revert Initialized();
        }

        isInitialized = true;

        quorum = _quorum;
        owner = _owner;

        for (uint256 i = 0; i < _members.length; i++) {
            _addMember(_members[i]);
        }
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
     */
    function approveHash(bytes32 _hashToApprove) public onlyMember {
        approves[msg.sender][_hashToApprove] = true;
        signers[_hashToApprove].push(msg.sender);
        emit HashApproved(_hashToApprove, msg.sender);
    }

    /**
     * @dev Marks a hash as approved. This can be used to validate a hash that is used by a signature.
     * @param _hashToReject The hash that should be marked as approved for signatures that are verified by this contract.
     */
    function rejectHash(bytes32 _hashToReject) public onlyMember {
        approves[msg.sender][_hashToReject] = false;
        for (uint256 i = 0; i < signers[_hashToReject].length; ++i) {
            if (signers[_hashToReject][i] == msg.sender) {
                signers[_hashToReject][i] = signers[_hashToReject][signers[_hashToReject].length - 1];
                signers[_hashToReject].pop();
                break;
            }
        }
    }

    function addMember(address _newMember) public onlyOwner {
        _addMember(_newMember);
    }

    function removeMember(address _member) public onlyOwner {
        if (members[_member] == false) {
            revert IsNotMember();
        }
        members[_member] = false;
        for (uint256 i = 0; i < membersList.length; ++i) {
            if (membersList[i] == _member) {
                membersList[i] = membersList[membersList.length - 1];
                membersList.pop();
                break;
            }
        }
    }

    /// @dev Returns hash to be signed by owners.
    /// @param _to Destination address.
    /// @param _data Data payload.
    /// @param _value ETH value to transfer
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
        uint256 supportersCount = 0;
        if (quorum == 0) {
            revert ZeroQuorum();
        }

        for (uint256 i = 0; i < signers[_txHash].length; ++i) {
            if (members[signers[_txHash][i]] == true) {
                supportersCount++;
            }
        }
        return supportersCount >= quorum;
    }

    function _addMember(address _newMember) internal {
        membersList.push(_newMember);
        members[_newMember] = true;
        emit MemberAdded(_newMember);
    }

    modifier onlyMember() {
        if (members[msg.sender] == false) {
            revert SenderIsNotMember();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert SenderIsNotOwner();
        }
        _;
    }
}
