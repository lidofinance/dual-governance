// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UnitTest} from "test/utils/unit-test.sol";

import {Proposers} from "contracts/libraries/Proposers.sol";

contract ProposersLibraryUnitTests is UnitTest {
    using Proposers for Proposers.Context;

    address internal immutable _ADMIN_EXECUTOR = makeAddr("ADMIN_EXECUTOR");
    address internal immutable _ADMIN_PROPOSER = makeAddr("ADMIN_PROPOSER");
    address internal immutable _DEFAULT_EXECUTOR = makeAddr("DEFAULT_EXECUTOR");
    address internal immutable _DEFAULT_PROPOSER = makeAddr("DEFAULT_PROPOSER");

    Proposers.Context internal _proposers;

    // ---
    // register()
    // ---
    function test_register_HappyPath() external {
        // adding admin proposer
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
        Proposers.Proposer[] memory allProposers = _proposers.getAllProposers();

        assertEq(allProposers.length, 1);
        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[0].executor, _ADMIN_EXECUTOR);

        // adding non admin proposer
        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);
        allProposers = _proposers.getAllProposers();

        assertEq(allProposers.length, 2);
        assertEq(allProposers[1].account, _DEFAULT_PROPOSER);
        assertEq(allProposers[1].executor, _DEFAULT_EXECUTOR);
    }

    function test_register_RevertOn_InvalidProposerAccount() external {
        vm.expectRevert(abi.encodeWithSelector(Proposers.InvalidProposerAccount.selector, address(0)));
        _proposers.register(address(0), _ADMIN_EXECUTOR);
    }

    function test_register_RevertOn_InvalidExecutor() external {
        vm.expectRevert(abi.encodeWithSelector(Proposers.InvalidExecutor.selector, address(0)));
        _proposers.register(_ADMIN_PROPOSER, address(0));
    }

    function test_register_RevertOn_ProposerAlreadyRegistered() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerAlreadyRegistered.selector, _ADMIN_PROPOSER));
        _proposers.register(_ADMIN_PROPOSER, _DEFAULT_EXECUTOR);
    }

    function test_register_Emit_ProposerRegistered() external {
        vm.expectEmit(true, true, true, false);
        emit Proposers.ProposerRegistered(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
    }

    // ---
    // unregister()
    // ---

    function test_unregister_HappyPath() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        assertEq(_proposers.proposers.length, 1);
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));
        assertTrue(_proposers.isExecutor(_ADMIN_EXECUTOR));

        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);
        assertEq(_proposers.proposers.length, 2);
        assertTrue(_proposers.isProposer(_DEFAULT_PROPOSER));
        assertTrue(_proposers.isExecutor(_DEFAULT_EXECUTOR));

        _proposers.unregister(_DEFAULT_PROPOSER);
        assertEq(_proposers.proposers.length, 1);
        assertFalse(_proposers.isProposer(_DEFAULT_PROPOSER));
        assertFalse(_proposers.isExecutor(_DEFAULT_EXECUTOR));

        _proposers.unregister(_ADMIN_PROPOSER);
        assertEq(_proposers.proposers.length, 0);
        assertFalse(_proposers.isProposer(_ADMIN_PROPOSER));
        assertFalse(_proposers.isExecutor(_ADMIN_EXECUTOR));
    }

    function test_unregister_RevertOn_ProposerIsNotRegistered() external {
        assertFalse(_proposers.isProposer(_DEFAULT_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        _proposers.unregister(_DEFAULT_PROPOSER);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        assertFalse(_proposers.isProposer(_DEFAULT_PROPOSER));
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        _proposers.unregister(_DEFAULT_PROPOSER);
    }

    function test_uregister_Emit_ProposerUnregistered() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));

        vm.expectEmit(true, true, true, false);
        emit Proposers.ProposerUnregistered(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        _proposers.unregister(_ADMIN_PROPOSER);
    }

    // ---
    // getProposer()
    // ---

    function test_getProposer_HappyPath() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));

        Proposers.Proposer memory adminProposer = _proposers.getProposer(_ADMIN_PROPOSER);
        assertEq(adminProposer.account, _ADMIN_PROPOSER);
        assertEq(adminProposer.executor, _ADMIN_EXECUTOR);

        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);
        assertTrue(_proposers.isProposer(_DEFAULT_PROPOSER));

        Proposers.Proposer memory defaultProposer = _proposers.getProposer(_DEFAULT_PROPOSER);
        assertEq(defaultProposer.account, _DEFAULT_PROPOSER);
        assertEq(defaultProposer.executor, _DEFAULT_EXECUTOR);
    }

    function test_getProposer_RevertOn_RetrievingUnregisteredProposer() external {
        assertFalse(_proposers.isProposer(_DEFAULT_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        _proposers.getProposer(_DEFAULT_PROPOSER);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));
        assertFalse(_proposers.isProposer(_DEFAULT_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        _proposers.getProposer(_DEFAULT_PROPOSER);
    }

    // ---
    // getAllProposer()
    // ---

    function test_getAllProposers_HappyPath() external {
        Proposers.Proposer[] memory emptyProposers = _proposers.getAllProposers();
        assertEq(emptyProposers.length, 0);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));

        Proposers.Proposer[] memory allProposers = _proposers.getAllProposers();
        assertEq(allProposers.length, 1);

        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[0].executor, _ADMIN_EXECUTOR);

        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);
        assertTrue(_proposers.isProposer(_DEFAULT_PROPOSER));

        allProposers = _proposers.getAllProposers();
        assertEq(allProposers.length, 2);

        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[0].executor, _ADMIN_EXECUTOR);

        assertEq(allProposers[1].account, _DEFAULT_PROPOSER);
        assertEq(allProposers[1].executor, _DEFAULT_EXECUTOR);
    }
}
