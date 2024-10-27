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
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);
        Proposers.Proposer[] memory allProposers = _proposers.getAllProposers();

        assertEq(allProposers.length, 1);
        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[0].executor, _ADMIN_EXECUTOR);

        // adding non admin proposer
        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR, true);
        allProposers = _proposers.getAllProposers();

        assertEq(allProposers.length, 2);
        assertEq(allProposers[1].account, _DEFAULT_PROPOSER);
        assertEq(allProposers[1].executor, _DEFAULT_EXECUTOR);
    }

    function test_register_RevertOn_InvalidProposerAccount() external {
        vm.expectRevert(abi.encodeWithSelector(Proposers.InvalidProposerAccount.selector, address(0)));
        _proposers.register(address(0), _ADMIN_EXECUTOR, true);
    }

    function test_register_RevertOn_InvalidExecutor() external {
        vm.expectRevert(abi.encodeWithSelector(Proposers.InvalidExecutor.selector, address(0)));
        _proposers.register(_ADMIN_PROPOSER, address(0), true);
    }

    function test_register_RevertOn_ProposerAlreadyRegistered() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerAlreadyRegistered.selector, _ADMIN_PROPOSER));
        _proposers.register(_ADMIN_PROPOSER, _DEFAULT_EXECUTOR, true);
    }

    function test_register_Emit_ProposerRegistered() external {
        vm.expectEmit(true, true, true, false);
        emit Proposers.ProposerRegistered(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);
    }

    // ---
    // unregister()
    // ---

    function test_unregister_HappyPath() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);

        assertEq(_proposers.proposers.length, 1);
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));
        assertTrue(_proposers.isExecutor(_ADMIN_EXECUTOR));

        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR, true);
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

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);

        assertFalse(_proposers.isProposer(_DEFAULT_PROPOSER));
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        _proposers.unregister(_DEFAULT_PROPOSER);
    }

    function test_uregister_Emit_ProposerUnregistered() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));

        vm.expectEmit(true, true, true, false);
        emit Proposers.ProposerUnregistered(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        _proposers.unregister(_ADMIN_PROPOSER);
    }

    // ---
    // getProposer()
    // ---

    function test_getProposer_HappyPath() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));

        Proposers.Proposer memory adminProposer = _proposers.getProposer(_ADMIN_PROPOSER);
        assertEq(adminProposer.account, _ADMIN_PROPOSER);
        assertEq(adminProposer.executor, _ADMIN_EXECUTOR);

        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR, true);
        assertTrue(_proposers.isProposer(_DEFAULT_PROPOSER));

        Proposers.Proposer memory defaultProposer = _proposers.getProposer(_DEFAULT_PROPOSER);
        assertEq(defaultProposer.account, _DEFAULT_PROPOSER);
        assertEq(defaultProposer.executor, _DEFAULT_EXECUTOR);
    }

    function test_getProposer_RevertOn_RetrievingUnregisteredProposer() external {
        assertFalse(_proposers.isProposer(_DEFAULT_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        _proposers.getProposer(_DEFAULT_PROPOSER);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);
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

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);
        assertTrue(_proposers.isProposer(_ADMIN_PROPOSER));

        Proposers.Proposer[] memory allProposers = _proposers.getAllProposers();
        assertEq(allProposers.length, 1);

        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[0].executor, _ADMIN_EXECUTOR);

        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR, true);
        assertTrue(_proposers.isProposer(_DEFAULT_PROPOSER));

        allProposers = _proposers.getAllProposers();
        assertEq(allProposers.length, 2);

        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[0].executor, _ADMIN_EXECUTOR);

        assertEq(allProposers[1].account, _DEFAULT_PROPOSER);
        assertEq(allProposers[1].executor, _DEFAULT_EXECUTOR);
    }

    // ---
    // Edge cases
    // ---

    function test_unregister_Spam() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);

        address dravee = makeAddr("Dravee");
        address draveeExecutor = makeAddr("draveeExecutor");
        address alice = makeAddr("Alice");
        address aliceExecutor = makeAddr("aliceExecutor");
        address celine = makeAddr("Celine");
        address celineExecutor = makeAddr("celineExecutor");
        address bob = makeAddr("Bob");
        address bobExecutor = makeAddr("bobExecutor");

        _proposers.register(alice, aliceExecutor, false);
        _proposers.register(bob, bobExecutor, true);
        _proposers.register(celine, celineExecutor, false);
        _proposers.register(dravee, draveeExecutor, true);

        _proposers.unregister(bob);
        _proposers.unregister(dravee);
        _proposers.unregister(celine);
        _proposers.unregister(alice);
    }

    function test_unregister_CorrectPosition() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR, true);

        address dravee = makeAddr("Dravee");
        address draveeExecutor = makeAddr("draveeExecutor");
        address alice = makeAddr("Alice");
        address aliceExecutor = makeAddr("aliceExecutor");
        address celine = makeAddr("Celine");
        address celineExecutor = makeAddr("celineExecutor");
        address bob = makeAddr("Bob");
        address bobExecutor = makeAddr("bobExecutor");

        _proposers.register(alice, aliceExecutor, false);
        _proposers.register(bob, bobExecutor, true);
        _proposers.register(celine, celineExecutor, false);
        _proposers.register(dravee, draveeExecutor, true);

        _proposers.unregister(bob);

        Proposers.Proposer[] memory allProposers = _proposers.getAllProposers();

        assertEq(allProposers.length, 4);
        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[1].account, alice);
        assertEq(allProposers[1].executor, aliceExecutor);
        assertEq(allProposers[2].account, dravee);
        assertEq(allProposers[2].executor, draveeExecutor);
        assertEq(allProposers[3].account, celine);
        assertEq(allProposers[3].executor, celineExecutor);

        _proposers.unregister(alice);

        allProposers = _proposers.getAllProposers();

        assertEq(allProposers.length, 3);
        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[1].account, celine);
        assertEq(allProposers[1].executor, celineExecutor);
        assertEq(allProposers[2].account, dravee);
        assertEq(allProposers[2].account, dravee);

        _proposers.unregister(dravee);

        allProposers = _proposers.getAllProposers();

        assertEq(allProposers.length, 2);
        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[1].account, celine);
        assertEq(allProposers[1].executor, celineExecutor);
    }
}
