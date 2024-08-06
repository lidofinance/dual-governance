pragma solidity 0.8.23;

import {State} from "contracts/libraries/DualGovernanceState.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract ActivateNextStateMock is StorageSetup {
    StorageSetup public immutable STORAGE_SETUP;
    address public immutable USER;

    constructor(address storageSetup, address user) {
        STORAGE_SETUP = StorageSetup(storageSetup);
        USER = user;
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

        AccountingRecord memory pre = STORAGE_SETUP.saveAccountingRecord(USER, signallingEscrow);

        State initialState = dualGovernance.getCurrentState();
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
        Timestamp vetoSignallingActivationTime = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));
        IConfiguration config = dualGovernance.CONFIG();

        IEscrow newSignallingEscrow;
        IEscrow newRageQuitEscrow;

        bool transitionToRageQuit = (
            initialState == State.VetoSignalling || initialState == State.VetoSignallingDeactivation
        ) && rageQuitSupport > config.SECOND_SEAL_RAGE_QUIT_SUPPORT()
            && Timestamps.now() > config.DYNAMIC_TIMELOCK_MAX_DURATION().addTo(vetoSignallingActivationTime);

        if (transitionToRageQuit) {
            address escrowMasterCopy = signallingEscrow.MASTER_COPY();
            newSignallingEscrow = IEscrow(Clones.clone(escrowMasterCopy));
            newRageQuitEscrow = signallingEscrow;
        } else {
            newSignallingEscrow = signallingEscrow;
            newRageQuitEscrow = rageQuitEscrow;
        }

        STORAGE_SETUP.dualGovernanceInitializeStorage(dualGovernance, newSignallingEscrow, newRageQuitEscrow);

        if (transitionToRageQuit) {
            vm.assume(dualGovernance.getCurrentState() == State.RageQuit);
        }

        STORAGE_SETUP.signallingEscrowInitializeStorage(newSignallingEscrow, dualGovernance);
        STORAGE_SETUP.rageQuitEscrowInitializeStorage(newRageQuitEscrow, dualGovernance);
        vm.assume(_getLastAssetsLockTimestamp(signallingEscrow, USER) < timeUpperBound);

        {
            uint128 senderLockedShares = uint128(kevm.freshUInt(16));
            vm.assume(senderLockedShares < ethUpperBound);
            uint128 senderUnlockedShares = uint128(kevm.freshUInt(16));
            bytes memory slotAbi = abi.encodePacked(uint128(senderUnlockedShares), uint128(senderLockedShares));
            bytes32 slot;
            assembly {
                slot := mload(add(slotAbi, 0x20))
            }
            _storeBytes32(
                address(signallingEscrow),
                93842437974268059396725027201531251382101332839645030345425397622830526343272,
                slot
            );
        }

        AccountingRecord memory post = STORAGE_SETUP.saveAccountingRecord(USER, signallingEscrow);

        STORAGE_SETUP.establishEqualAccountingRecords(Mode.Assume, pre, post);
    }
}

contract ActivateNextStateTest is DualGovernanceSetUp {
    function testActivateNextStateTermination() external {
        dualGovernance.activateNextState();
    }

    function testActivateNextStateCorrectEscrows() external {
        State preState = dualGovernance.getCurrentState();

        dualGovernance.activateNextState();

        State postState = dualGovernance.getCurrentState();

        Escrow newSignallingEscrow = Escrow(payable(dualGovernance.getVetoSignallingEscrow()));
        Escrow newRageQuitEscrow = Escrow(payable(dualGovernance.getRageQuitEscrow()));

        if (postState == State.RageQuit && preState != State.RageQuit) {
            this.infoAssert(address(newSignallingEscrow) != address(signallingEscrow), "NRQ: NS != OS");
            this.infoAssert(address(newSignallingEscrow) != address(rageQuitEscrow), "NRQ: NS != OR");
            this.infoAssert(address(newRageQuitEscrow) == address(signallingEscrow), "NRQ: NR == OS");
        } else {
            this.infoAssert(address(newSignallingEscrow) == address(signallingEscrow), "RQ: NS == OS");
            this.infoAssert(address(newRageQuitEscrow) == address(rageQuitEscrow), "RQ: NR == OR");
        }
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
