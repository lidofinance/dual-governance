pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/Configuration.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";
import "contracts/model/StETHModel.sol";
import "contracts/model/WstETHAdapted.sol";
import "contracts/model/WithdrawalQueueModel.sol";

import "test/kontrol/StorageSetup.sol";

contract DualGovernanceSetUp is StorageSetup {
    using DualGovernanceState for DualGovernanceState.Store;

    Configuration config;
    DualGovernance dualGovernance;
    EmergencyProtectedTimelock timelock;
    StETHModel stEth;
    WstETHAdapted wstEth;
    WithdrawalQueueModel withdrawalQueue;
    IEscrow signallingEscrow;
    IEscrow rageQuitEscrow;

    function setUp() public {
        vm.chainId(1); // Set block.chainid so it's not symbolic

        stEth = new StETHModel();
        wstEth = new WstETHAdapted(IStETH(stEth));
        withdrawalQueue = new WithdrawalQueueModel();

        // Placeholder addresses
        address adminExecutor = address(uint160(uint256(keccak256("adminExecutor"))));
        address emergencyGovernance = address(uint160(uint256(keccak256("emergencyGovernance"))));
        address adminProposer = address(uint160(uint256(keccak256("adminProposer"))));

        config = new Configuration(adminExecutor, emergencyGovernance, new address[](0));
        timelock = new EmergencyProtectedTimelock(address(config));
        Escrow escrowMasterCopy = new Escrow(address(stEth), address(wstEth), address(withdrawalQueue), address(config));
        dualGovernance =
            new DualGovernance(address(config), address(timelock), address(escrowMasterCopy), adminProposer);
        signallingEscrow = IEscrow(dualGovernance.getVetoSignallingEscrow());
        rageQuitEscrow = IEscrow(Clones.clone(address(escrowMasterCopy)));

        // ?STORAGE
        // ?WORD: totalPooledEther
        // ?WORD0: totalShares
        // ?WORD1: shares[signallingEscrow]
        _stEthStorageSetup(stEth, signallingEscrow);

        // ?STORAGE0
        // ?WORD2: currentState
        // ?WORD3: enteredAt
        // ?WORD4: vetoSignallingActivationTime
        // ?WORD5: vetoSignallingReactivationTime
        // ?WORD6: lastAdoptableStaateExitedAt
        // ?WORD7: rageQuitRound
        _dualGovernanceStorageSetup(dualGovernance, signallingEscrow, rageQuitEscrow);

        // ?STORAGE1
        // ?WORD8: lockedShares
        // ?WORD9: claimedETH
        // ?WORD10: unfinalizedShares
        // ?WORD11: finalizedETH
        // ?WORD12: batchesQueue
        // ?WORD13: rageQuitExtensionDelay
        // ?WORD14: rageQuitWithdrawalsTimelock
        // ?WORD15: rageQuitTimelockStartedAt
        _signallingEscrowStorageSetup(signallingEscrow, dualGovernance);

        // ?STORAGE2
        // ?WORD16: lockedShares
        // ?WORD17: claimedETH
        // ?WORD18: unfinalizedShares
        // ?WORD19: finalizedETH
        // ?WORD20: batchesQueue
        // ?WORD21: rageQuitExtensionDelay
        // ?WORD22: rageQuitWithdrawalsTimelock
        // ?WORD23: rageQuitTimelockStartedAt
        _rageQuitEscrowStorageSetup(rageQuitEscrow, dualGovernance);

        // ?STORAGE3
        kevm.symbolicStorage(address(timelock));

        // ?STORAGE4
        kevm.symbolicStorage(address(withdrawalQueue));
    }
}
