// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RestrictedMultisigBase} from "./RestrictedMultisigBase.sol";

interface IEmergencyProtectedTimelock {
    function emergencyExecute(uint256 proposalId) external;
    function emergencyReset() external;
}

contract EmergencyExecutionMultisig is RestrictedMultisigBase {
    uint256 public constant EXECUTE_PROPOSAL = 1;
    uint256 public constant RESET_GOVERNANCE = 2;

    address emergencyProtectedTimelock;

    constructor(
        address _owner,
        address[] memory _members,
        uint256 _quorum,
        address _emergencyProtectedTimelock
    ) RestrictedMultisigBase(_owner, _members, _quorum) {
        emergencyProtectedTimelock = _emergencyProtectedTimelock;
    }

    // Proposal Execution
    function voteExecuteProposal(uint256 _proposalId, bool _supports) public onlyMember {
        _vote(_buildExecuteProposalAction(_proposalId), _supports);
    }

    function getExecuteProposalState(uint256 _proposalId)
        public
        returns (uint256 support, uint256 ExecutionQuorum, bool isExecuted)
    {
        return _getState(_buildExecuteProposalAction(_proposalId));
    }

    function executeProposal(uint256 _proposalId) public {
        _execute(_buildExecuteProposalAction(_proposalId));
    }

    // Governance reset

    function voteGoveranaceReset() public onlyMember {
        _vote(_buildResetGovAction(), true);
    }

    function getGovernanceResetState() public returns (uint256 support, uint256 ExecutionQuorum, bool isExecuted) {
        return _getState(_buildResetGovAction());
    }

    function resetGovernance() external {
        _execute(_buildResetGovAction());
    }

    function _issueCalls(Action memory _action) internal override {
        if (_action.actionType == EXECUTE_PROPOSAL) {
            uint256 proposalIdToExecute = abi.decode(_action.data, (uint256));
            IEmergencyProtectedTimelock(emergencyProtectedTimelock).emergencyExecute(proposalIdToExecute);
        } else if (_action.actionType == RESET_GOVERNANCE) {
            IEmergencyProtectedTimelock(emergencyProtectedTimelock).emergencyReset();
        } else {
            assert(false);
        }
    }

    function _buildResetGovAction() internal view returns (Action memory) {
        return Action(RESET_GOVERNANCE, new bytes(0), false, new address[](0));
    }

    function _buildExecuteProposalAction(uint256 proposalId) internal view returns (Action memory) {
        return Action(EXECUTE_PROPOSAL, abi.encode(proposalId), false, new address[](0));
    }
}
