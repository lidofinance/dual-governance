pragma solidity 0.8.26;

import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import {Escrow} from "contracts/Escrow.sol";

import {SharesValue} from "contracts/types/SharesValue.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";
import {State as WithdrawalsBatchesQueueState} from "contracts/libraries/WithdrawalsBatchesQueue.sol";
import {State as EscrowSt} from "contracts/libraries/EscrowState.sol";

import "test/kontrol/model/StETHModel.sol";
import "test/kontrol/model/WithdrawalQueueModel.sol";
import "test/kontrol/model/WstETHAdapted.sol";

import "test/kontrol/KontrolTest.sol";
import "test/kontrol/storage/DualGovernanceStorageConstants.sol";
import "test/kontrol/storage/EscrowStorageConstants.sol";
import "test/kontrol/storage/WithdrawalQueueStorageConstants.sol";

contract StEthStorageSetup is KontrolTest {
    //
    //  STETH
    //
    function stEthStorageSetup(StETHModel _stEth, IWithdrawalQueue _withdrawalQueue) external {
        kevm.symbolicStorage(address(_stEth));

        uint256 totalPooledEther = freshUInt256("StEth_totalPooledEther");
        vm.assume(0 < totalPooledEther);
        vm.assume(totalPooledEther < ethUpperBound);
        _stEth.setTotalPooledEther(totalPooledEther);

        uint256 totalShares = freshUInt256("StEth_totalShares");
        vm.assume(0 < totalShares);
        vm.assume(totalShares < ethUpperBound);
        _stEth.setTotalShares(totalShares);

        uint256 queueShares = freshUInt256("StEth_queueShares");
        vm.assume(queueShares < totalShares);
        vm.assume(queueShares < ethUpperBound);
        _stEth.setShares(address(_withdrawalQueue), queueShares);
    }

    function stEthEscrowSetup(StETHModel _stEth, IEscrowBase _escrow, IWithdrawalQueue _withdrawalQueue) external {
        uint256 escrowShares = freshUInt256("StEth_escrowShares");
        vm.assume(escrowShares < _stEth.getTotalShares());
        vm.assume(escrowShares < ethUpperBound);
        _stEth.setShares(address(_escrow), escrowShares);

        uint256 queueAllowance = type(uint256).max;
        _stEth.setAllowances(address(_escrow), address(_withdrawalQueue), queueAllowance);
    }

    function stEthUserSetup(StETHModel _stEth, address _user) external {
        uint256 userShares = freshUInt256("StEth_userShares");
        vm.assume(userShares < _stEth.getTotalShares());
        vm.assume(userShares < ethUpperBound);
        _stEth.setShares(_user, userShares);
    }

    function stEthStorageInvariants(Mode mode, StETHModel _stEth, IEscrowBase _escrow) external {
        uint256 totalPooledEther = _stEth.getTotalPooledEther();
        uint256 totalShares = _stEth.getTotalShares();
        uint256 escrowShares = _stEth.sharesOf(address(_escrow));

        _establish(mode, 0 < _stEth.getTotalPooledEther());
        _establish(mode, 0 < _stEth.getTotalShares());
        _establish(mode, escrowShares < totalShares);
    }

    function stEthAssumeBounds(StETHModel _stEth, IEscrowBase _escrow) external {
        uint256 totalPooledEther = _stEth.getTotalPooledEther();
        uint256 totalShares = _stEth.getTotalShares();
        uint256 escrowShares = _stEth.sharesOf(address(_escrow));

        vm.assume(totalPooledEther < ethUpperBound);
        vm.assume(totalShares < ethUpperBound);
        vm.assume(escrowShares < ethUpperBound);
    }

    function stEthInitializeStorage(
        StETHModel _stEth,
        IEscrowBase _signallingEscrow,
        IEscrowBase _rageQuitEscrow,
        IWithdrawalQueue _withdrawalQueue
    ) external {
        this.stEthStorageSetup(_stEth, _withdrawalQueue);
        this.stEthEscrowSetup(_stEth, _signallingEscrow, _withdrawalQueue);
        this.stEthEscrowSetup(_stEth, _rageQuitEscrow, _withdrawalQueue);
        this.stEthStorageInvariants(Mode.Assume, _stEth, _signallingEscrow);
        this.stEthStorageInvariants(Mode.Assume, _stEth, _rageQuitEscrow);
    }

    //
    //  WSTETH
    //
    function _wstEthStorageSetup(WstETHAdapted _wstEth, IStETH _stEth) internal {
        kevm.symbolicStorage(address(_wstEth));
    }
}
