pragma solidity 0.8.23;

import {State} from "contracts/libraries/DualGovernanceState.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract ActivateNextStateMock is StorageSetup {
    function activateNextState() external {
        DualGovernance dualGovernance = DualGovernance(address(this));
        IConfiguration config = dualGovernance.CONFIG();
        Escrow signallingEscrow = Escrow(payable(dualGovernance.getVetoSignallingEscrow()));
        Escrow rageQuitEscrow = Escrow(payable(dualGovernance.getRageQuitEscrow()));
        address sender = address(uint160(uint256(keccak256("sender"))));
        AccountingRecord memory pre = _saveAccountingRecord(sender, signallingEscrow);

        _dualGovernanceStorageInvariants(Mode.Assert, dualGovernance);
        _escrowStorageInvariants(Mode.Assert, signallingEscrow);
        _signallingEscrowStorageInvariants(Mode.Assert, signallingEscrow);
        _escrowStorageInvariants(Mode.Assert, rageQuitEscrow);
        _rageQuitEscrowStorageInvariants(Mode.Assert, rageQuitEscrow);

        State initialState = dualGovernance.getCurrentState();
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
        (,, Timestamp vetoSignallingActivationTime,) = dualGovernance.getVetoSignallingState();

        if (
            (initialState == State.VetoSignalling || initialState == State.VetoSignallingDeactivation)
                && rageQuitSupport > config.SECOND_SEAL_RAGE_QUIT_SUPPORT()
                && Timestamps.now() > config.DYNAMIC_TIMELOCK_MAX_DURATION().addTo(vetoSignallingActivationTime)
        ) {
            address escrowMasterCopy = signallingEscrow.MASTER_COPY();
            IEscrow newSignallingEscrow = IEscrow(Clones.clone(escrowMasterCopy));

            _dualGovernanceInitializeStorage(dualGovernance, newSignallingEscrow, signallingEscrow);
            _signallingEscrowInitializeStorage(newSignallingEscrow, dualGovernance);
            _rageQuitEscrowInitializeStorage(signallingEscrow, dualGovernance);
        } else {
            _dualGovernanceInitializeStorage(dualGovernance, signallingEscrow, rageQuitEscrow);
            _signallingEscrowInitializeStorage(signallingEscrow, dualGovernance);
            _rageQuitEscrowInitializeStorage(rageQuitEscrow, dualGovernance);
        }

        AccountingRecord memory post = _saveAccountingRecord(sender, signallingEscrow);
        _establishEqualAccountingRecords(Mode.Assume, pre, post);
    }
}

contract ActivateNextStateTest is DualGovernanceSetUp {
    function testEscrowStateTransition() public {
        State initialState = dualGovernance.getCurrentState();
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
        (,, Timestamp vetoSignallingActivationTime,) = dualGovernance.getVetoSignallingState();
        address sender = address(uint160(uint256(keccak256("sender"))));
        AccountingRecord memory pre = _saveAccountingRecord(sender, signallingEscrow);

        dualGovernance.activateNextState();

        if (
            (initialState == State.VetoSignalling || initialState == State.VetoSignallingDeactivation)
                && rageQuitSupport > config.SECOND_SEAL_RAGE_QUIT_SUPPORT()
                && Timestamps.now() > config.DYNAMIC_TIMELOCK_MAX_DURATION().addTo(vetoSignallingActivationTime)
        ) {
            IEscrow newSignallingEscrow = IEscrow(dualGovernance.getVetoSignallingEscrow());

            assert(dualGovernance.getRageQuitEscrow() == address(signallingEscrow));
            assert(EscrowState(_getCurrentState(signallingEscrow)) == EscrowState.RageQuitEscrow);
            _dualGovernanceStorageInvariants(Mode.Assert, dualGovernance);
            _signallingEscrowStorageInvariants(Mode.Assert, newSignallingEscrow);
            _rageQuitEscrowStorageInvariants(Mode.Assert, signallingEscrow);
        } else {
            assert(dualGovernance.getVetoSignallingEscrow() == address(signallingEscrow));
            assert(dualGovernance.getRageQuitEscrow() == address(rageQuitEscrow));
            assert(EscrowState(_getCurrentState(signallingEscrow)) == EscrowState.SignallingEscrow);
            _dualGovernanceStorageInvariants(Mode.Assert, dualGovernance);
            _signallingEscrowStorageInvariants(Mode.Assert, signallingEscrow);
            _rageQuitEscrowStorageInvariants(Mode.Assert, rageQuitEscrow);
        }

        AccountingRecord memory post = _saveAccountingRecord(sender, signallingEscrow);
        _establishEqualAccountingRecords(Mode.Assert, pre, post);
    }
}
