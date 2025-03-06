// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "../../contracts/ImmutableDualGovernanceConfigProvider.sol";
import "../../contracts/DualGovernance.sol";
import "../../contracts/EmergencyProtectedTimelock.sol";
import "../../contracts/Escrow.sol";
import "../../contracts/model/StETHModel.sol";
import "../../contracts/model/WstETHAdapted.sol";
import "../../contracts/model/WithdrawalQueueModel.sol";
import "../../contracts/ResealManager.sol";

import {DualGovernanceConfig} from "../../contracts/libraries/DualGovernanceConfig.sol";
import {PercentD16} from "../../contracts/types/PercentD16.sol";
import {Duration, Durations} from "../../contracts/types/Duration.sol";

contract DebugDualGovernance {
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

        stEth = new StETHModel();
        stEth.setTotalPooledEther(32 ether);
        stEth.setTotalShares(32 ether);

        wstEth = new WstETHAdapted(IStETH(stEth));
        withdrawalQueue = new WithdrawalQueueModel(IStETH(stEth));

        // Placeholder addresses
        address adminExecutor = address(this);
        address emergencyGovernance = address(this);
        address adminProposer = address(this);

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
        dualGovernance.registerProposer(adminProposer, adminExecutor);
        timelock.setGovernance(address(dualGovernance));
        escrowMasterCopy = new Escrow(stEth, wstEth, withdrawalQueue, dualGovernance, 1);

        signallingEscrow = Escrow(payable(dualGovernance.getVetoSignallingEscrow()));
        rageQuitEscrow = Escrow(payable(Clones.clone(address(escrowMasterCopy))));

    }

    function debugSubmitProposal() external {
        Proposal proposal = new Proposal("Debug Proposal");
        ExternalCall[] memory calls = new ExternalCall[](1);
        calls[0] = ExternalCall({
            target: address(proposal),
            value: 0,
            payload: abi.encodeWithSelector(proposal.execute.selector)
        });
        dualGovernance.submitProposal(calls, "Debug Proposal");
    }
}

contract Proposal {

    bool public executed = false;
    string public name;

    constructor(string memory _name) {
        name = _name;
    }

    function execute() external {
        require(!executed, "Already executed");
        executed = true;
    }

}