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
        this.external__register(address(0), _ADMIN_EXECUTOR);
    }

    function test_register_RevertOn_InvalidExecutor() external {
        vm.expectRevert(abi.encodeWithSelector(Proposers.InvalidExecutor.selector, address(0)));
        this.external__register(_ADMIN_PROPOSER, address(0));
    }

    function test_register_RevertOn_ProposerAlreadyRegistered() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerAlreadyRegistered.selector, _ADMIN_PROPOSER));
        this.external__register(_ADMIN_PROPOSER, _DEFAULT_EXECUTOR);
    }

    function test_register_Emit_ProposerRegistered() external {
        vm.expectEmit(true, true, true, false);
        emit Proposers.ProposerRegistered(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
    }

    // ---
    // setProposerExecutor()
    // ---

    function test_setProposerExecutor_HappyPath() external {
        Proposers.Proposer memory defaultProposer = _registerProposer(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);
        assertNotEq(defaultProposer.executor, _ADMIN_EXECUTOR);

        uint256 adminExecutorRefsCountBefore = _proposers.executorRefsCounts[_ADMIN_EXECUTOR];
        uint256 defaultExecutorRefsCountBefore = _proposers.executorRefsCounts[_DEFAULT_EXECUTOR];

        vm.expectEmit(true, true, false, false);
        emit Proposers.ProposerExecutorSet(defaultProposer.account, _ADMIN_EXECUTOR);

        _proposers.setProposerExecutor(defaultProposer.account, _ADMIN_EXECUTOR);

        defaultProposer = _proposers.getProposer(_DEFAULT_PROPOSER);
        assertEq(defaultProposer.executor, _ADMIN_EXECUTOR);

        // check executor references updated properly
        assertEq(_proposers.executorRefsCounts[_DEFAULT_EXECUTOR], defaultExecutorRefsCountBefore - 1);
        assertEq(_proposers.executorRefsCounts[_ADMIN_EXECUTOR], adminExecutorRefsCountBefore + 1);
    }

    function test_setProposerExecutor_RevertOn_ZeroAddressExecutor() external {
        Proposers.Proposer memory defaultProposer = _registerProposer(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.InvalidExecutor.selector, address(0)));
        this.external__setProposerExecutor(defaultProposer.account, address(0));
    }

    function test_setProposerExecutor_RevertOn_SameExecutorAddress() external {
        Proposers.Proposer memory defaultProposer = _registerProposer(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.InvalidExecutor.selector, _DEFAULT_EXECUTOR));
        this.external__setProposerExecutor(defaultProposer.account, _DEFAULT_EXECUTOR);
    }

    function test_setProposerExecutor_RevertOn_NonRegisteredPropsoer() external {
        assertEq(_proposers.proposers.length, 0);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        this.external__setProposerExecutor(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);
    }

    // ---
    // unregister()
    // ---

    function test_unregister_HappyPath() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        assertEq(_proposers.proposers.length, 1);
        assertTrue(_proposers.isRegisteredProposer(_ADMIN_PROPOSER));
        assertTrue(_proposers.isRegisteredExecutor(_ADMIN_EXECUTOR));

        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);
        assertEq(_proposers.proposers.length, 2);
        assertTrue(_proposers.isRegisteredProposer(_DEFAULT_PROPOSER));
        assertTrue(_proposers.isRegisteredExecutor(_DEFAULT_EXECUTOR));

        _proposers.unregister(_DEFAULT_PROPOSER);
        assertEq(_proposers.proposers.length, 1);
        assertFalse(_proposers.isRegisteredProposer(_DEFAULT_PROPOSER));
        assertFalse(_proposers.isRegisteredExecutor(_DEFAULT_EXECUTOR));

        _proposers.unregister(_ADMIN_PROPOSER);
        assertEq(_proposers.proposers.length, 0);
        assertFalse(_proposers.isRegisteredProposer(_ADMIN_PROPOSER));
        assertFalse(_proposers.isRegisteredExecutor(_ADMIN_EXECUTOR));
    }

    function test_unregister_RevertOn_ProposerIsNotRegistered() external {
        assertFalse(_proposers.isRegisteredProposer(_DEFAULT_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        this.external__unregister(_DEFAULT_PROPOSER);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        assertFalse(_proposers.isRegisteredProposer(_DEFAULT_PROPOSER));
        assertTrue(_proposers.isRegisteredProposer(_ADMIN_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        this.external__unregister(_DEFAULT_PROPOSER);
    }

    function test_uregister_Emit_ProposerUnregistered() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
        assertTrue(_proposers.isRegisteredProposer(_ADMIN_PROPOSER));

        vm.expectEmit(true, true, true, false);
        emit Proposers.ProposerUnregistered(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        _proposers.unregister(_ADMIN_PROPOSER);
    }

    // ---
    // getProposer()
    // ---

    function test_getProposer_HappyPath() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
        assertTrue(_proposers.isRegisteredProposer(_ADMIN_PROPOSER));

        Proposers.Proposer memory adminProposer = _proposers.getProposer(_ADMIN_PROPOSER);
        assertEq(adminProposer.account, _ADMIN_PROPOSER);
        assertEq(adminProposer.executor, _ADMIN_EXECUTOR);

        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);
        assertTrue(_proposers.isRegisteredProposer(_DEFAULT_PROPOSER));

        Proposers.Proposer memory defaultProposer = _proposers.getProposer(_DEFAULT_PROPOSER);
        assertEq(defaultProposer.account, _DEFAULT_PROPOSER);
        assertEq(defaultProposer.executor, _DEFAULT_EXECUTOR);
    }

    function test_getProposer_RevertOn_RetrievingUnregisteredProposer() external {
        assertFalse(_proposers.isRegisteredProposer(_DEFAULT_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        this.external__getProposer(_DEFAULT_PROPOSER);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
        assertTrue(_proposers.isRegisteredProposer(_ADMIN_PROPOSER));
        assertFalse(_proposers.isRegisteredProposer(_DEFAULT_PROPOSER));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, _DEFAULT_PROPOSER));
        this.external__getProposer(_DEFAULT_PROPOSER);
    }

    // ---
    // getAllProposer()
    // ---

    function test_getAllProposers_HappyPath() external {
        Proposers.Proposer[] memory emptyProposers = _proposers.getAllProposers();
        assertEq(emptyProposers.length, 0);

        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);
        assertTrue(_proposers.isRegisteredProposer(_ADMIN_PROPOSER));

        Proposers.Proposer[] memory allProposers = _proposers.getAllProposers();
        assertEq(allProposers.length, 1);

        assertEq(allProposers[0].account, _ADMIN_PROPOSER);
        assertEq(allProposers[0].executor, _ADMIN_EXECUTOR);

        _proposers.register(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);
        assertTrue(_proposers.isRegisteredProposer(_DEFAULT_PROPOSER));

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
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        address dravee = makeAddr("Dravee");
        address draveeExecutor = makeAddr("draveeExecutor");
        address alice = makeAddr("Alice");
        address aliceExecutor = makeAddr("aliceExecutor");
        address celine = makeAddr("Celine");
        address celineExecutor = makeAddr("celineExecutor");
        address bob = makeAddr("Bob");
        address bobExecutor = makeAddr("bobExecutor");

        _proposers.register(alice, aliceExecutor);
        _proposers.register(bob, bobExecutor);
        _proposers.register(celine, celineExecutor);
        _proposers.register(dravee, draveeExecutor);

        _proposers.unregister(bob);
        _proposers.unregister(dravee);
        _proposers.unregister(celine);
        _proposers.unregister(alice);
    }

    function test_unregister_CorrectPosition() external {
        _proposers.register(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        address dravee = makeAddr("Dravee");
        address draveeExecutor = makeAddr("draveeExecutor");
        address alice = makeAddr("Alice");
        address aliceExecutor = makeAddr("aliceExecutor");
        address celine = makeAddr("Celine");
        address celineExecutor = makeAddr("celineExecutor");
        address bob = makeAddr("Bob");
        address bobExecutor = makeAddr("bobExecutor");

        _proposers.register(alice, aliceExecutor);
        _proposers.register(bob, bobExecutor);
        _proposers.register(celine, celineExecutor);
        _proposers.register(dravee, draveeExecutor);

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

    // ---
    // checkRegisteredExecutor()
    // ---

    function test_checkRegisteredExecutor_HappyPath() external {
        address notExecutor = makeAddr("notExecutor");

        assertEq(_proposers.proposers.length, 0);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ExecutorNotRegistered.selector, _ADMIN_EXECUTOR));
        this.external__checkRegisteredExecutor(_ADMIN_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ExecutorNotRegistered.selector, _DEFAULT_EXECUTOR));
        this.external__checkRegisteredExecutor(_DEFAULT_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ExecutorNotRegistered.selector, notExecutor));
        this.external__checkRegisteredExecutor(notExecutor);

        // ---
        // register admin proposer
        // ---

        _registerProposer(_ADMIN_PROPOSER, _ADMIN_EXECUTOR);

        this.external__checkRegisteredExecutor(_ADMIN_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ExecutorNotRegistered.selector, _DEFAULT_EXECUTOR));
        this.external__checkRegisteredExecutor(_DEFAULT_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ExecutorNotRegistered.selector, notExecutor));
        this.external__checkRegisteredExecutor(notExecutor);

        // ---
        // register default proposer
        // ---

        _registerProposer(_DEFAULT_PROPOSER, _DEFAULT_EXECUTOR);

        this.external__checkRegisteredExecutor(_ADMIN_EXECUTOR);

        this.external__checkRegisteredExecutor(_DEFAULT_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ExecutorNotRegistered.selector, notExecutor));
        this.external__checkRegisteredExecutor(notExecutor);

        // ---
        // change default proposer's executor on admin
        // ---

        _proposers.setProposerExecutor(_DEFAULT_PROPOSER, _ADMIN_EXECUTOR);

        this.external__checkRegisteredExecutor(_ADMIN_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ExecutorNotRegistered.selector, _DEFAULT_EXECUTOR));
        this.external__checkRegisteredExecutor(_DEFAULT_EXECUTOR);

        vm.expectRevert(abi.encodeWithSelector(Proposers.ExecutorNotRegistered.selector, notExecutor));
        this.external__checkRegisteredExecutor(notExecutor);
    }

    // ---
    // Helper Methods
    // ---

    function _registerProposer(
        address account,
        address executor
    ) private returns (Proposers.Proposer memory proposer) {
        uint256 proposersCountBefore = _proposers.proposers.length;
        uint256 executorRefsCountBefore = _proposers.executorRefsCounts[executor];

        _proposers.register(account, executor);

        uint256 proposersCountAfter = _proposers.proposers.length;
        uint256 executorRefsCountAfter = _proposers.executorRefsCounts[executor];

        assertEq(proposersCountAfter, proposersCountBefore + 1);
        assertEq(executorRefsCountAfter, executorRefsCountBefore + 1);

        proposer = _proposers.getProposer(account);

        assertEq(proposer.account, account, "Invalid proposer account");
        assertEq(proposer.executor, executor, "Invalid proposer executor");
    }

    function external__setProposerExecutor(address proposer, address executor) external {
        _proposers.setProposerExecutor(proposer, executor);
    }

    function external__checkRegisteredExecutor(address executor) external view {
        _proposers.checkRegisteredExecutor(executor);
    }

    function external__register(address proposerAccount, address executor) external {
        _proposers.register(proposerAccount, executor);
    }

    function external__unregister(address proposerAccount) external {
        _proposers.unregister(proposerAccount);
    }

    function external__getProposer(address proposerAccount) external view {
        _proposers.getProposer(proposerAccount);
    }
}
