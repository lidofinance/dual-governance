pragma solidity 0.8.23;

import "contracts/model/DualGovernanceModel.sol";
import "contracts/model/EmergencyProtectedTimelockModel.sol";
import "contracts/model/EscrowModel.sol";
import "contracts/model/StETHModel.sol";

import "test/kontrol/StorageSetup.sol";

contract DualGovernanceSetUp is StorageSetup {
    DualGovernanceModel dualGovernance;
    EmergencyProtectedTimelockModel timelock;
    StETHModel stEth;
    EscrowModel signallingEscrow;
    EscrowModel rageQuitEscrow;

    function setUp() public {
        stEth = new StETHModel();
        uint256 emergencyProtectionTimelock = 0; // Regular deployment mode
        dualGovernance = new DualGovernanceModel(address(stEth), emergencyProtectionTimelock);
        timelock = dualGovernance.emergencyProtectedTimelock();
        signallingEscrow = dualGovernance.signallingEscrow();
        rageQuitEscrow = new EscrowModel(address(dualGovernance), address(stEth));

        // ?STORAGE
        // ?WORD: totalPooledEther
        // ?WORD0: totalShares
        // ?WORD1: shares[signallingEscrow]
        _stEthStorageSetup(stEth, signallingEscrow);

        // ?STORAGE0
        // ?WORD2: lastStateChangeTime
        // ?WORD3: lastSubStateActivationTime
        // ?WORD4: lastStateReactivationTime
        // ?WORD5: lastVetoSignallingTime
        // ?WORD6: rageQuitSequenceNumber
        // ?WORD7: currentState
        _dualGovernanceStorageSetup(dualGovernance, timelock, stEth, signallingEscrow, rageQuitEscrow);

        // ?STORAGE1
        // ?WORD8: totalSharesLocked
        // ?WORD9: totalClaimedEthAmount
        // ?WORD10: withdrawalRequestCount
        // ?WORD11: lastWithdrawalRequestSubmitted
        // ?WORD12: claimedWithdrawalRequests
        // ?WORD13: rageQuitExtensionDelayPeriodEnd
        // ?WORD14: rageQuitEthClaimTimelockStart
        _signallingEscrowStorageSetup(signallingEscrow, dualGovernance, stEth);

        // ?STORAGE2
        // ?WORD15: totalSharesLocked
        // ?WORD16: totalClaimedEthAmount
        // ?WORD17: withdrawalRequestCount
        // ?WORD18: lastWithdrawalRequestSubmitted
        // ?WORD19: claimedWithdrawalRequests
        // ?WORD20: rageQuitExtensionDelayPeriodEnd
        // ?WORD21: rageQuitEthClaimTimelockStart
        _rageQuitEscrowStorageSetup(rageQuitEscrow, dualGovernance, stEth);

        // ?STORAGE3
        kevm.symbolicStorage(address(timelock));
    }
}
