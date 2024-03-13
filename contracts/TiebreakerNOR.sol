// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IEmergencyExecutor {
    function emergencyExecute(uint256 proposalId) external;
}

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
    error SenderIsNotMember();
    error ProposalIsNotSupported();
    error ProposalSupported();
    error ProposalAlreadyExecuted(uint256 proposalId);

    address public executor;
    address public nodeOperatorsRegistry;

    struct ProposalState {
        uint256[] supportersList;
        mapping(address => bool) supporters;
        bool isExecuted;
    }

    mapping(uint256 => ProposalState) proposals;

    constructor(address _nodeOperatorsRegistry, address _executor) {
        nodeOperatorsRegistry = _nodeOperatorsRegistry;
        executor = _executor;
    }

    function emergencyExecute(uint256 _proposalId, uint256 _nodeOperatorId) public onlyNodeOperator(_nodeOperatorId) {
        if (proposals[_proposalId].supporters[msg.sender] == true) {
            revert ProposalSupported();
        }
        proposals[_proposalId].supportersList.push(_nodeOperatorId);
        proposals[_proposalId].supporters[msg.sender] = true;
    }

    function forwardExecution(uint256 _proposalId) public {
        if (!hasQuorum(_proposalId)) {
            revert ProposalIsNotSupported();
        }

        if (proposals[_proposalId].isExecuted == true) {
            revert ProposalAlreadyExecuted(_proposalId);
        }

        IEmergencyExecutor(executor).emergencyExecute(_proposalId);

        proposals[_proposalId].isExecuted = true;
    }

    function hasQuorum(uint256 _proposalId) public view returns (bool) {
        uint256 activeNOCount = INodeOperatorsRegistry(nodeOperatorsRegistry).getActiveNodeOperatorsCount();
        uint256 quorum = activeNOCount / 2 + 1;

        uint256 supportersCount = 0;

        for (uint256 i = 0; i < proposals[_proposalId].supportersList.length; ++i) {
            if (
                INodeOperatorsRegistry(nodeOperatorsRegistry).getNodeOperatorIsActive(
                    proposals[_proposalId].supportersList[i]
                ) == true
            ) {
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
