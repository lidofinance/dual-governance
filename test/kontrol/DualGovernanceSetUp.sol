pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/ImmutableDualGovernanceConfigProvider.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";
import "contracts/model/StETHModel.sol";
import "contracts/model/WstETHAdapted.sol";
import "contracts/model/WithdrawalQueueModel.sol";
import "contracts/ResealManager.sol";

import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

import "test/kontrol/StorageSetup.sol";

contract DualGovernanceSetUp is StorageSetup {
    ImmutableDualGovernanceConfigProvider config;
    DualGovernance dualGovernance;
    EmergencyProtectedTimelock timelock;
    StETHModel stEth;
    WstETHAdapted wstEth;
    WithdrawalQueueModel withdrawalQueue;
    Escrow escrowMasterCopy;
    Escrow signallingEscrow;
    Escrow rageQuitEscrow;
    ResealManager resealManager;

    DualGovernanceConfig.Context governanceConfig;
    EmergencyProtectedTimelock.SanityCheckParams timelockSanityCheckParams;
    DualGovernance.ExternalDependencies dependencies;
    DualGovernance.SanityCheckParams dgSanityCheckParams;

    function setUp() public {
        vm.chainId(1); // Set block.chainid so it's not symbolic
        vm.assume(block.timestamp < timeUpperBound);

        stEth = new StETHModel();
        wstEth = new WstETHAdapted(IStETH(stEth));
        withdrawalQueue = new WithdrawalQueueModel(IStETH(stEth));

        // Placeholder addresses
        address adminExecutor = address(uint160(uint256(keccak256("adminExecutor"))));
        address emergencyGovernance = address(uint160(uint256(keccak256("emergencyGovernance"))));
        address adminProposer = address(uint160(uint256(keccak256("adminProposer"))));

        governanceConfig = DualGovernanceConfig.Context({
            firstSealRageQuitSupport: PercentsD16.fromBasisPoints(3_00), // 3%
            secondSealRageQuitSupport: PercentsD16.fromBasisPoints(15_00), // 15%
            //
            minAssetsLockDuration: Durations.from(5 hours),
            //
            vetoSignallingMinDuration: Durations.from(3 days),
            vetoSignallingMaxDuration: Durations.from(30 days),
            vetoSignallingMinActiveDuration: Durations.from(5 hours),
            vetoSignallingDeactivationMaxDuration: Durations.from(5 days),
            //
            vetoCooldownDuration: Durations.from(4 days),
            //
            rageQuitExtensionPeriodDuration: Durations.from(7 days),
            rageQuitEthWithdrawalsMinDelay: Durations.from(30 days),
            rageQuitEthWithdrawalsMaxDelay: Durations.from(180 days),
            rageQuitEthWithdrawalsDelayGrowth: Durations.from(15 days)
        });

        config = new ImmutableDualGovernanceConfigProvider(governanceConfig);
        timelock = new EmergencyProtectedTimelock(timelockSanityCheckParams, adminExecutor);
        resealManager = new ResealManager(timelock);

        //DualGovernance.ExternalDependencies memory dependencies;
        dependencies.stETH = stEth;
        dependencies.wstETH = wstEth;
        dependencies.withdrawalQueue = withdrawalQueue;
        dependencies.timelock = timelock;
        dependencies.resealManager = resealManager;
        dependencies.configProvider = config;

        dualGovernance = new DualGovernance(dependencies, dgSanityCheckParams);
        escrowMasterCopy = new Escrow(stEth, wstEth, withdrawalQueue, dualGovernance, 1);

        signallingEscrow = Escrow(payable(dualGovernance.getVetoSignallingEscrow()));
        rageQuitEscrow = Escrow(payable(Clones.clone(address(escrowMasterCopy))));

        // ?STORAGE
        // ?WORD: totalPooledEther
        // ?WORD0: totalShares
        // ?WORD1: shares[signallingEscrow]
        this.stEthStorageSetup(stEth, signallingEscrow);

        // ?STORAGE0
        // ?WORD2: currentState
        // ?WORD3: enteredAt
        // ?WORD4: vetoSignallingActivationTime
        // ?WORD5: vetoSignallingReactivationTime
        // ?WORD6: normalOrVetoCooldownExitedAt
        // ?WORD7: rageQuitRound
        this.dualGovernanceInitializeStorage(dualGovernance, signallingEscrow, rageQuitEscrow, config);

        // ?STORAGE1
        // ?WORD8: lockedShares
        // ?WORD9: claimedETH
        // ?WORD10: unfinalizedShares
        // ?WORD11: finalizedETH
        // ?WORD12: batchesQueue
        // ?WORD13: rageQuitExtensionDelay
        // ?WORD14: rageQuitWithdrawalsTimelock
        // ?WORD15: rageQuitTimelockStartedAt
        this.signallingEscrowInitializeStorage(signallingEscrow);

        // ?STORAGE2
        // ?WORD16: lockedShares
        // ?WORD17: claimedETH
        // ?WORD18: unfinalizedShares
        // ?WORD19: finalizedETH
        // ?WORD20: batchesQueue
        // ?WORD21: rageQuitExtensionDelay
        // ?WORD22: rageQuitWithdrawalsTimelock
        // ?WORD23: rageQuitTimelockStartedAt
        this.rageQuitEscrowInitializeStorage(rageQuitEscrow);

        // ?STORAGE3
        kevm.symbolicStorage(address(timelock));

        // ?STORAGE4
        kevm.symbolicStorage(address(withdrawalQueue));
    }
}
