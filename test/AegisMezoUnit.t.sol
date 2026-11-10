// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MezoAddresses} from "../src/libraries/MezoAddresses.sol";
import {
    IERC20,
    IPriceFeed,
    IMezoPool,
    IStabilityPool
} from "../src/interfaces/IMezoCore.sol";
import {MusdPegGuard} from "../src/MusdPegGuard.sol";
import {MUSDCarryEngine} from "../src/MUSDCarryEngine.sol";
import {MezoBoostExchange} from "../src/MezoBoostExchange.sol";
import {AegisTroveVault, AegisUserTroveProxy} from "../src/AegisTroveVault.sol";
import {MezoFloatRefiller} from "../src/MezoFloatRefiller.sol";

contract UnitNativePrecompileShim {
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, 74_195_474260000000000000, block.timestamp, block.timestamp, 1);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function balanceOf(address account) external view returns (uint256) {
        return account.balance;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }
}

/// @title AegisMezoUnitTest
/// @notice 38 Unit Tests validating every functional module, mathematical invariant, security guard,
///         tier rebate, peg deviation threshold, boost curve, carry router, and x402 clearing rail.
contract AegisMezoUnitTest is Test {
    MusdPegGuard public pegGuard;
    MUSDCarryEngine public carryEngine;
    MezoBoostExchange public boostExchange;
    AegisTroveVault public aegisVault;
    MezoFloatRefiller public floatRefiller;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public merchant = makeAddr("merchant");
    address public agent = makeAddr("agent");

    function setUp() public {
        if (block.chainid == 31611) {
            UnitNativePrecompileShim shim = new UnitNativePrecompileShim();
            vm.etch(0x7b7c000000000000000000000000000000000015, address(shim).code);
            vm.etch(MezoAddresses.BTC_ERC20, address(shim).code);
            vm.etch(MezoAddresses.MEZO_ERC20, address(shim).code);
        }

        pegGuard = new MusdPegGuard(
            MezoAddresses.PRICE_FEED,
            MezoAddresses.MUSD,
            MezoAddresses.MUSDC,
            MezoAddresses.MAMUSD,
            MezoAddresses.MUSD_MUSDC_POOL,
            MezoAddresses.MAMUSD_MUSD_POOL,
            MezoAddresses.MUSD_BTC_POOL
        );

        carryEngine = new MUSDCarryEngine(
            MezoAddresses.MUSD,
            MezoAddresses.STABILITY_POOL,
            MezoAddresses.MAMUSD,
            MezoAddresses.MAMUSD_MUSD_POOL,
            MezoAddresses.MEZO_POOLS_ROUTER,
            MezoAddresses.MEZO_POOLS_FACTORY,
            MezoAddresses.MEZO_POOLS_SWAPPER,
            MezoAddresses.SUSDAT
        );

        boostExchange = new MezoBoostExchange(
            MezoAddresses.MUSD,
            MezoAddresses.BTC_ERC20,
            MezoAddresses.MEZO_ERC20,
            MezoAddresses.VE_BTC,
            MezoAddresses.VE_MEZO,
            MezoAddresses.BOOSTER,
            MezoAddresses.VOTER,
            MezoAddresses.SPLITTER
        );

        aegisVault = new AegisTroveVault(
            MezoAddresses.MUSD,
            MezoAddresses.BORROWER_OPERATIONS,
            MezoAddresses.TROVE_MANAGER,
            MezoAddresses.SORTED_TROVES,
            MezoAddresses.HINT_HELPERS,
            MezoAddresses.PRICE_FEED,
            address(pegGuard),
            payable(address(carryEngine)),
            payable(address(boostExchange))
        );

        floatRefiller = new MezoFloatRefiller(
            MezoAddresses.MUSD,
            MezoAddresses.MUSDC,
            MezoAddresses.MUSD_MUSDC_POOL,
            MezoAddresses.MUSD_BTC_POOL,
            MezoAddresses.MEZO_POOLS_ROUTER,
            MezoAddresses.MEZO_POOLS_SWAPPER,
            MezoAddresses.PRICE_FEED,
            MezoAddresses.WORMHOLE_NTT_MANAGER,
            address(pegGuard),
            payable(address(aegisVault)),
            payable(address(carryEngine))
        );

        carryEngine.setAuthorizedModules(address(aegisVault), address(floatRefiller));
        boostExchange.setAegisVault(address(aegisVault));
        aegisVault.setFloatRefiller(address(floatRefiller));

        // Ensure PriceFeed returns $75,000 if running in a local non-forked VM
        if (MezoAddresses.PRICE_FEED.code.length == 0) {
            vm.mockCall(
                MezoAddresses.PRICE_FEED,
                abi.encodeWithSelector(IPriceFeed.fetchPrice.selector),
                abi.encode(75_000e18)
            );
        }

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
    }

    // =========================================================================
    // 1. Canonical Address Matrix & Constants (Tests 1 - 5)
    // =========================================================================

    function testUnit_01_CanonicalMusdAndCoreAddresses() public pure {
        assertEq(MezoAddresses.MUSD, 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503);
        assertEq(MezoAddresses.BORROWER_OPERATIONS, 0xCdF7028ceAB81fA0C6971208e83fa7872994beE5);
        assertEq(MezoAddresses.TROVE_MANAGER, 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0);
        assertEq(MezoAddresses.SORTED_TROVES, 0x722E4D24FD6Ff8b0AC679450F3D91294607268fA);
        assertEq(MezoAddresses.HINT_HELPERS, 0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6);
        assertEq(MezoAddresses.STABILITY_POOL, 0x1CCA7E410eE41739792eA0A24e00349Dd247680e);
        assertEq(MezoAddresses.PRICE_FEED, 0x86bCF0841622a5dAC14A313a15f96A95421b9366);
    }

    function testUnit_02_CanonicalPoolsAndYieldAddresses() public pure {
        assertEq(MezoAddresses.MAMUSD, 0xA8BAc7913D5163E2dF9aE3aF5B0AEeA44529Ac70);
        assertEq(MezoAddresses.MAMUSD_MUSD_POOL, 0xBF329A2A130cb0D5B5218f1672E51Fb36089FDE0);
        assertEq(MezoAddresses.MUSD_MUSDC_POOL, 0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e);
        assertEq(MezoAddresses.MUSD_BTC_POOL, 0xd16A5Df82120ED8D626a1a15232bFcE2366d6AA9);
        assertEq(MezoAddresses.MEZO_POOLS_ROUTER, 0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9);
        assertEq(MezoAddresses.SUSDAT, 0xBCaf6f2a7BEfc4Fc64CeeC6D8e4872941d52Ee87);
    }

    function testUnit_03_CanonicalVeTokenomicsAndBridgeAddresses() public pure {
        assertEq(MezoAddresses.VE_BTC, 0x38E35d92E6Bfc6787272A62345856B13eA12130a);
        assertEq(MezoAddresses.VE_MEZO, 0xaCE816CA2bcc9b12C59799dcC5A959Fb9b98111b);
        assertEq(MezoAddresses.BOOSTER, 0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1);
        assertEq(MezoAddresses.VOTER, 0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D);
        assertEq(MezoAddresses.SPLITTER, 0x47FbB2e6d3f6EF14AF3553d139e8af6cc92ed51F);
        assertEq(MezoAddresses.WORMHOLE_NTT_MANAGER, 0xBA0486fdBbd2FF63Ac55FBB736805785E1BeD1E3);
    }

    function testUnit_04_ChainIdConstants() public pure {
        assertEq(MezoAddresses.MEZO_TESTNET_CHAIN_ID, 31611);
        assertEq(MezoAddresses.MEZO_MAINNET_CHAIN_ID, 31612);
        assertEq(MezoAddresses.BASE_MAINNET_CHAIN_ID, 8453);
    }

    function testUnit_05_SystemCrossModuleWiring() public view {
        assertEq(carryEngine.aegisVault(), address(aegisVault));
        assertEq(carryEngine.floatRefiller(), address(floatRefiller));
        assertEq(boostExchange.aegisVault(), address(aegisVault));
        assertEq(aegisVault.floatRefiller(), address(floatRefiller));
    }

    // =========================================================================
    // 2. MusdPegGuard Telemetry & Floor Enforcement (Tests 6 - 13)
    // =========================================================================

    function testUnit_06_PegGuardDefaultParameters() public view {
        assertEq(pegGuard.discountThresholdBps(), 40);
        assertEq(pegGuard.minSettlementPriceFloor(), 0.985e18);
        assertEq(pegGuard.maxBtcDivergenceBps(), 500);
    }

    function testUnit_07_PegGuardEvaluatePegAtPar() public {
        vm.mockCall(
            MezoAddresses.MUSD_MUSDC_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 10e18, MezoAddresses.MUSD),
            abi.encode(10e6) // 1.00 USDC
        );
        vm.mockCall(
            MezoAddresses.MAMUSD_MUSD_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 1e18, MezoAddresses.MUSD),
            abi.encode(1e18)
        );
        vm.mockCall(
            MezoAddresses.MUSD_BTC_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 100e18, MezoAddresses.MUSD),
            abi.encode(uint256(100e18 * 1e18) / uint256(74_195e18))
        );
        MusdPegGuard.PegTelemetry memory t = pegGuard.evaluatePeg();
        assertGe(t.compositePegPrice, 0.99e18);
        assertFalse(t.isPegDiscounted);
    }

    function testUnit_08_PegGuardDetectsDiscountAndRedemptionPressure() public {
        // Simulate MUSD trading at $0.988 in MUSD/mUSDC and maMUSD/MUSD pools
        vm.etch(MezoAddresses.MUSD_MUSDC_POOL, hex"600160005260206000f3");
        vm.etch(MezoAddresses.MAMUSD_MUSD_POOL, hex"600160005260206000f3");
        vm.etch(MezoAddresses.MUSD_BTC_POOL, hex"600160005260206000f3");

        vm.mockCall(
            MezoAddresses.MUSD_MUSDC_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 10e18, MezoAddresses.MUSD),
            abi.encode(9_880_000) // $0.988 per MUSD
        );
        vm.mockCall(
            MezoAddresses.MAMUSD_MUSD_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 1e18, MezoAddresses.MUSD),
            abi.encode(0.990e18)
        );
        vm.mockCall(
            MezoAddresses.MUSD_BTC_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 100e18, MezoAddresses.MUSD),
            abi.encode((99e18 * 1e18) / 75_000e18)
        );

        MusdPegGuard.PegTelemetry memory t = pegGuard.evaluatePeg();
        assertTrue(t.isPegDiscounted, "Must detect peg discount below 40 bps threshold");
        assertGt(t.pegDeviationBps, 40);
        assertGt(t.redemptionPressureBps, 0);
    }

    function testUnit_09_PegGuardEnforceSettlementFloorSuccess() public {
        vm.mockCall(
            MezoAddresses.MUSD_MUSDC_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 10e18, MezoAddresses.MUSD),
            abi.encode(10e6)
        );
        vm.mockCall(
            MezoAddresses.MAMUSD_MUSD_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 1e18, MezoAddresses.MUSD),
            abi.encode(1e18)
        );
        vm.mockCall(
            MezoAddresses.MUSD_BTC_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 100e18, MezoAddresses.MUSD),
            abi.encode(uint256(100e18 * 1e18) / uint256(74_195e18))
        );
        MusdPegGuard.PegTelemetry memory t = pegGuard.enforceSettlementFloor(0.995e18);
        assertGt(t.compositePegPrice, 0.985e18);
    }

    function testUnit_10_PegGuardEnforceSettlementFloorRevertsWhenTooLow() public {
        vm.expectRevert(
            abi.encodeWithSelector(MusdPegGuard.PriceBelowSettlementFloor.selector, 0.970e18, 0.985e18)
        );
        pegGuard.enforceSettlementFloor(0.970e18);
    }

    function testUnit_11_PegGuardSetPegConfigOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(MusdPegGuard.Unauthorized.selector);
        pegGuard.setPegConfig(50, 0.99e18, 300);

        pegGuard.setPegConfig(50, 0.99e18, 300);
        assertEq(pegGuard.discountThresholdBps(), 50);
        assertEq(pegGuard.minSettlementPriceFloor(), 0.99e18);
    }

    function testUnit_12_PegGuardInvalidConfigReverts() public {
        vm.expectRevert(MusdPegGuard.InvalidConfiguration.selector);
        pegGuard.setPegConfig(3000, 0.99e18, 300);

        vm.expectRevert(MusdPegGuard.InvalidConfiguration.selector);
        pegGuard.setPegConfig(50, 0.70e18, 300);
    }

    function testUnit_13_PegGuardTransferOwnership() public {
        pegGuard.transferOwnership(alice);
        assertEq(pegGuard.owner(), alice);
    }

    // =========================================================================
    // 3. MezoBoostExchange: veBTC × veMEZO Matching & Tiers (Tests 14 - 24)
    // =========================================================================

    function testUnit_14_BoostMultiplierCurveBoundaryConditions() public view {
        assertEq(boostExchange.calculateBoostMultiplier(0, 1000 ether), 10_000, "Zero veBTC => 1.0x");
        assertEq(boostExchange.calculateBoostMultiplier(1 ether, 0), 10_000, "Zero veMEZO => 1.0x");
        assertEq(boostExchange.calculateBoostMultiplier(1 ether, 2_500 ether), 20_000, "25% optimal => 2.0x");
        assertEq(boostExchange.calculateBoostMultiplier(1 ether, 5_000 ether), 30_000, "50% optimal => 3.0x");
        assertEq(boostExchange.calculateBoostMultiplier(1 ether, 7_500 ether), 40_000, "75% optimal => 4.0x");
        assertEq(boostExchange.calculateBoostMultiplier(1 ether, 10_000 ether), 50_000, "100% optimal => 5.0x");
        assertEq(boostExchange.calculateBoostMultiplier(1 ether, 25_000 ether), 50_000, ">100% optimal => capped at 5.0x");
    }

    function testUnit_15_ListVeMezoBoostOffer() public {
        vm.prank(bob);
        uint256 offerId = boostExchange.listVeMezoBoost(12, 20_000 ether, 2500);
        assertEq(offerId, 1);
        assertEq(boostExchange.totalAvailableVeMezoWeight(), 20_000 ether);
    }

    function testUnit_16_ListVeMezoBoostRevertsOnExcessSplitOrZeroWeight() public {
        vm.prank(bob);
        vm.expectRevert(MezoBoostExchange.InvalidAmount.selector);
        boostExchange.listVeMezoBoost(0, 0, 2500);

        vm.prank(bob);
        vm.expectRevert(MezoBoostExchange.InvalidAmount.selector);
        boostExchange.listVeMezoBoost(1, 10_000 ether, 6000);
    }

    function testUnit_17_PairVeBtcMatchesAcrossMultipleOffersToReach5x() public {
        vm.prank(bob);
        boostExchange.listVeMezoBoost(1, 4_000 ether, 2000);
        vm.prank(carol);
        boostExchange.listVeMezoBoost(2, 8_000 ether, 2500);

        // Alice pairs 1.0 BTC (needs 10,000 veMEZO for full 5x)
        vm.prank(alice);
        (uint256 multBps, uint256 pairedVeMezo) = boostExchange.pairVeBtcForBoost{value: 1 ether}(alice, 0, 1 ether);

        assertEq(pairedVeMezo, 10_000 ether);
        assertEq(multBps, 50_000, "Must aggregate across Offer #1 and Offer #2 to hit 5.0x");
        assertEq(boostExchange.totalAvailableVeMezoWeight(), 2_000 ether);
        assertEq(boostExchange.totalLeasedVeMezoWeight(), 10_000 ether);
    }

    function testUnit_18_PartialVeMezoLiquidityYieldsProportionalBoost() public {
        vm.prank(bob);
        boostExchange.listVeMezoBoost(1, 5_000 ether, 2000);

        // Alice pairs 1.0 BTC when only 5,000 veMEZO is in pool -> gets 3.0x (30,000 bps)
        vm.prank(alice);
        (uint256 multBps, uint256 pairedVeMezo) = boostExchange.pairVeBtcForBoost{value: 1 ether}(alice, 0, 1 ether);

        assertEq(pairedVeMezo, 5_000 ether);
        assertEq(multBps, 30_000);
    }

    function testUnit_19_BorrowerRebateTiersNoneBronzeSilverGold() public {
        assertEq(uint256(boostExchange.getBorrowerTier(alice)), uint256(MezoBoostExchange.BorrowerTier.None));
        assertEq(boostExchange.getBorrowerFeeRebateBps(alice), 0);

        vm.startPrank(alice);
        boostExchange.stakeMezoForTier(1_000e18);
        assertEq(uint256(boostExchange.getBorrowerTier(alice)), uint256(MezoBoostExchange.BorrowerTier.Bronze));
        assertEq(boostExchange.getBorrowerFeeRebateBps(alice), 1500); // 15%

        boostExchange.stakeMezoForTier(9_000e18);
        assertEq(uint256(boostExchange.getBorrowerTier(alice)), uint256(MezoBoostExchange.BorrowerTier.Silver));
        assertEq(boostExchange.getBorrowerFeeRebateBps(alice), 3000); // 30%

        boostExchange.stakeMezoForTier(40_000e18);
        assertEq(uint256(boostExchange.getBorrowerTier(alice)), uint256(MezoBoostExchange.BorrowerTier.Gold));
        assertEq(boostExchange.getBorrowerFeeRebateBps(alice), 5000); // 50%
        vm.stopPrank();
    }

    function testUnit_20_UnstakeMezoDowngradesBorrowerTier() public {
        vm.startPrank(alice);
        boostExchange.stakeMezoForTier(50_000e18);
        assertEq(uint256(boostExchange.getBorrowerTier(alice)), uint256(MezoBoostExchange.BorrowerTier.Gold));

        boostExchange.unstakeMezo(45_000e18);
        assertEq(uint256(boostExchange.getBorrowerTier(alice)), uint256(MezoBoostExchange.BorrowerTier.Bronze));

        boostExchange.unstakeMezo(5_000e18);
        assertEq(uint256(boostExchange.getBorrowerTier(alice)), uint256(MezoBoostExchange.BorrowerTier.None));
        vm.stopPrank();
    }

    function testUnit_21_UnstakeExceedingBalanceReverts() public {
        vm.prank(alice);
        vm.expectRevert(MezoBoostExchange.InsufficientUnstakedBalance.selector);
        boostExchange.unstakeMezo(100e18);
    }

    function testUnit_22_RouteGaugeVotesLengthValidation() public {
        address[] memory gauges = new address[](2);
        gauges[0] = MezoAddresses.MAMUSD_MUSD_POOL;
        gauges[1] = MezoAddresses.MUSD_MUSDC_POOL;
        uint256[] memory badWeights = new uint256[](1);
        badWeights[0] = 10_000;

        vm.expectRevert(MezoBoostExchange.ArrayLengthMismatch.selector);
        boostExchange.routeGaugeVotes(1, gauges, badWeights, false);
    }

    function testUnit_23_DistributeBtcGaugeDividendsAndClaim() public {
        vm.prank(bob);
        uint256 offerId = boostExchange.listVeMezoBoost(1, 20_000 ether, 2500);

        boostExchange.distributeGaugeDividends{value: 1 ether}(alice, offerId, 0);

        uint256 aliceBtcBefore = alice.balance;
        vm.prank(alice);
        (, uint256 btcClaimed) = boostExchange.claimUserBoostRewards();

        assertEq(btcClaimed, 0.65 ether);
        assertEq(alice.balance, aliceBtcBefore + 0.65 ether);
    }

    function testUnit_24_SetRewardSplitValidation() public {
        vm.expectRevert(MezoBoostExchange.InvalidAmount.selector);
        boostExchange.setRewardSplit(7000, 2000, 500);

        boostExchange.setRewardSplit(7000, 2000, 1000);
        assertEq(boostExchange.veBtcRewardShareBps(), 7000);
    }

    // =========================================================================
    // 4. MUSDCarryEngine Allocation & Unwind Logic (Tests 25 - 29)
    // =========================================================================

    function testUnit_25_CarryEngineDefaultAllocationWeights() public view {
        assertEq(carryEngine.defaultSpWeightBps(), 5000);
        assertEq(carryEngine.defaultMaMusdWeightBps(), 3500);
        assertEq(carryEngine.defaultStrcWeightBps(), 1500);
    }

    function testUnit_26_CarryEngineUpdateAllocationWeights() public {
        carryEngine.setAllocationWeights(6000, 2500, 1500);
        assertEq(carryEngine.defaultSpWeightBps(), 6000);
        assertEq(carryEngine.defaultMaMusdWeightBps(), 2500);
        assertEq(carryEngine.defaultStrcWeightBps(), 1500);
    }

    function testUnit_27_CarryEngineInvalidWeightsRevert() public {
        vm.expectRevert(MUSDCarryEngine.InvalidWeights.selector);
        carryEngine.setAllocationWeights(5000, 5000, 1000);
    }

    function testUnit_28_CarryEngineUnauthorizedSetWeightsReverts() public {
        vm.prank(alice);
        vm.expectRevert(MUSDCarryEngine.Unauthorized.selector);
        carryEngine.setAllocationWeights(5000, 3000, 2000);
    }

    function testUnit_29_CarryEngineUnwindAuthorizationGuard() public {
        vm.prank(bob);
        vm.expectRevert(MUSDCarryEngine.Unauthorized.selector);
        carryEngine.instantUnwindToMusd(alice, 100e18, 0, bob);
    }

    // =========================================================================
    // 5. AegisTroveVault Controls, Proxies & Guards (Tests 30 - 34)
    // =========================================================================

    function testUnit_30_UserTroveProxyCreationAndMapping() public {
        address proxy1 = aegisVault.getOrCreateUserProxy(alice);
        address proxy2 = aegisVault.getOrCreateUserProxy(alice);
        assertEq(proxy1, proxy2, "Must return deterministic singleton proxy per user");
        assertEq(aegisVault.proxyToOwner(proxy1), alice);

        address bobProxy = aegisVault.getOrCreateUserProxy(bob);
        assertTrue(bobProxy != proxy1, "Different users must receive isolated Trove proxies");
    }

    function testUnit_31_UserTroveProxyAccessControl() public {
        address proxy = aegisVault.getOrCreateUserProxy(alice);
        vm.prank(alice);
        vm.expectRevert(AegisUserTroveProxy.OnlyVault.selector);
        AegisUserTroveProxy(payable(proxy)).executeRepayMusd(100e18, address(0), address(0));
    }

    function testUnit_32_AuthorizeAgentCreditAllowance() public {
        vm.prank(alice);
        aegisVault.authorizeAgentCredit(agent, 2_500e18);
        assertEq(aegisVault.agentCreditAllowance(alice, agent), 2_500e18);
    }

    function testUnit_33_SetRescueParametersValidation() public {
        aegisVault.setRescueParameters(1.40e18, 1.65e18, 1500);
        assertEq(aegisVault.rescueIcrThreshold(), 1.40e18);
        assertEq(aegisVault.targetHealthyIcr(), 1.65e18);
        assertEq(aegisVault.redemptionDangerPercentileBps(), 1500);

        vm.expectRevert(AegisTroveVault.InvalidAmount.selector);
        aegisVault.setRescueParameters(1.05e18, 1.50e18, 1000);
    }

    function testUnit_34_OpenVaultInvalidArgumentsRevert() public {
        vm.prank(alice);
        vm.expectRevert(AegisTroveVault.InvalidAmount.selector);
        aegisVault.openAndActivateVault{value: 0.5 ether}(5_000e18, 0.5 ether, 5000, address(0), address(0));
    }

    // =========================================================================
    // 6. MezoFloatRefiller x402 Invoices & Float Configuration (Tests 35 - 38)
    // =========================================================================

    function testUnit_35_CreateX402InvoiceAndPreventDuplicates() public {
        bytes32 id = keccak256("inv-unit-35");
        floatRefiller.createX402Invoice(id, merchant, 250e18, 8453, "https://agent.mezo.org/x402/resource");

        (
            bytes32 storedId,
            address storedMerchant,
            ,
            uint256 amount,
            uint256 chainId,
            string memory uri,
            bool settled,
            ,
        ) = floatRefiller.invoices(id);

        assertEq(storedId, id);
        assertEq(storedMerchant, merchant);
        assertEq(amount, 250e18);
        assertEq(chainId, 8453);
        assertEq(uri, "https://agent.mezo.org/x402/resource");
        assertFalse(settled);

        vm.expectRevert(abi.encodeWithSelector(MezoFloatRefiller.InvoiceAlreadyExists.selector, id));
        floatRefiller.createX402Invoice(id, merchant, 250e18, 8453, "https://agent.mezo.org/x402/resource");
    }

    function testUnit_36_AuthorizeX402AgentSessionBudget() public {
        vm.prank(alice);
        floatRefiller.authorizeX402Agent(agent, 1_200e18);
        assertEq(floatRefiller.agentSessionBudgets(alice, agent), 1_200e18);
    }

    function testUnit_37_ConfigureFloatAccountValidation() public {
        vm.prank(merchant);
        floatRefiller.configureFloatAccount(merchant, 500e18, 2_000e18, true);

        (, uint256 minThresh, uint256 targetFloat, bool enabled) = floatRefiller.floatAccounts(merchant);
        assertEq(minThresh, 500e18);
        assertEq(targetFloat, 2_000e18);
        assertTrue(enabled);

        vm.prank(merchant);
        vm.expectRevert(MezoFloatRefiller.InvalidAmount.selector);
        floatRefiller.configureFloatAccount(merchant, 3_000e18, 1_000e18, true);
    }

    function testUnit_38_QuoteBtcToMusdAndCrossChainUsdc() public view {
        uint256 musdQuoted = floatRefiller.quoteBtcToMusd(1 ether);
        assertGt(musdQuoted, 10_000e18);

        (uint256 usdcOut6, uint256 rate18) = floatRefiller.quoteCrossChainUsdc(1_000e18);
        assertGt(usdcOut6, 750e6);
        assertGt(rate18, 0.78e18);
    }
}
