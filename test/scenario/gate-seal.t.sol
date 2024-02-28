// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {GateSeal} from "contracts/GateSeal.sol";
import {DAO_AGENT, DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER} from "../utils/mainnet-addresses.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Utils} from "../utils/utils.sol";

contract GateSealTest is Test {
    uint256 internal immutable _RELEASE_TIMELOCK = 14 days;
    uint256 internal immutable _RELEASE_EXPERY = 5 days;
    uint256 internal immutable _SEALING_COMMITTEE_LIFETIME = 365 days;

    address internal immutable _SEALING_COMMITTEE = makeAddr("SEALING_COMMITTEE");

    GateSeal private _gateSeal;
    address[] private _sealables;
    GovernanceState__mock private _govState;

    Pausable__mock private _pausable;
    NotPausable__mock private _notPausable;

    function setUp() external {
        Utils.selectFork();
        _pausable = new Pausable__mock();
        _notPausable = new NotPausable__mock();

        _sealables.push(address(_pausable));
        _sealables.push(address(_pausable));

        _govState = new GovernanceState__mock();

        _gateSeal = new GateSeal(
            address(this),
            address(_govState),
            _SEALING_COMMITTEE,
            _SEALING_COMMITTEE_LIFETIME,
            _RELEASE_TIMELOCK,
            _RELEASE_EXPERY,
            _sealables
        );
    }

    function test_happy_path() external {
        vm.prank(_SEALING_COMMITTEE);

        vm.expectEmit(true, true, true, true);
        emit GateSeal.Sealed(_sealables);
        emit GateSeal.ReleaseReset();
        _gateSeal.seal(_sealables);

        uint256 expectedReleaseTimestamp = block.timestamp + _RELEASE_TIMELOCK;
        vm.expectEmit(true, true, true, true);
        emit GateSeal.ReleaseStarted(expectedReleaseTimestamp);
        _gateSeal.startRelease();

        vm.expectRevert(abi.encodeWithSelector(GateSeal.SealDurationNotPassed.selector));
        _gateSeal.enactRelease();

        vm.warp(expectedReleaseTimestamp + 1);

        vm.expectEmit(true, true, true, true);
        emit GateSeal.Released(_sealables[0]);
        emit GateSeal.Released(_sealables[1]);
        _gateSeal.enactRelease();
    }
}

contract Pausable__mock {
    bool private _pause;

    function resume() external {
        _pause = false;
    }

    function pauseFor(uint256 duration) external {
        _pause = true;
    }

    function isPaused() external view returns (bool) {
        return _pause;
    }
}

contract NotPausable__mock {}

contract GovernanceState__mock {
    enum State {
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
        RageQuitAccumulation,
        RageQuit
    }

    State public currentState = State.Normal;

    function setState(State _nextState) public {
        currentState = _nextState;
    }
}
