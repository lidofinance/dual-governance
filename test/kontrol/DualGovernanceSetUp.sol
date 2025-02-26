pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/ImmutableDualGovernanceConfigProvider.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import {Escrow} from "contracts/Escrow.sol";
import "test/kontrol/model/StETHModel.sol";
import "test/kontrol/model/WstETHAdapted.sol";
import "test/kontrol/model/WithdrawalQueueModel.sol";
import "contracts/ResealManager.sol";

import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

import "test/kontrol/StorageSetup.sol";

contract DualGovernanceSetUp is StorageSetup {
    ImmutableDualGovernanceConfigProvider config;
    DualGovernance dualGovernance;
    EmergencyProtectedTimelock timelock;
    StETHModel stEth;
    WstETHAdapted wstEth;
    WithdrawalQueueModel withdrawalQueue;
    IEscrowBase escrowMasterCopy;
    Escrow signallingEscrow;
    Escrow rageQuitEscrow;
    ResealManager resealManager;

    DualGovernanceConfig.Context governanceConfig;
    EmergencyProtectedTimelock.SanityCheckParams timelockSanityCheckParams;
    DualGovernance.SignallingTokens signallingTokens;
    DualGovernance.DualGovernanceComponents components;
    DualGovernance.SanityCheckParams dgSanityCheckParams;

    function setUp() public virtual {
        vm.chainId(1); // Set block.chainid so it's not symbolic
        vm.assume(block.timestamp < timeUpperBound);

        stEth = new StETHModel();
        wstEth = new WstETHAdapted(IStETH(stEth));
        withdrawalQueue = new WithdrawalQueueModel(vm, IStETH(stEth));

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

        timelockSanityCheckParams = EmergencyProtectedTimelock.SanityCheckParams({
            minExecutionDelay: Durations.from(4 days),
            maxAfterSubmitDelay: Durations.from(14 days),
            maxAfterScheduleDelay: Durations.from(7 days),
            maxEmergencyModeDuration: Durations.from(365 days),
            maxEmergencyProtectionDuration: Durations.from(365 days)
        });
        Duration afterSubmitDelay = Durations.from(3 days);
        Duration afterScheduleDelay = Durations.from(2 days);

        timelock = new EmergencyProtectedTimelock(
            timelockSanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay
        );
        resealManager = new ResealManager(timelock);

        signallingTokens.stETH = stEth;
        signallingTokens.wstETH = wstEth;
        signallingTokens.withdrawalQueue = withdrawalQueue;
        components.timelock = timelock;
        components.resealManager = resealManager;
        components.configProvider = config;

        dgSanityCheckParams = DualGovernance.SanityCheckParams({
            minWithdrawalsBatchSize: 1,
            minTiebreakerActivationTimeout: Durations.from(30 days),
            maxTiebreakerActivationTimeout: Durations.from(180 days),
            maxSealableWithdrawalBlockersCount: 128,
            maxMinAssetsLockDuration: Durations.from(365 days)
        });

        dualGovernance = new DualGovernance(components, signallingTokens, dgSanityCheckParams);

        signallingEscrow = Escrow(payable(dualGovernance.getVetoSignallingEscrow()));
        escrowMasterCopy = signallingEscrow.ESCROW_MASTER_COPY();
        rageQuitEscrow = Escrow(payable(Clones.clone(address(escrowMasterCopy))));

        this.stEthInitializeStorage(stEth, signallingEscrow, rageQuitEscrow, withdrawalQueue);
        this.dualGovernanceInitializeStorage(dualGovernance, signallingEscrow, rageQuitEscrow, config);
        this.signallingEscrowInitializeStorage(signallingEscrow);
        this.rageQuitEscrowInitializeStorage(rageQuitEscrow);
        this.timelockStorageSetup(dualGovernance, timelock);
        this.withdrawalQueueStorageSetup(withdrawalQueue, stEth, rageQuitEscrow);
    }

    function _getArbitraryUserAddress() internal pure returns (address) {
        // Placeholder address to avoid complications with keccak of symbolic addresses
        return address(uint160(uint256(keccak256("sender"))));
    }

    function _calcVetoSignallingDuration(PercentD16 rageQuitSupport) internal view returns (Duration) {
        PercentD16 firstSealRageQuitSupport = config.FIRST_SEAL_RAGE_QUIT_SUPPORT();
        PercentD16 secondSealRageQuitSupport = config.SECOND_SEAL_RAGE_QUIT_SUPPORT();

        Duration vetoSignallingMinDuration = config.VETO_SIGNALLING_MIN_DURATION();
        Duration vetoSignallingMaxDuration = config.VETO_SIGNALLING_MAX_DURATION();

        if (rageQuitSupport < firstSealRageQuitSupport) {
            return Durations.ZERO;
        }

        if (rageQuitSupport >= secondSealRageQuitSupport) {
            return vetoSignallingMaxDuration;
        }

        return vetoSignallingMinDuration
            + Durations.from(
                (rageQuitSupport - firstSealRageQuitSupport).toUint256()
                    * (vetoSignallingMaxDuration - vetoSignallingMinDuration).toSeconds()
                    / (secondSealRageQuitSupport - firstSealRageQuitSupport).toUint256()
            );
    }

    function forgetStateTransition(
        State state,
        PercentD16 rageQuitSupport,
        Timestamp vetoSignallingActivatedAt,
        Timestamp vetoSignallingReactivationTime,
        Timestamp enteredAt,
        Timestamp rageQuitExtensionPeriodStartedAt,
        Duration rageQuitExtensionPeriodDuration
    ) public {
        if (state == State.Normal) {
            // Transitions from Normal
            kevm.forgetBranch(
                PercentD16.unwrap(rageQuitSupport),
                KontrolCheatsBase.ComparisonOperator.GreaterThanOrEqual,
                PercentD16.unwrap(config.FIRST_SEAL_RAGE_QUIT_SUPPORT())
            );
        } else if (state == State.VetoSignalling) {
            // Transitions from VetoSignalling
            kevm.forgetBranch(
                Timestamp.unwrap(Timestamps.now()),
                KontrolCheatsBase.ComparisonOperator.GreaterThan,
                Timestamp.unwrap(_calcVetoSignallingDuration(rageQuitSupport).addTo(vetoSignallingActivatedAt))
            );

            kevm.forgetBranch(
                PercentD16.unwrap(rageQuitSupport),
                KontrolCheatsBase.ComparisonOperator.GreaterThanOrEqual,
                PercentD16.unwrap(config.SECOND_SEAL_RAGE_QUIT_SUPPORT())
            );

            kevm.forgetBranch(
                Timestamp.unwrap(Timestamps.now()),
                KontrolCheatsBase.ComparisonOperator.GreaterThan,
                Timestamp.unwrap(
                    config.VETO_SIGNALLING_MIN_ACTIVE_DURATION().addTo(
                        Timestamps.max(vetoSignallingReactivationTime, vetoSignallingActivatedAt)
                    )
                )
            );
        } else if (state == State.VetoSignallingDeactivation) {
            // Transitions from VetoSignallingDeactivation
            kevm.forgetBranch(
                Timestamp.unwrap(Timestamps.now()),
                KontrolCheatsBase.ComparisonOperator.GreaterThan,
                Timestamp.unwrap(_calcVetoSignallingDuration(rageQuitSupport).addTo(vetoSignallingActivatedAt))
            );

            kevm.forgetBranch(
                PercentD16.unwrap(rageQuitSupport),
                KontrolCheatsBase.ComparisonOperator.GreaterThanOrEqual,
                PercentD16.unwrap(config.SECOND_SEAL_RAGE_QUIT_SUPPORT())
            );

            kevm.forgetBranch(
                Timestamp.unwrap(Timestamps.now()),
                KontrolCheatsBase.ComparisonOperator.GreaterThan,
                Timestamp.unwrap(config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().addTo(enteredAt))
            );
        } else if (state == State.VetoCooldown) {
            // Transitions from VetoCooldown
            kevm.forgetBranch(
                Timestamp.unwrap(Timestamps.now()),
                KontrolCheatsBase.ComparisonOperator.GreaterThan,
                Timestamp.unwrap(config.VETO_COOLDOWN_DURATION().addTo(enteredAt))
            );

            kevm.forgetBranch(
                PercentD16.unwrap(rageQuitSupport),
                KontrolCheatsBase.ComparisonOperator.GreaterThanOrEqual,
                PercentD16.unwrap(config.FIRST_SEAL_RAGE_QUIT_SUPPORT())
            );
        } else if (state == State.RageQuit) {
            // Transitions from RageQuit
            kevm.forgetBranch(
                Timestamp.unwrap(Timestamps.now()),
                KontrolCheatsBase.ComparisonOperator.GreaterThan,
                Timestamp.unwrap(rageQuitExtensionPeriodDuration.addTo(rageQuitExtensionPeriodStartedAt))
            );

            kevm.forgetBranch(
                PercentD16.unwrap(rageQuitSupport),
                KontrolCheatsBase.ComparisonOperator.GreaterThanOrEqual,
                PercentD16.unwrap(config.FIRST_SEAL_RAGE_QUIT_SUPPORT())
            );
        }
    }
}
