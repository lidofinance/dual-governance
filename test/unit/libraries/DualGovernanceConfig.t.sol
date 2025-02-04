// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {Duration, Durations, MAX_DURATION_VALUE} from "contracts/types/Duration.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

import {DualGovernanceConfig, PercentD16} from "contracts/libraries/DualGovernanceConfig.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract DualGovernanceConfigTest is UnitTest {
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    PercentD16 internal immutable _MAX_SECOND_SEAL_RAGE_QUIT_SUPPORT =
        PercentsD16.from(DualGovernanceConfig.MAX_SECOND_SEAL_RAGE_QUIT_SUPPORT);
    Timestamp internal immutable _MAX_TIMESTAMP = Timestamps.from(block.timestamp + 100 * 365 days);

    // The actual max value will not exceed 255, but for testing is used higher upper bound
    uint256 internal immutable _MAX_RAGE_QUIT_ROUND = 512;

    DualGovernanceConfig.Context _dualGovernanceConfig = DualGovernanceConfig.Context({
        firstSealRageQuitSupport: PercentsD16.fromBasisPoints(10),
        secondSealRageQuitSupport: PercentsD16.fromBasisPoints(20),
        minAssetsLockDuration: Durations.from(1 days),
        vetoSignallingMinDuration: Durations.from(1 days),
        vetoSignallingMaxDuration: Durations.from(30 days),
        vetoSignallingMinActiveDuration: Durations.from(7 days),
        vetoSignallingDeactivationMaxDuration: Durations.from(3 days),
        vetoCooldownDuration: Durations.from(1 days),
        rageQuitExtensionPeriodDuration: Durations.from(1 days),
        rageQuitEthWithdrawalsMinDelay: Durations.from(15 days),
        rageQuitEthWithdrawalsMaxDelay: Durations.from(90 days),
        rageQuitEthWithdrawalsDelayGrowth: Durations.from(30 days)
    });

    // ---
    // validate()
    // ---

    function testFuzz_validate_HappyPath(DualGovernanceConfig.Context memory config) external {
        _assumeConfigParams(config);
        this.external__validate(config);
    }

    function testFuzz_validate_RevertOn_InvalidSecondSealRageQuitSupport(DualGovernanceConfig.Context memory config)
        external
    {
        vm.assume(config.secondSealRageQuitSupport > _MAX_SECOND_SEAL_RAGE_QUIT_SUPPORT);
        vm.assume(config.firstSealRageQuitSupport < config.secondSealRageQuitSupport);
        vm.assume(config.vetoSignallingMinDuration < config.vetoSignallingMaxDuration);
        vm.assume(config.rageQuitEthWithdrawalsMinDelay <= config.rageQuitEthWithdrawalsMaxDelay);
        vm.assume(config.minAssetsLockDuration > Durations.ZERO);

        vm.expectRevert(
            abi.encodeWithSelector(
                DualGovernanceConfig.InvalidSecondSealRageQuitSupport.selector, config.secondSealRageQuitSupport
            )
        );
        this.external__validate(config);
    }

    function testFuzz_validate_RevertOn_InvalidSealRageQuitSupportRange(DualGovernanceConfig.Context memory config)
        external
    {
        vm.assume(config.secondSealRageQuitSupport <= _MAX_SECOND_SEAL_RAGE_QUIT_SUPPORT);
        vm.assume(config.firstSealRageQuitSupport >= config.secondSealRageQuitSupport);
        vm.assume(config.vetoSignallingMinDuration < config.vetoSignallingMaxDuration);
        vm.assume(config.rageQuitEthWithdrawalsMinDelay <= config.rageQuitEthWithdrawalsMaxDelay);

        vm.expectRevert(
            abi.encodeWithSelector(
                DualGovernanceConfig.InvalidRageQuitSupportRange.selector,
                config.firstSealRageQuitSupport,
                config.secondSealRageQuitSupport
            )
        );
        this.external__validate(config);
    }

    function testFuzz_validate_RevertOn_InvalidVetoSignallingDurationRange(DualGovernanceConfig.Context memory config)
        external
    {
        vm.assume(config.firstSealRageQuitSupport < config.secondSealRageQuitSupport);
        vm.assume(config.secondSealRageQuitSupport < _MAX_SECOND_SEAL_RAGE_QUIT_SUPPORT);
        vm.assume(config.vetoSignallingMinDuration >= config.vetoSignallingMaxDuration);
        vm.assume(config.rageQuitEthWithdrawalsMinDelay <= config.rageQuitEthWithdrawalsMaxDelay);

        vm.expectRevert(
            abi.encodeWithSelector(
                DualGovernanceConfig.InvalidVetoSignallingDurationRange.selector,
                config.vetoSignallingMinDuration,
                config.vetoSignallingMaxDuration
            )
        );
        this.external__validate(config);
    }

    function testFuzz_validate_RevertOn_InvalidRageQuitEthWithdrawalsDelayRange(
        DualGovernanceConfig.Context memory config
    ) external {
        vm.assume(config.firstSealRageQuitSupport < config.secondSealRageQuitSupport);
        vm.assume(config.secondSealRageQuitSupport < _MAX_SECOND_SEAL_RAGE_QUIT_SUPPORT);
        vm.assume(config.vetoSignallingMinDuration < config.vetoSignallingMaxDuration);
        vm.assume(config.rageQuitEthWithdrawalsMinDelay > config.rageQuitEthWithdrawalsMaxDelay);

        vm.expectRevert(
            abi.encodeWithSelector(
                DualGovernanceConfig.InvalidRageQuitEthWithdrawalsDelayRange.selector,
                config.rageQuitEthWithdrawalsMinDelay,
                config.rageQuitEthWithdrawalsMaxDelay
            )
        );
        this.external__validate(config);
    }

    function test_validate_RevertOn_InvalidMinAssetsLockDuration() external {
        _dualGovernanceConfig.minAssetsLockDuration = Durations.ZERO;

        vm.expectRevert(
            abi.encodeWithSelector(DualGovernanceConfig.InvalidMinAssetsLockDuration.selector, Durations.ZERO)
        );
        this.external__validate(_dualGovernanceConfig);
    }

    // ---
    // isFirstSealRageQuitSupportReached()
    // ---

    function testFuzz_isFirstSealRageQuitSupportReached_HappyPath(
        DualGovernanceConfig.Context memory config,
        PercentD16 rageQuitSupport
    ) external {
        _assumeConfigParams(config);
        assertEq(
            config.isFirstSealRageQuitSupportReached(rageQuitSupport),
            rageQuitSupport >= config.firstSealRageQuitSupport
        );
    }

    // ---
    // isSecondSealRageQuitSupportReached()
    // ---

    function testFuzz_isSecondSealRageQuitSupportReached_HappyPath(
        DualGovernanceConfig.Context memory config,
        PercentD16 rageQuitSupport
    ) external {
        _assumeConfigParams(config);
        assertEq(
            config.isSecondSealRageQuitSupportReached(rageQuitSupport),
            rageQuitSupport >= config.secondSealRageQuitSupport
        );
    }

    // ---
    // isVetoSignallingDurationPassed()
    // ---

    function testFuzz_isVetoSignallingDurationPassed_HappyPath(
        DualGovernanceConfig.Context memory config,
        Timestamp vetoSignallingActivatedAt,
        PercentD16 rageQuitSupport
    ) external {
        _assumeConfigParams(config);
        vm.assume(vetoSignallingActivatedAt <= _MAX_TIMESTAMP);

        Duration vetoSignallingDuration = config.calcVetoSignallingDuration(rageQuitSupport);
        Timestamp vetoSignallingDurationEndTime = vetoSignallingDuration.addTo(vetoSignallingActivatedAt);

        assertEq(
            config.isVetoSignallingDurationPassed(vetoSignallingActivatedAt, rageQuitSupport),
            Timestamps.now() > vetoSignallingDurationEndTime
        );
    }

    // ---
    // isVetoSignallingReactivationDurationPassed()
    // ---
    function testFuzz_isVetoSignallingReactivationDurationPassed_HappyPath(
        DualGovernanceConfig.Context memory config,
        Timestamp vetoSignallingReactivationTime
    ) external {
        _assumeConfigParams(config);
        vm.assume(vetoSignallingReactivationTime <= _MAX_TIMESTAMP);

        Timestamp reactivationDurationPassedAfter =
            config.vetoSignallingMinActiveDuration.addTo(vetoSignallingReactivationTime);

        assertEq(
            config.isVetoSignallingReactivationDurationPassed(vetoSignallingReactivationTime),
            Timestamps.now() > reactivationDurationPassedAfter
        );
    }

    function test_isVetoSignallingReactivationDurationPassed_HappyPath_EdgeCase() external {
        DualGovernanceConfig.Context memory config;

        Timestamp vetoSignallingReactivatedAt = Timestamps.now();
        config.vetoSignallingMinActiveDuration = Durations.from(30 days);
        Timestamp vetoSignallingReactivationTimestamp =
            config.vetoSignallingMinActiveDuration.addTo(vetoSignallingReactivatedAt);

        _wait(config.vetoSignallingMinActiveDuration);
        assertEq(Timestamps.now(), vetoSignallingReactivationTimestamp);

        assertFalse(config.isVetoSignallingReactivationDurationPassed(vetoSignallingReactivatedAt));

        _wait(Durations.from(1 seconds));
        assertTrue(config.isVetoSignallingReactivationDurationPassed(vetoSignallingReactivatedAt));
    }

    // ---
    // isVetoSignallingDeactivationMaxDurationPassed()
    // ---

    function testFuzz_isVetoSignallingDeactivationMaxDurationPassed_HappyPath(
        DualGovernanceConfig.Context memory config,
        Timestamp vetoSignallingDeactivationEnteredAt
    ) external {
        _assumeConfigParams(config);
        vm.assume(vetoSignallingDeactivationEnteredAt <= _MAX_TIMESTAMP);

        Timestamp vetoSignallingDeactivationTimestamp =
            config.vetoSignallingDeactivationMaxDuration.addTo(vetoSignallingDeactivationEnteredAt);

        assertEq(
            config.isVetoSignallingDeactivationMaxDurationPassed(vetoSignallingDeactivationEnteredAt),
            Timestamps.now() > vetoSignallingDeactivationTimestamp
        );
    }

    function test_isVetoSignallingDeactivationMaxDurationPassed_HappyPath_EdgeCase() external {
        DualGovernanceConfig.Context memory config;

        Timestamp vetoSignallingDeactivationEnteredAt = Timestamps.now();
        config.vetoSignallingDeactivationMaxDuration = Durations.from(3 days);
        Timestamp vetoSignallingDeactivationEndsAfter =
            config.vetoSignallingDeactivationMaxDuration.addTo(vetoSignallingDeactivationEnteredAt);

        _wait(config.vetoSignallingDeactivationMaxDuration);

        assertEq(Timestamps.now(), vetoSignallingDeactivationEndsAfter);
        assertFalse(config.isVetoSignallingDeactivationMaxDurationPassed(vetoSignallingDeactivationEnteredAt));

        _wait(Durations.from(1 seconds));
        assertTrue(config.isVetoSignallingDeactivationMaxDurationPassed(vetoSignallingDeactivationEnteredAt));
    }

    // ---
    // isVetoCooldownDurationPassed()
    // ---

    function testFuzz_isVetoCooldownDurationPassed_HappyPath(
        DualGovernanceConfig.Context memory config,
        Timestamp vetoCooldownEnteredAt
    ) external {
        _assumeConfigParams(config);
        vm.assume(vetoCooldownEnteredAt <= _MAX_TIMESTAMP);

        Timestamp vetoCooldownEndsAfter = config.vetoCooldownDuration.addTo(vetoCooldownEnteredAt);

        assertEq(config.isVetoCooldownDurationPassed(vetoCooldownEnteredAt), Timestamps.now() > vetoCooldownEndsAfter);
    }

    function test_isVetoCooldownDurationPassed_HappyPath_EdgeCases() external {
        DualGovernanceConfig.Context memory config;

        Timestamp vetoCooldownEnteredAt = Timestamps.now();
        config.vetoCooldownDuration = Durations.from(5 hours);
        Timestamp vetoCooldownEndsAfter = config.vetoCooldownDuration.addTo(vetoCooldownEnteredAt);

        _wait(config.vetoCooldownDuration);

        assertEq(Timestamps.now(), vetoCooldownEndsAfter);
        assertFalse(config.isVetoCooldownDurationPassed(vetoCooldownEnteredAt));

        _wait(Durations.from(1 seconds));
        assertTrue(config.isVetoCooldownDurationPassed(vetoCooldownEnteredAt));
    }

    // ---
    // calcVetoSignallingDuration()
    // ---

    function testFuzz_calcVetoSignallingDuration_HappyPath_RageQuitSupportLessThanFirstSeal(
        DualGovernanceConfig.Context memory config,
        PercentD16 rageQuitSupport
    ) external {
        _assumeConfigParams(config);
        vm.assume(rageQuitSupport < config.firstSealRageQuitSupport);
        assertEq(config.calcVetoSignallingDuration(rageQuitSupport), Durations.ZERO);
    }

    function testFuzz_calcVetoSignallingDuration_HappyPath_RageQuitSupportGreaterOrEqualThanSecondSeal(
        DualGovernanceConfig.Context memory config,
        PercentD16 rageQuitSupport
    ) external {
        _assumeConfigParams(config);
        vm.assume(rageQuitSupport >= config.secondSealRageQuitSupport);
        assertEq(config.calcVetoSignallingDuration(rageQuitSupport), config.vetoSignallingMaxDuration);
    }

    function testFuzz_calcVetoSignallingDuration_HappyPath_RageQuitSupportInsideSealsRange(
        DualGovernanceConfig.Context memory config,
        PercentD16 rageQuitSupport
    ) external {
        _assumeConfigParams(config);
        vm.assume(rageQuitSupport >= config.firstSealRageQuitSupport);
        vm.assume(rageQuitSupport < config.secondSealRageQuitSupport);

        PercentD16 rageQuitSupportFirstSealDelta = rageQuitSupport - config.firstSealRageQuitSupport;
        PercentD16 secondFirstSealRangeDelta = config.secondSealRageQuitSupport - config.firstSealRageQuitSupport;
        Duration vetoSignallingMaxMinDurationDelta = config.vetoSignallingMaxDuration - config.vetoSignallingMinDuration;

        Duration expectedDuration = config.vetoSignallingMinDuration
            + Durations.from(
                PercentD16.unwrap(rageQuitSupportFirstSealDelta) * vetoSignallingMaxMinDurationDelta.toSeconds()
                    / PercentD16.unwrap(secondFirstSealRangeDelta)
            );

        assertEq(config.calcVetoSignallingDuration(rageQuitSupport), expectedDuration);
    }

    // ---
    // calcRageQuitWithdrawalsDelay()
    // ---

    function test_calcRageQuitWithdrawalsDelay_HappyPath_MinDelayWhenRageQuitRoundIsZero() external {
        DualGovernanceConfig.Context memory config;

        config.rageQuitEthWithdrawalsMinDelay = Durations.from(15 days);
        config.rageQuitEthWithdrawalsMaxDelay = Durations.from(90 days);
        config.rageQuitEthWithdrawalsDelayGrowth = Durations.from(30 days);

        assertEq(config.calcRageQuitWithdrawalsDelay({rageQuitRound: 0}), config.rageQuitEthWithdrawalsMinDelay);
    }

    function test_calcRageQuitWithdrawalsDelay_HappyPath_MaxDelayWhenRageQuitRoundIsMaxRageQuitRound() external {
        DualGovernanceConfig.Context memory config;

        config.rageQuitEthWithdrawalsMinDelay = Durations.from(15 days);
        config.rageQuitEthWithdrawalsMaxDelay = Durations.from(90 days);
        config.rageQuitEthWithdrawalsDelayGrowth = Durations.from(30 days);

        assertEq(
            config.calcRageQuitWithdrawalsDelay({rageQuitRound: _MAX_RAGE_QUIT_ROUND}),
            config.rageQuitEthWithdrawalsMaxDelay
        );
    }

    function testFuzz_calcRageQuitWithdrawalsDelay_HappyPath(
        DualGovernanceConfig.Context memory config,
        uint16 rageQuitRound
    ) external {
        _assumeConfigParams(config);
        vm.assume(rageQuitRound <= _MAX_RAGE_QUIT_ROUND);

        uint256 computedRageQuitEthWithdrawalsDelayInSeconds = config.rageQuitEthWithdrawalsMinDelay.toSeconds()
            + rageQuitRound * config.rageQuitEthWithdrawalsDelayGrowth.toSeconds();

        if (computedRageQuitEthWithdrawalsDelayInSeconds > config.rageQuitEthWithdrawalsMaxDelay.toSeconds()) {
            computedRageQuitEthWithdrawalsDelayInSeconds = config.rageQuitEthWithdrawalsMaxDelay.toSeconds();
        }
        assertEq(
            config.calcRageQuitWithdrawalsDelay(rageQuitRound),
            Durations.from(computedRageQuitEthWithdrawalsDelayInSeconds)
        );
    }

    // ---
    // Helper Methods
    // ---

    function _assumeConfigParams(DualGovernanceConfig.Context memory config) internal view {
        vm.assume(config.firstSealRageQuitSupport < config.secondSealRageQuitSupport);
        vm.assume(config.vetoSignallingMinDuration < config.vetoSignallingMaxDuration);
        vm.assume(config.secondSealRageQuitSupport <= _MAX_SECOND_SEAL_RAGE_QUIT_SUPPORT);
        vm.assume(config.rageQuitEthWithdrawalsMinDelay <= config.rageQuitEthWithdrawalsMaxDelay);
        vm.assume(config.minAssetsLockDuration > Durations.ZERO);
    }

    function external__validate(DualGovernanceConfig.Context memory config) external {
        config.validate();
    }
}
