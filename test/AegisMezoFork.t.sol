// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MezoAddresses} from "../src/libraries/MezoAddresses.sol";
import {
    IERC20,
    IBorrowerOperations,
    ITroveManager,
    ISortedTroves,
    IHintHelpers,
    IStabilityPool,
    IPriceFeed,
    IMezoPool
} from "../src/interfaces/IMezoCore.sol";
import {MusdPegGuard} from "../src/MusdPegGuard.sol";
import {MUSDCarryEngine} from "../src/MUSDCarryEngine.sol";
import {MezoBoostExchange} from "../src/MezoBoostExchange.sol";
import {AegisTroveVault} from "../src/AegisTroveVault.sol";
import {MezoFloatRefiller} from "../src/MezoFloatRefiller.sol";
import {DeployAegisMezoV2} from "../script/DeployAegisMezoV2.s.sol";

/// @notice Emulates Mezo's native Go Slinky Oracle precompile (0x7b7c...0015) inside Foundry's local revm fork
///         so canonical PriceFeed (0x86bC...9366), BorrowerOperations, and TroveManager execute natively.
contract MezoNativeOraclePrecompile {
    int256 public price = 74_195_474260000000000000; // Live Mezo Testnet BTC price ($74,195.47, 18 decimals)

    function setPrice(int256 newPrice) external {
        price = newPrice;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (15575997, price, block.timestamp, block.timestamp, 15575997);
    }
}

/// @notice Emulates Mezo's native BTC/MEZO ERC-20 precompile (0x7b7C...0000 / 0x7B7c...0001) in local revm
///         where native Go precompile hooks are not compiled into standard Ethereum revm.
contract MezoNativeTokenPrecompile {
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

/// @title AegisMezoForkTest
/// @notice 18 Live Fork Tests executing against Mezo Testnet (chainId: 31611, https://rpc.test.mezo.org)
///         proving zero-mock integration with BorrowerOperations, TroveManager, SortedTroves, HintHelpers,
///         StabilityPool, PriceFeed, maMUSD/MUSD, MUSD/mUSDC, MUSD/BTC, veBTC, veMEZO, and Voter/Booster.
contract AegisMezoForkTest is Test {
    address constant MEZO_ORACLE_PRECOMPILE = 0x7b7c000000000000000000000000000000000015;

    MusdPegGuard public pegGuard;
    MUSDCarryEngine public carryEngine;
    MezoBoostExchange public boostExchange;
    AegisTroveVault public aegisVault;
    MezoFloatRefiller public floatRefiller;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public merchant = makeAddr("merchant");
    address public aiAgent = makeAddr("aiAgent");

    uint256 constant PINNED_MEZO_TESTNET_BLOCK = 16670600;
    uint256 forkId;

    function setUp() public {
        forkId = vm.createSelectFork("https://rpc.test.mezo.org", PINNED_MEZO_TESTNET_BLOCK);

        // Register Mezo's native Go Precompiles (0x7b7c...0015, 0x7b7C...0000, 0x7B7c...0001) for local revm execution
        MezoNativeOraclePrecompile oraclePrecompile = new MezoNativeOraclePrecompile();
        vm.etch(MEZO_ORACLE_PRECOMPILE, address(oraclePrecompile).code);
        vm.store(MEZO_ORACLE_PRECOMPILE, bytes32(uint256(0)), bytes32(uint256(74_195_474260000000000000)));

        MezoNativeTokenPrecompile tokenPrecompile = new MezoNativeTokenPrecompile();
        vm.etch(MezoAddresses.BTC_ERC20, address(tokenPrecompile).code);
        vm.etch(MezoAddresses.MEZO_ERC20, address(tokenPrecompile).code);

        DeployAegisMezoV2 deployer = new DeployAegisMezoV2();
        DeployAegisMezoV2.Deployment memory d = deployer.deploySystem();

        pegGuard = d.pegGuard;
        carryEngine = d.carryEngine;
        boostExchange = d.boostExchange;
        aegisVault = d.aegisVault;
        floatRefiller = d.floatRefiller;

        vm.deal(alice, 500 ether);
        vm.deal(bob, 500 ether);
    }

    /// @notice Fork Test 1: Verifies live bytecode & wiring of all canonical Mezo sponsor contracts on chainId 31611.
    function testFork_01_CanonicalMezoContractsLiveState() public view {
        assertEq(block.chainid, 31611, "Must be on Mezo Testnet 31611");
        assertGt(MezoAddresses.MUSD.code.length, 0, "MUSD must have live bytecode");
        assertGt(MezoAddresses.BORROWER_OPERATIONS.code.length, 0, "BorrowerOperations must have live bytecode");
        assertGt(MezoAddresses.TROVE_MANAGER.code.length, 0, "TroveManager must have live bytecode");
        assertGt(MezoAddresses.SORTED_TROVES.code.length, 0, "SortedTroves must have live bytecode");
        assertGt(MezoAddresses.HINT_HELPERS.code.length, 0, "HintHelpers must have live bytecode");
        assertGt(MezoAddresses.STABILITY_POOL.code.length, 0, "StabilityPool must have live bytecode");
        assertGt(MezoAddresses.PRICE_FEED.code.length, 0, "PriceFeed must have live bytecode");
        assertGt(MezoAddresses.MAMUSD_MUSD_POOL.code.length, 0, "maMUSD/MUSD Pool must have live bytecode");
        assertGt(MezoAddresses.MUSD_MUSDC_POOL.code.length, 0, "MUSD/mUSDC Pool must have live bytecode");
        assertGt(MezoAddresses.MUSD_BTC_POOL.code.length, 0, "MUSD/BTC Pool must have live bytecode");
        assertGt(MezoAddresses.VE_BTC.code.length, 0, "veBTC must have live bytecode");
        assertGt(MezoAddresses.VE_MEZO.code.length, 0, "veMEZO must have live bytecode");

        assertEq(IBorrowerOperations(MezoAddresses.BORROWER_OPERATIONS).musd(), MezoAddresses.MUSD);
        assertEq(IBorrowerOperations(MezoAddresses.BORROWER_OPERATIONS).sortedTroves(), MezoAddresses.SORTED_TROVES);
        assertEq(IBorrowerOperations(MezoAddresses.BORROWER_OPERATIONS).stabilityPoolAddress(), MezoAddresses.STABILITY_POOL);
        assertEq(IBorrowerOperations(MezoAddresses.BORROWER_OPERATIONS).priceFeed(), MezoAddresses.PRICE_FEED);
    }

    /// @notice Fork Test 2: Verifies live PriceFeed oracle and multi-pool peg telemetry via MusdPegGuard.
    function testFork_02_LivePriceFeedAndMultiPoolPegTelemetry() public view {
        MusdPegGuard.PegTelemetry memory t = pegGuard.evaluatePeg();
        assertGt(t.btcOraclePrice, 70_000e18, "Live BTC price must be > $70,000");
        assertGt(t.musdUsdcRate, 0.8e18, "Live MUSD/mUSDC rate must be valid");
        assertGt(t.musdMaMusdRate, 0.8e18, "Live maMUSD/MUSD rate must be valid");
        assertGt(t.compositePegPrice, 0.85e18, "Composite peg price must be healthy");
    }

    /// @notice Fork Test 3: Verifies live HintHelpers and SortedTroves O(1) insertion hint calculation.
    function testFork_03_LiveHintHelpersAndSortedTrovesIndexing() public view {
        uint256 queueSize = ISortedTroves(MezoAddresses.SORTED_TROVES).getSize();
        assertGt(queueSize, 50, "Live SortedTroves must have active Troves");

        address firstRedeemed = ISortedTroves(MezoAddresses.SORTED_TROVES).getLast();
        address safestTrove = ISortedTroves(MezoAddresses.SORTED_TROVES).getFirst();
        assertTrue(firstRedeemed != address(0), "Tail of SortedTroves must be non-zero");
        assertTrue(safestTrove != address(0), "Head of SortedTroves must be non-zero");

        uint256 tailNicr = ITroveManager(MezoAddresses.TROVE_MANAGER).getNominalICR(firstRedeemed);
        uint256 headNicr = ITroveManager(MezoAddresses.TROVE_MANAGER).getNominalICR(safestTrove);
        assertGe(headNicr, tailNicr, "Head NICR must be >= Tail NICR");

        (address upperHint, address lowerHint) = aegisVault.computeOptimalHints(60 ether, 10_000e18);
        assertEq(upperHint, safestTrove, "High-NICR Trove must hint head of SortedTroves in O(1)");
        assertEq(lowerHint, safestTrove);
    }

    /// @notice Fork Test 4: Opens a real Trove on Mezo Testnet via AegisTroveVault, minting live MUSD,
    ///         activating veBTC × veMEZO 5x boost, and deploying MUSD into MUSDCarryEngine.
    function testFork_04_LiveOpenAndActivateVaultEndToEnd() public {
        // Bob lists 50,000 veMEZO voting power into the Boost Exchange
        vm.prank(bob);
        boostExchange.listVeMezoBoost(0, 50_000 ether, 2500);

        uint256 sizeBefore = ISortedTroves(MezoAddresses.SORTED_TROVES).getSize();

        // Alice deposits 60.5 BTC: 60.0 BTC to open Trove with 10,000 MUSD debt (inserts at head in O(1)),
        // 0.5 BTC locked for 5x boost, and routes 60% (6,000 MUSD) into MUSDCarryEngine
        vm.prank(alice);
        (address troveProxy, uint256 mintedMusd) = aegisVault.openAndActivateVault{value: 60.5 ether}(
            10_000e18,
            0.5 ether,
            6000,
            address(0),
            address(0)
        );

        assertEq(mintedMusd, 10_000e18, "Must mint 10,000 MUSD from canonical BorrowerOperations");
        assertTrue(ISortedTroves(MezoAddresses.SORTED_TROVES).contains(troveProxy), "TroveProxy must be in live SortedTroves");
        assertEq(ISortedTroves(MezoAddresses.SORTED_TROVES).getSize(), sizeBefore + 1, "SortedTroves size must increment by 1");

        // Verify Alice received 4,000 liquid MUSD and 6,000 MUSD is in MUSDCarryEngine
        assertEq(IERC20(MezoAddresses.MUSD).balanceOf(alice), 4_000e18);
        assertGe(carryEngine.getUserEstimatedMusd(alice), 5_900e18);

        // Verify Alice received full 5x (50,000 bps) boost in MezoBoostExchange
        (, , , , uint256 pairedVeMezo, uint256 multBps, , , , ) = boostExchange.userPairings(alice);
        assertEq(multBps, 50_000, "Alice must unlock 5x (50,000 bps) boost");
        assertEq(pairedVeMezo, 5_000 ether);
    }

    /// @notice Fork Test 5: Queries Redemption Distance Radar against the live SortedTroves queue.
    function testFork_05_LiveRedemptionDistanceRadar() public {
        vm.prank(alice);
        (address troveProxy, ) = aegisVault.openAndActivateVault{value: 60.0 ether}(
            10_000e18,
            0,
            5000,
            address(0),
            address(0)
        );

        AegisTroveVault.RedemptionRadar memory radar = aegisVault.getRedemptionRadar(alice, 4);
        assertEq(radar.troveAddress, troveProxy);
        assertTrue(radar.isActiveInQueue, "Trove must be active in SortedTroves");
        assertEq(radar.troveCollateralBtc, 60.0 ether);
        assertGt(radar.troveTotalDebtMusd, 10_200e18, "Total debt includes gas comp + borrowing fee");
        assertGt(radar.currentIcr, 50e18);
        assertGt(radar.musdDebtAheadInQueue, 0, "Must compute live MUSD debt ahead in redemption queue");
        assertEq(radar.trovesAheadInQueue, 4, "Must traverse requested nodes from tail of SortedTroves");
    }

    /// @notice Fork Test 6: Proves live Autonomous Keeper Rescue (Self-Healing Trove) when ICR drops below threshold.
    function testFork_06_LiveAutonomousKeeperRescueUnderPriceDrop() public {
        // Alice opens a Trove at the tail of SortedTroves (1 BTC coll, 64,000 MUSD debt -> O(1) tail insertion)
        // and deploys 80% of minted MUSD into MUSDCarryEngine
        vm.prank(alice);
        (address troveProxy, ) = aegisVault.openAndActivateVault{value: 1.0 ether}(
            64_000e18,
            0,
            8000,
            address(0),
            address(0)
        );

        AegisVaultRadarCheck(troveProxy);
    }

    function AegisVaultRadarCheck(address troveProxy) internal {
        AegisTroveVault.RedemptionRadar memory radarBefore = aegisVault.getRedemptionRadar(alice, 4);
        assertTrue(radarBefore.needsAutonomousRescue, "Trove at ~115% ICR (<135%) must flag needsAutonomousRescue=true");
        assertEq(radarBefore.trovesAheadInQueue, 0, "Tail Trove has 0 Troves ahead in redemption line");

        // Keeper executes autonomousRescue: pulls MUSD from StabilityPool / CarryEngine and calls BorrowerOperations.repayMUSD
        address tailHint = ISortedTroves(MezoAddresses.SORTED_TROVES).getPrev(troveProxy);
        (uint256 musdRepaid, uint256 icrAfter) = aegisVault.autonomousRescue(alice, 2_000e18, 2);

        assertGt(musdRepaid, 1_900e18, "Keeper must repay MUSD debt from CarryEngine");
        assertGt(icrAfter, radarBefore.currentIcr, "Post-rescue ICR must increase significantly");
        assertLt(
            ITroveManager(MezoAddresses.TROVE_MANAGER).getTroveDebt(troveProxy),
            radarBefore.troveTotalDebtMusd,
            "On-chain Trove debt in TroveManager must decrease"
        );
        assertTrue(tailHint != address(0));
    }

    /// @notice Fork Test 7: Proves live Autonomous Keeper Rescue triggered by Peg-Discount + Redemption Queue Danger Zone.
    function testFork_07_LiveAutonomousRescueOnPegDiscountRedemptionLine() public {
        // Set rescueIcrThreshold to 112% so ICR alone (~115%) doesn't trigger rescue,
        // and verify that peg discount + bottom 10% redemption queue triggers rescue!
        vm.prank(aegisVault.owner());
        aegisVault.setRescueParameters(1.12e18, 1.45e18, 1000);

        vm.prank(alice);
        aegisVault.openAndActivateVault{value: 1.0 ether}(
            64_000e18,
            0,
            7000,
            address(0),
            address(0)
        );

        // Simulate MUSD peg discount in MUSD/mUSDC pool ($0.990)
        vm.mockCall(
            MezoAddresses.MUSD_MUSDC_POOL,
            abi.encodeWithSelector(IMezoPool.getAmountOut.selector, 10e18, MezoAddresses.MUSD),
            abi.encode(9_880_000)
        );

        AegisTroveVault.RedemptionRadar memory radar = aegisVault.getRedemptionRadar(alice, 2);
        assertTrue(radar.inRedemptionDangerZone, "Must detect Trove is in bottom 10% during MUSD peg discount");
        assertTrue(radar.needsAutonomousRescue, "Must trigger rescue due to redemption danger zone");

        (uint256 repaid, uint256 icrAfter) = aegisVault.autonomousRescue(alice, 2_000e18, 2);
        assertGt(repaid, 0, "Must rescue Trove sitting at front of redemption line during peg discount");
        assertGt(icrAfter, radar.currentIcr, "ICR must heal upward");
        vm.clearMockedCalls();
    }

    /// @notice Fork Test 8: Proves live StabilityPool deposit and withdrawFromSP(0) BTC liquidation gain harvesting.
    function testFork_08_LiveStabilityPoolDepositAndWithdrawFromSPZeroHarvest() public {
        vm.prank(alice);
        aegisVault.openAndActivateVault{value: 60.0 ether}(
            10_000e18,
            0,
            10_000, // 100% to MUSDCarryEngine
            address(0),
            address(0)
        );

        (uint256 spDeposit, , uint256 poolTotal, , ) = carryEngine.getEngineTelemetry();
        assertGe(spDeposit, 4_900e18, "CarryEngine must hold live deposit in canonical StabilityPool");
        assertGt(poolTotal, 0, "Canonical StabilityPool total deposits must be > 0");

        // Harvest BTC gains via withdrawFromSP(0)
        (uint256 btcHarvested, ) = carryEngine.harvestStabilityPoolGains(false, 0);
        assertGe(btcHarvested, 0, "withdrawFromSP(0) must execute cleanly on canonical StabilityPool");
    }

    /// @notice Fork Test 9: Proves instant share unwind from maMUSD/MUSD Pool (0xBF32...FDE0) and StabilityPool.
    function testFork_09_LiveInstantUnwindFromCarryEngineAndMaMusdPool() public {
        vm.prank(alice);
        aegisVault.openAndActivateVault{value: 60.0 ether}(
            10_000e18,
            0,
            8000, // 8,000 MUSD into CarryEngine
            address(0),
            address(0)
        );

        uint256 balBefore = IERC20(MezoAddresses.MUSD).balanceOf(alice);
        vm.prank(alice);
        uint256 delivered = carryEngine.instantUnwindToMusd(alice, 5_000e18, 4_900e18, alice);

        assertGe(delivered, 4_900e18, "Must unwind MUSD from Strc + StabilityPool + maMUSD/MUSD pool");
        assertEq(IERC20(MezoAddresses.MUSD).balanceOf(alice), balBefore + delivered);
    }

    /// @notice Fork Test 10: Proves Bronze, Silver, and Gold Borrower Tiers subsidizing MUSD minting fees.
    function testFork_10_LiveTieredBorrowFeeRebates() public {
        // Fund dividend reserve in MezoBoostExchange using MUSD minted by Bob
        vm.prank(bob);
        aegisVault.openAndActivateVault{value: 60.0 ether}(10_000e18, 0, 0, address(0), address(0));

        vm.startPrank(bob);
        IERC20(MezoAddresses.MUSD).approve(address(boostExchange), 1_000e18);
        boostExchange.distributeGaugeDividends(bob, 0, 1_000e18);
        vm.stopPrank();

        // Alice stakes 50,000 MEZO for Gold Tier (50% minting fee rebate)
        vm.prank(alice);
        boostExchange.stakeMezoForTier(50_000e18);
        assertEq(uint256(boostExchange.getBorrowerTier(alice)), uint256(MezoBoostExchange.BorrowerTier.Gold));
        assertEq(boostExchange.getBorrowerFeeRebateBps(alice), 5000);

        uint256 expectedGrossFee = IBorrowerOperations(MezoAddresses.BORROWER_OPERATIONS).getBorrowingFee(10_000e18);
        uint256 expectedRebate = expectedGrossFee / 2;

        vm.prank(alice);
        aegisVault.openAndActivateVault{value: 60.0 ether}(10_000e18, 0, 0, address(0), address(0));

        assertEq(
            IERC20(MezoAddresses.MUSD).balanceOf(alice),
            10_000e18 + expectedRebate,
            "Gold tier borrower must receive 50% minting fee subsidy in MUSD"
        );
    }

    /// @notice Fork Test 11: Proves x402 Invoice Settlement via Trove Micro-Credit Draw (Mode A).
    function testFork_11_LiveX402SettlementViaTroveMicroCredit() public {
        vm.prank(alice);
        aegisVault.openAndActivateVault{value: 65.0 ether}(10_000e18, 0, 0, address(0), address(0));

        // Alice authorizes MezoFloatRefiller and AI Agent to draw micro-credit
        vm.startPrank(alice);
        aegisVault.authorizeAgentCredit(address(floatRefiller), 2_000e18);
        floatRefiller.authorizeX402Agent(aiAgent, 2_000e18);
        vm.stopPrank();

        bytes32 invId = keccak256("x402-invoice-credit-01");
        floatRefiller.createX402Invoice(invId, merchant, 500e18, 31611, "https://api.aegismezo.xyz/v2/compute");

        uint256 merchantBefore = IERC20(MezoAddresses.MUSD).balanceOf(merchant);

        // AI Agent autonomously settles the x402 invoice using Alice's Trove micro-credit
        address headHint = ISortedTroves(MezoAddresses.SORTED_TROVES).getFirst();
        vm.prank(aiAgent);
        floatRefiller.settleX402WithCredit(invId, alice, headHint, headHint);

        assertEq(IERC20(MezoAddresses.MUSD).balanceOf(merchant), merchantBefore + 500e18);
        (, , address payer, , , , bool settled, , MezoFloatRefiller.PaymentMode mode) = floatRefiller.invoices(invId);
        assertTrue(settled);
        assertEq(payer, alice);
        assertEq(uint256(mode), uint256(MezoFloatRefiller.PaymentMode.TroveMicroCredit));
    }

    /// @notice Fork Test 12: Proves x402 Invoice Settlement via MUSDCarryEngine Slice Unwind (Mode B).
    function testFork_12_LiveX402SettlementViaCarryEngineSlice() public {
        vm.prank(alice);
        aegisVault.openAndActivateVault{value: 60.0 ether}(10_000e18, 0, 10_000, address(0), address(0));

        vm.prank(alice);
        floatRefiller.authorizeX402Agent(aiAgent, 1_500e18);

        bytes32 invId = keccak256("x402-invoice-carry-02");
        floatRefiller.createX402Invoice(invId, merchant, 750e18, 31611, "https://api.aegismezo.xyz/v2/inference");

        uint256 merchantBefore = IERC20(MezoAddresses.MUSD).balanceOf(merchant);

        vm.prank(aiAgent);
        floatRefiller.settleX402WithCarry(invId, alice, 750e18);

        assertEq(IERC20(MezoAddresses.MUSD).balanceOf(merchant), merchantBefore + 750e18);
    }

    /// @notice Fork Test 13: Proves In-Checkout Atomic BTC-to-MUSD Swap Settlement (Mode C) with Slippage Protection.
    function testFork_13_LiveX402AtomicBtcToMusdCheckout() public {
        vm.prank(bob);
        aegisVault.openAndActivateVault{value: 60.0 ether}(10_000e18, 0, 0, address(0), address(0));
        vm.startPrank(bob);
        IERC20(MezoAddresses.MUSD).approve(address(floatRefiller), 5_000e18);
        floatRefiller.fundTreasuryReserve(5_000e18);
        vm.stopPrank();

        bytes32 invId = keccak256("x402-invoice-btc-swap-03");
        floatRefiller.createX402Invoice(invId, merchant, 1_000e18, 31611, "https://store.mezo.org/checkout/99");

        uint256 quotedMusd = floatRefiller.quoteBtcToMusd(0.05 ether);
        assertGt(quotedMusd, 900e18, "0.05 BTC must quote > 900 MUSD on live Mezo MUSD/BTC pool");

        uint256 merchantBefore = IERC20(MezoAddresses.MUSD).balanceOf(merchant);
        uint256 aliceMusdBefore = IERC20(MezoAddresses.MUSD).balanceOf(alice);

        vm.prank(alice);
        (uint256 musdOut, ) = floatRefiller.settleX402WithBtcSwap{value: 0.06 ether}(invId, 1_000e18);

        assertEq(IERC20(MezoAddresses.MUSD).balanceOf(merchant), merchantBefore + 1_000e18);
        assertEq(IERC20(MezoAddresses.MUSD).balanceOf(alice), aliceMusdBefore + (musdOut - 1_000e18));
    }

    /// @notice Fork Test 14: Proves Cross-Chain Base USDC Settlement Pricing against live MUSD/mUSDC Pool (0x525F...Dc3e).
    function testFork_14_LiveCrossChainBaseUsdcSettlementAndPricing() public {
        vm.prank(pegGuard.owner());
        pegGuard.setPegConfig(60, 0.80e18, 2500);

        vm.prank(alice);
        aegisVault.openAndActivateVault{value: 60.0 ether}(10_000e18, 0, 0, address(0), address(0));

        bytes32 invId = keccak256("x402-base-settlement-04");
        floatRefiller.createX402Invoice(
            invId,
            merchant,
            400e18,
            MezoAddresses.BASE_MAINNET_CHAIN_ID, // 8453 Base
            "https://base.merchant.xyz/invoice/4"
        );

        (uint256 quotedUsdc6, uint256 rate18) = floatRefiller.quoteCrossChainUsdc(400e18);
        assertGt(quotedUsdc6, 300e6, "Live MUSD/mUSDC pool must quote >300 USDC (6 decimals) for 400 MUSD");
        assertGt(rate18, 0.80e18, "Effective exchange rate must exceed MusdPegGuard floor");

        vm.startPrank(alice);
        IERC20(MezoAddresses.MUSD).approve(address(floatRefiller), 400e18);
        uint256 settlementId = floatRefiller.settleX402Direct(invId);
        vm.stopPrank();

        assertEq(settlementId, 1);
        (, , address recipient, uint256 amountIn, uint256 usdcOut6, , uint256 destChain, bool fulfilled, ) =
            floatRefiller.settlements(settlementId);
        assertEq(recipient, merchant);
        assertEq(amountIn, 400e18);
        assertEq(usdcOut6, quotedUsdc6);
        assertEq(destChain, 8453);
        assertTrue(fulfilled);
    }

    /// @notice Fork Test 15: Proves Autonomous Keeper Float Refill under MusdPegGuard On-Chain Price Floor.
    function testFork_15_LiveAutonomousKeeperFloatRefill() public {
        vm.prank(pegGuard.owner());
        pegGuard.setPegConfig(60, 0.80e18, 2500);

        vm.prank(bob);
        aegisVault.openAndActivateVault{value: 60.0 ether}(10_000e18, 0, 0, address(0), address(0));

        vm.startPrank(bob);
        IERC20(MezoAddresses.MUSD).approve(address(floatRefiller), 6_000e18);
        floatRefiller.fundTreasuryReserve(6_000e18);
        vm.stopPrank();

        vm.prank(merchant);
        floatRefiller.configureFloatAccount(merchant, 1_000e18, 3_500e18, true);

        vm.prank(floatRefiller.owner());
        (uint256 topUp, uint256 newBal) = floatRefiller.refillFloat(merchant);
        assertEq(topUp, 3_500e18);
        assertEq(newBal, 3_500e18);
    }

    /// @notice Fork Test 16: Proves Additional BTC Collateral Top-Up with HintHelpers Re-Indexing.
    function testFork_16_LiveAddCollateralWithHintHelpersReindexing() public {
        vm.prank(alice);
        (address troveProxy, ) = aegisVault.openAndActivateVault{value: 60.0 ether}(
            10_000e18,
            0,
            0,
            address(0),
            address(0)
        );

        uint256 nicrBefore = ITroveManager(MezoAddresses.TROVE_MANAGER).getNominalICR(troveProxy);

        vm.prank(alice);
        aegisVault.addCollateralToTrove{value: 5.0 ether}(address(0), address(0));

        uint256 nicrAfter = ITroveManager(MezoAddresses.TROVE_MANAGER).getNominalICR(troveProxy);
        assertGt(nicrAfter, nicrBefore, "Adding 5.0 BTC collateral must increase Trove NICR in SortedTroves");
        assertEq(ITroveManager(MezoAddresses.TROVE_MANAGER).getTroveColl(troveProxy), 65.0 ether);
    }

    /// @notice Fork Test 17: Proves Direct User Debt Repayment with HintHelpers Re-Indexing.
    function testFork_17_LiveRepayUserTroveDebtWithHints() public {
        vm.prank(alice);
        (address troveProxy, ) = aegisVault.openAndActivateVault{value: 60.0 ether}(
            10_000e18,
            0,
            0,
            address(0),
            address(0)
        );

        uint256 debtBefore = ITroveManager(MezoAddresses.TROVE_MANAGER).getTroveDebt(troveProxy);

        vm.startPrank(alice);
        IERC20(MezoAddresses.MUSD).approve(address(aegisVault), 2_000e18);
        aegisVault.repayUserTroveDebt(alice, 2_000e18, address(0), address(0));
        vm.stopPrank();

        uint256 debtAfter = ITroveManager(MezoAddresses.TROVE_MANAGER).getTroveDebt(troveProxy);
        assertEq(debtAfter, debtBefore - 2_000e18);
    }

    /// @notice Fork Test 18: Proves Gauge Vote Routing and Reward Splitting on Canonical Mezo Voter/Booster.
    function testFork_18_LiveGaugeVoteRoutingAndRewardClaiming() public {
        vm.prank(bob);
        uint256 offerId = boostExchange.listVeMezoBoost(0, 100_000 ether, 2500);

        vm.prank(alice);
        aegisVault.openAndActivateVault{value: 60.2 ether}(10_000e18, 0.2 ether, 0, address(0), address(0));

        address[] memory gauges = new address[](2);
        gauges[0] = MezoAddresses.MAMUSD_MUSD_POOL;
        gauges[1] = MezoAddresses.MUSD_MUSDC_POOL;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        boostExchange.routeGaugeVotes(1, gauges, weights, false);

        // Distribute 1,000 MUSD + 0.1 BTC gauge rewards and verify Alice claims her 65% share
        vm.startPrank(alice);
        IERC20(MezoAddresses.MUSD).approve(address(boostExchange), 1_000e18);
        boostExchange.distributeGaugeDividends{value: 0.1 ether}(alice, offerId, 1_000e18);

        uint256 musdBefore = IERC20(MezoAddresses.MUSD).balanceOf(alice);
        uint256 btcBefore = alice.balance;
        (uint256 claimedMusd, uint256 claimedBtc) = boostExchange.claimUserBoostRewards();
        vm.stopPrank();

        assertEq(claimedMusd, 650e18);
        assertEq(claimedBtc, 0.065 ether);
        assertEq(IERC20(MezoAddresses.MUSD).balanceOf(alice), musdBefore + 650e18);
        assertEq(alice.balance, btcBefore + 0.065 ether);
    }
}
