// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    Escrow,
    percents,
    ExecutorCall,
    ExecutorCallHelpers,
    DualGovernanceState,
    ScenarioTestBlueprint
} from "../utils/scenario-test-blueprint.sol";

interface IDangerousContract {
    function doRegularStaff(uint256 magic) external;
    function doRugPool() external;
    function doControversialStaff() external;
}

contract VetoCooldownMechanicsTest is ScenarioTestBlueprint {
    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});
    }

    function testFork_ProposalSubmittedInRageQuitNonExecutableInTheNextVetoCooldown() external {
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. THE PROPOSAL IS SUBMITTED");
        {
            proposalId = _submitProposal(
                _dualGovernance, "Propose to doSmth on target passing dual governance", regularStaffCalls
            );

            _assertSubmittedProposalData(proposalId, _config.ADMIN_EXECUTOR(), regularStaffCalls);
            _assertCanSchedule(_dualGovernance, proposalId, false);
        }

        uint256 vetoedStETHAmount;
        address vetoer = makeAddr("MALICIOUS_ACTOR");
        _step("2. THE SECOND SEAL RAGE QUIT SUPPORT IS ACQUIRED");
        {
            vetoedStETHAmount = _lockStETH(vetoer, percents(_config.SECOND_SEAL_RAGE_QUIT_SUPPORT() + 1));
            _assertVetoSignalingState();

            _wait(_config.DYNAMIC_TIMELOCK_MAX_DURATION().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();
        }

        uint256 anotherProposalId;
        _step("3. ANOTHER PROPOSAL IS SUBMITTED DURING THE RAGE QUIT STATE");
        {
            _activateNextState();
            _assertRageQuitState();
            anotherProposalId = _submitProposal(
                _dualGovernance,
                "Another Proposal",
                ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()))
            );
        }

        _step("4. RAGE QUIT IS FINALIZED");
        {
            // request withdrawals batches
            Escrow rageQuitEscrow = _getRageQuitEscrow();
            uint256 requestAmount = _WITHDRAWAL_QUEUE.MAX_STETH_WITHDRAWAL_AMOUNT();
            uint256 maxRequestsCount = vetoedStETHAmount / requestAmount + 1;

            while (!rageQuitEscrow.isWithdrawalsBatchesFinalized()) {
                rageQuitEscrow.requestNextWithdrawalsBatch(96);
            }

            vm.deal(address(_WITHDRAWAL_QUEUE), 2 * vetoedStETHAmount);
            _finalizeWQ();

            while (!rageQuitEscrow.isWithdrawalsClaimed()) {
                rageQuitEscrow.claimNextWithdrawalsBatch(128);
            }

            _wait(_config.RAGE_QUIT_EXTENSION_DELAY().plusSeconds(1));
            assertTrue(rageQuitEscrow.isRageQuitFinalized());
        }

        _step("5. PROPOSAL SUBMITTED BEFORE RAGE QUIT IS EXECUTABLE");
        {
            _activateNextState();
            _assertVetoCooldownState();

            this.scheduleProposalExternal(proposalId);
            _assertProposalScheduled(proposalId);
        }

        _step("6. PROPOSAL SUBMITTED DURING RAGE QUIT IS NOT EXECUTABLE");
        {
            _activateNextState();
            _assertVetoCooldownState();

            vm.expectRevert(DualGovernanceState.ProposalsAdoptionSuspended.selector);
            this.scheduleProposalExternal(anotherProposalId);
        }
    }

    function scheduleProposalExternal(uint256 proposalId) external {
        _scheduleProposal(_dualGovernance, proposalId);
    }

    function _finalizeWQ() internal {
        uint256 lastRequestId = _WITHDRAWAL_QUEUE.getLastRequestId();
        _finalizeWQ(lastRequestId);
    }

    function _finalizeWQ(uint256 id) internal {
        uint256 finalizationShareRate = _ST_ETH.getPooledEthByShares(1e27) + 1e9; // TODO check finalization rate
        address lido = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        vm.prank(lido);
        _WITHDRAWAL_QUEUE.finalize(id, finalizationShareRate);

        bytes32 LOCKED_ETHER_AMOUNT_POSITION = 0x0e27eaa2e71c8572ab988fef0b54cd45bbd1740de1e22343fb6cda7536edc12f; // keccak256("lido.WithdrawalQueue.lockedEtherAmount");

        vm.store(address(_WITHDRAWAL_QUEUE), LOCKED_ETHER_AMOUNT_POSITION, bytes32(address(_WITHDRAWAL_QUEUE).balance));
    }
}
