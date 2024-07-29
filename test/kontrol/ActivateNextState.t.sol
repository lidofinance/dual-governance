pragma solidity 0.8.23;

import {State} from "contracts/libraries/DualGovernanceState.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract ActivateNextStateMock is StorageSetup {
    StorageSetup public immutable STORAGE_SETUP;

    constructor(address storageSetup) {
        STORAGE_SETUP = StorageSetup(storageSetup);
    }

    function activateNextState() external {
        DualGovernance dualGovernance = DualGovernance(address(this));
        Escrow signallingEscrow = Escrow(payable(dualGovernance.getVetoSignallingEscrow()));
        Escrow rageQuitEscrow = Escrow(payable(dualGovernance.getRageQuitEscrow()));

        STORAGE_SETUP.dualGovernanceStorageInvariants(Mode.Assert, dualGovernance);
        STORAGE_SETUP.escrowStorageInvariants(Mode.Assert, signallingEscrow);
        STORAGE_SETUP.signallingEscrowStorageInvariants(Mode.Assert, signallingEscrow);
        STORAGE_SETUP.escrowStorageInvariants(Mode.Assert, rageQuitEscrow);
        STORAGE_SETUP.rageQuitEscrowStorageInvariants(Mode.Assert, rageQuitEscrow);

        address escrowMasterCopy = signallingEscrow.MASTER_COPY();
        IEscrow newSignallingEscrow = IEscrow(Clones.clone(escrowMasterCopy));
        IEscrow newRageQuitEscrow = IEscrow(Clones.clone(escrowMasterCopy));

        STORAGE_SETUP.dualGovernanceInitializeStorage(dualGovernance, newSignallingEscrow, newRageQuitEscrow);
        STORAGE_SETUP.signallingEscrowInitializeStorage(newSignallingEscrow, dualGovernance);
        STORAGE_SETUP.rageQuitEscrowInitializeStorage(newRageQuitEscrow, dualGovernance);
    }
}

contract ActivateNextStateTest is DualGovernanceSetUp {
    function testActivateNextStateTermination() external {
        dualGovernance.activateNextState();
    }

    function testActivateNextStateInvariants() external {
        dualGovernance.activateNextState();

        Escrow newSignallingEscrow = Escrow(payable(dualGovernance.getVetoSignallingEscrow()));
        Escrow newRageQuitEscrow = Escrow(payable(dualGovernance.getRageQuitEscrow()));

        this.dualGovernanceStorageInvariants(Mode.Assert, dualGovernance);
        this.escrowStorageInvariants(Mode.Assert, newSignallingEscrow);
        this.signallingEscrowStorageInvariants(Mode.Assert, newSignallingEscrow);
        this.escrowStorageInvariants(Mode.Assert, newRageQuitEscrow);
        this.rageQuitEscrowStorageInvariants(Mode.Assert, newRageQuitEscrow);
    }

    function testEscrowStateTransition() public {
        State initialState = dualGovernance.getCurrentState();

        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
        (,, Timestamp vetoSignallingActivationTime,) = dualGovernance.getVetoSignallingState();
        address sender = address(uint160(uint256(keccak256("sender"))));
        AccountingRecord memory pre = this.saveAccountingRecord(sender, signallingEscrow);

        dualGovernance.activateNextState();

        if (
            (initialState == State.VetoSignalling || initialState == State.VetoSignallingDeactivation)
                && rageQuitSupport > config.SECOND_SEAL_RAGE_QUIT_SUPPORT()
                && Timestamps.now() > config.DYNAMIC_TIMELOCK_MAX_DURATION().addTo(vetoSignallingActivationTime)
        ) {
            IEscrow newSignallingEscrow = IEscrow(dualGovernance.getVetoSignallingEscrow());

            assert(dualGovernance.getRageQuitEscrow() == address(signallingEscrow));
            assert(EscrowState(_getCurrentState(signallingEscrow)) == EscrowState.RageQuitEscrow);
            this.dualGovernanceStorageInvariants(Mode.Assert, dualGovernance);
            this.signallingEscrowStorageInvariants(Mode.Assert, newSignallingEscrow);
            this.rageQuitEscrowStorageInvariants(Mode.Assert, signallingEscrow);
        } else {
            assert(dualGovernance.getVetoSignallingEscrow() == address(signallingEscrow));
            assert(dualGovernance.getRageQuitEscrow() == address(rageQuitEscrow));
            assert(EscrowState(_getCurrentState(signallingEscrow)) == EscrowState.SignallingEscrow);
            this.dualGovernanceStorageInvariants(Mode.Assert, dualGovernance);
            this.signallingEscrowStorageInvariants(Mode.Assert, signallingEscrow);
            this.rageQuitEscrowStorageInvariants(Mode.Assert, rageQuitEscrow);
        }

        AccountingRecord memory post = this.saveAccountingRecord(sender, signallingEscrow);
        this.establishEqualAccountingRecords(Mode.Assert, pre, post);
    }
}
