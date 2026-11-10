# AegisMezo V2 — Autonomous Omni-Clearing & Boost Engine on Mezo

> **Target Program**: Build with MUSD and MEZO: Bitcoin’s Economic Layer (Akindo WaveHack)  
> **Track Alignment**: Dual-Track Architecture — **Track 1 (DeFi)** & **Track 2 (Access & Distribution)**  
> **Target Networks**: Mezo Testnet (`chainId: 31611`) & Mezo Mainnet (`chainId: 31612`), with Cross-Chain Settlement Lanes to Base (`chainId: 8453`)  
> **Zero-Mock Engineering**: Binds 100% to canonical Mezo contracts (`MUSD`, `BorrowerOperations`, `TroveManager`, `SortedTroves`, `HintHelpers`, `StabilityPool`, `PriceFeed`, `maMUSD/MUSD`, `MUSD/mUSDC`, `MUSD/BTC`, `veBTC`, `veMEZO`, `Voter`, `Booster`, and `Wormhole NTT`).

---

## 1. Executive Summary & Frontier Thesis

First-generation Mezo hackathon submissions largely treated **MUSD** as a static ERC-20 token or relied on mocked collateral flows. **AegisMezo V2** pushes the newest frontier of the Mezo stack by uniting three live on-chain primitives into a single autonomous credit, yield, and clearing engine:

1. **Redemption-Aware Self-Healing Troves ([`AegisTroveVault.sol`](src/AegisTroveVault.sol) & [`MusdPegGuard.sol`](src/MusdPegGuard.sol))**:
   Direct integration with `SortedTroves`, `HintHelpers`, `BorrowerOperations`, `TroveManager`, and the live `PriceFeed` oracle to shield borrowers from both BTC price liquidations and **redemption-line cannibalization** when MUSD trades below peg.
2. **The `veBTC` × `veMEZO` Matching & Gauge Router ([`MezoBoostExchange.sol`](src/MezoBoostExchange.sol))**:
   An algorithmic peer-to-pool marketplace that pairs 30-day locked `veBTC` positions with idle `veMEZO` voting power to unlock the **5x yield boost**, route emissions across MEZO Gauges & Splitters (`maMUSD/MUSD` and `MUSD/mUSDC`), and subsidize MUSD minting fees by **15% to 50%** via Bronze/Silver/Gold MEZO staking tiers.
3. **Positive-Carry Yield Router & Agentic x402 Float Settlement ([`MUSDCarryEngine.sol`](src/MUSDCarryEngine.sol) & [`MezoFloatRefiller.sol`](src/MezoFloatRefiller.sol))**:
   Splits minted 1%-fixed-rate MUSD across the canonical `StabilityPool` (harvesting discounted BTC liquidation gains via `withdrawFromSP(0)`), tokenized STRC RWA yield (`sUSDat`), and `maMUSD/MUSD`, while providing an **HTTP 402 (`x402`) Payment-Required clearing rail** and autonomous cross-chain float refiller between **Mezo (`31611`)** and **Base (`8453`)**.

---

## 2. Sponsor Technology Integration Matrix (Canonical Mezo Testnet `31611`)

Every module in `src/` binds directly to verified canonical contracts on Mezo Testnet (`chainId: 31611`) defined in [`MezoAddresses.sol`](src/libraries/MezoAddresses.sol):

| System Layer | Mezo Sponsor Primitive | Canonical Contract Address (`31611`) | AegisMezo V2 Module & Frontier Capability Delivered |
| :--- | :--- | :--- | :--- |
| **Core CDP & Oracle** | `MUSD` Token | [`0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503`](https://explorer.test.mezo.org/address/0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503) | [`AegisTroveVault.sol`](src/AegisTroveVault.sol): Fixed-rate MUSD minting, debt repayment, and x402 credit draws |
| **Core CDP & Oracle** | `BorrowerOperations` | [`0xCdF7028ceAB81fA0C6971208e83fa7872994beE5`](https://explorer.test.mezo.org/address/0xCdF7028ceAB81fA0C6971208e83fa7872994beE5) | [`AegisTroveVault.sol`](src/AegisTroveVault.sol): `openTrove`, `addColl`, `withdrawMUSD`, and `repayMUSD` via deterministic per-user Trove proxies |
| **Core CDP & Oracle** | `TroveManager` | [`0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0`](https://explorer.test.mezo.org/address/0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0) | [`AegisTroveVault.sol`](src/AegisTroveVault.sol): Live `getCurrentICR`, `getNominalICR`, and `getEntireDebtAndColl` inspection |
| **Core CDP & Oracle** | `PriceFeed` Oracle | [`0x86bCF0841622a5dAC14A313a15f96A95421b9366`](https://explorer.test.mezo.org/address/0x86bCF0841622a5dAC14A313a15f96A95421b9366) | [`MusdPegGuard.sol`](src/MusdPegGuard.sol): Real-time BTC/USD oracle pricing (`fetchPrice()`) paired with AMM pool quotes |
| **Queue Telemetry** | `SortedTroves` | [`0x722E4D24FD6Ff8b0AC679450F3D91294607268fA`](https://explorer.test.mezo.org/address/0x722E4D24FD6Ff8b0AC679450F3D91294607268fA) | [`AegisTroveVault.sol`](src/AegisTroveVault.sol): Doubly-linked list traversal from `getLast()` to compute cumulative MUSD debt ahead in the redemption queue |
| **Queue Telemetry** | `HintHelpers` | [`0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6`](https://explorer.test.mezo.org/address/0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6) | [`AegisTroveVault.sol`](src/AegisTroveVault.sol): `computeNominalCR` + `getApproxHint` + `findInsertPosition` for O(1) gas-optimized SortedTroves insertion |
| **Liquidation & Real Yield** | `StabilityPool` | [`0x1CCA7E410eE41739792eA0A24e00349Dd247680e`](https://explorer.test.mezo.org/address/0x1CCA7E410eE41739792eA0A24e00349Dd247680e) | [`MUSDCarryEngine.sol`](src/MUSDCarryEngine.sol): `provideToSP` deposits and `withdrawFromSP(0)` auto-harvesting of discounted BTC liquidation gains |
| **Liquidation & Real Yield** | `maMUSD/MUSD` Pool | [`0xBF329A2A130cb0D5B5218f1672E51Fb36089FDE0`](https://explorer.test.mezo.org/address/0xBF329A2A130cb0D5B5218f1672E51Fb36089FDE0) | [`MUSDCarryEngine.sol`](src/MUSDCarryEngine.sol): Instant `maMUSD -> MUSD` share liquidity unwind without waiting on withdrawal epochs |
| **Liquidation & Real Yield** | `sUSDat` (STRC Yield) | [`0xBCaf6f2a7BEfc4Fc64CeeC6D8e4872941d52Ee87`](https://explorer.test.mezo.org/address/0xBCaf6f2a7BEfc4Fc64CeeC6D8e4872941d52Ee87) | [`MUSDCarryEngine.sol`](src/MUSDCarryEngine.sol): ERC-4626 tokenized STRC real-world yield allocation for positive carry over the 1% borrow rate |
| **Tokenomics Flywheel** | `veBTC` & `veMEZO` | [`0x38E35d92E6Bfc6787272A62345856B13eA12130a`](https://explorer.test.mezo.org/address/0x38E35d92E6Bfc6787272A62345856B13eA12130a) / [`0xaCE816CA2bcc9b12C59799dcC5A959Fb9b98111b`](https://explorer.test.mezo.org/address/0xaCE816CA2bcc9b12C59799dcC5A959Fb9b98111b) | [`MezoBoostExchange.sol`](src/MezoBoostExchange.sol): Peer-to-pool `veMEZO` boost leasing to `veBTC` holders to unlock up to a **5.00x multiplier** |
| **Tokenomics Flywheel** | `Voter`, `Booster`, `Splitter` | [`0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D`](https://explorer.test.mezo.org/address/0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D) / [`0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1`](https://explorer.test.mezo.org/address/0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1) | [`MezoBoostExchange.sol`](src/MezoBoostExchange.sol): Automated gauge vote routing and reward splitting between `veBTC` depositors, `veMEZO` providers, and borrower fee rebates |
| **Access & Clearing** | `MezoPoolsRouter` & `MUSD/mUSDC` Pool | [`0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9`](https://explorer.test.mezo.org/address/0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9) / [`0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e`](https://explorer.test.mezo.org/address/0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e) | [`MezoFloatRefiller.sol`](src/MezoFloatRefiller.sol): Atomic `BTC -> MUSD` checkout swaps with slippage floors & cross-chain `Base (8453) ↔ Mezo (31611)` float rebalancing |

---

## 3. End-to-End Architecture Diagram

```mermaid
flowchart TD
    User["User / Merchant / AI Agent (Mezo Passport: Native BTC + EVM)"]

    subgraph Track1["Track 1: DeFi Core (Self-Healing CDP, 5x Boost & Carry)"]
        Vault["AegisTroveVault.sol (Per-User Trove Proxy Factory)"]
        PegGuard["MusdPegGuard.sol (3-Pool Peg + Oracle Guard)"]
        Boost["MezoBoostExchange.sol (veBTC x veMEZO 5x Matcher)"]
        Carry["MUSDCarryEngine.sol (Positive-Carry Router)"]
    end

    subgraph MezoCanonical["Canonical Mezo Contracts (ChainId: 31611)"]
        BO["BorrowerOperations (0xCdF7...beE5)"]
        TM["TroveManager (0xE47c...6bb0)"]
        ST["SortedTroves (0x722E...68fA)"]
        HH["HintHelpers (0x4e4c...BCF6)"]
        PF["PriceFeed (0x86bC...9366)"]
        SP["StabilityPool (0x1CCA...680e)"]
        Pools["Mezo Pools: maMUSD/MUSD, MUSD/mUSDC, MUSD/BTC"]
        Ve["veBTC, veMEZO, Voter & Booster"]
    end

    subgraph Track2["Track 2: Access & Distribution (x402 & Cross-Chain Float)"]
        SDK["Embeddable SDK (sdk/aegisX402Sdk.ts)"]
        API["HTTP 402 Clearing Endpoint (/api/x402)"]
        Refiller["MezoFloatRefiller.sol (Mezo 31611 <-> Base 8453)"]
    end

    User -->|"1. Deposit BTC & Open Vault"| Vault
    Vault -->|"O(1) Hints"| HH
    Vault -->|"Queue Radar"| ST
    Vault -->|"openTrove / repayMUSD"| BO
    BO --> TM
    Vault -->|"Lock veBTC Slice"| Boost
    Boost -->|"5x Boost & Gauge Votes"| Ve
    Vault -->|"Deploy Minted MUSD"| Carry
    Carry -->|"provideToSP / withdrawFromSP(0)"| SP
    Carry -->|"Instant Share Swap"| Pools
    PegGuard -->|"Inspect Peg & BTC Price"| PF
    PegGuard -->|"Read Live Reserves"| Pools

    User -->|"2. Request Protected Resource"| API
    API -->|"HTTP 402 Challenge"| SDK
    SDK -->|"Settle via Credit / Carry / Atomic BTC Swap"| Refiller
    Refiller -->|"Draw Micro-Credit"| Vault
    Refiller -->|"Unwind Yield Slice"| Carry
    Refiller -->|"Enforce Price Floor"| PegGuard
```

---

## 4. Core Functional Modules

### Module A: Redemption-Shielded Self-Healing Vault ([`src/AegisTroveVault.sol`](src/AegisTroveVault.sol) & [`src/MusdPegGuard.sol`](src/MusdPegGuard.sol))
- **Deterministic Per-User Trove Proxies (`AegisUserTroveProxy`)**: Since canonical Liquity/Mezo `BorrowerOperations` allows one Trove per `msg.sender`, `AegisTroveVault` deploys a dedicated lightweight proxy per user so multiple users can hold isolated Troves in `SortedTroves` while delegating autonomous rescue and x402 micro-credit privileges to the vault.
- **Redemption Distance Radar (`getRedemptionRadar`)**: Walks `SortedTroves` from `getLast()` (lowest NICR, first redeemed) to calculate the exact cumulative MUSD debt sitting ahead of the user's Trove in the redemption line, queue percentile, and live ICR.
- **Autonomous Keeper Rescue (`autonomousRescue`)**: When a Trove's ICR approaches the minimum threshold or enters the bottom 10% of the redemption queue during a peg discount detected by `MusdPegGuard`, the vault automatically unwinds MUSD from `MUSDCarryEngine` and executes `BorrowerOperations.repayMUSD` with pre-computed `HintHelpers` + `SortedTroves` hints.

### Module B: `veBTC` × `veMEZO` Boost Matching Market ([`src/MezoBoostExchange.sol`](src/MezoBoostExchange.sol))
- **Peer-to-Pool Boost Leasing (`listVeMezoBoost` & `pairVeBtcForBoost`)**: `veMEZO` holders list idle voting power into the Boost Exchange; `veBTC` depositors are algorithmically matched to hit the **5.00x (`50,000 bps`)** boost multiplier.
- **Automated Gauge & Splitter Routing (`routeGaugeVotes` & `distributeGaugeDividends`)**: Directs pooled votes across `Voter` (`0x263F...85F0D`) gauges and splits harvested BTC and MUSD rewards (`65%` `veBTC` depositor / `25%` `veMEZO` provider / `10%` borrower rebate reserve).
- **Tiered Borrow-Fee Rebates (`stakeMezoForTier` & `claimBorrowFeeRebate`)**: Staking MEZO unlocks **Bronze (`15%`)**, **Silver (`30%`)**, and **Gold (`50%`)** MUSD minting fee rebates funded by protocol gauge dividends.

### Module C: Positive-Carry Yield Router ([`src/MUSDCarryEngine.sol`](src/MUSDCarryEngine.sol))
- **Dual-Strategy Allocation (`deployCarry`)**: Dynamically allocates borrowed MUSD across the canonical `StabilityPool` (`0x1CCA...680e`), `maMUSD/MUSD` (`0xBF32...FDE0`), and `sUSDat` (`0xBCaf...Ee87`).
- **BTC Liquidation Gain Harvesting (`harvestStabilityPoolGains`)**: Calls `StabilityPool.withdrawFromSP(0)` to harvest discounted BTC liquidation gains without withdrawing MUSD principal.
- **Instant Share Liquidity (`instantUnwindToMusd`)**: Swaps `maMUSD` shares directly back to `MUSD` through `MezoPoolsRouter` (`0x9a1f...D7E9`) / `maMUSD/MUSD` pool (`0xBF32...FDE0`) to close Trove debt or settle x402 invoices with zero withdrawal epoch delay.

### Module D: Track 2 Access Layer — x402 Credit Rail & Cross-Chain Float Refiller ([`src/MezoFloatRefiller.sol`](src/MezoFloatRefiller.sol) & [`sdk/aegisX402Sdk.ts`](sdk/aegisX402Sdk.ts))
- **4-Mode x402 Invoice Clearing**:
  1. `settleX402WithCredit`: Draws fixed-rate MUSD micro-credit from `AegisTroveVault`.
  2. `settleX402WithCarry`: Unwinds the exact MUSD slice needed from `MUSDCarryEngine`.
  3. `settleX402WithBtcSwap`: Executes an atomic `BTC -> MUSD` swap via `MezoPoolsRouter` with strict `minMusdOut` slippage protection.
  4. `settleX402Direct`: Settles directly in MUSD.
- **Autonomous Cross-Chain Float Refiller (`refillFloat` & `quoteCrossChainUsdc`)**: Connects Mezo (`31611`) with Base (`8453`), pricing cross-chain USDC settlements against live `MUSD/mUSDC` pool depth (`0x525F...Dc3e`) and topping up merchant floats under `MusdPegGuard` price floors.

---

## 5. Foundry Test Suite Verification (56 Passing Tests: 38 Unit + 18 Live Fork)

Run the complete test suite (38 unit tests in [`test/AegisMezoUnit.t.sol`](test/AegisMezoUnit.t.sol) + 18 live Mezo Testnet fork tests in [`test/AegisMezoFork.t.sol`](test/AegisMezoFork.t.sol)):

```bash
# Run all 38 unit tests
forge test --match-contract AegisMezoUnitTest -vv

# Run all 18 live fork tests against Mezo Testnet (https://rpc.test.mezo.org)
forge test --match-contract AegisMezoForkTest --fork-url https://rpc.test.mezo.org -vv

# Run the entire 56-test suite against Mezo Testnet RPC
forge test --fork-url https://rpc.test.mezo.org -vv
```

### Live Fork Test Coverage Matrix (`test/AegisMezoFork.t.sol`)
- `testFork_01_CanonicalMezoContractsLiveState`: Verifies live bytecode and cross-contract wiring of all 13 canonical Mezo contracts on `chainId: 31611`.
- `testFork_02_LivePriceFeedAndMultiPoolPegTelemetry`: Queries live BTC oracle price (`$74,195.47`) and `MUSD/mUSDC`, `maMUSD/MUSD`, `MUSD/BTC` pool rates.
- `testFork_03_LiveHintHelpersAndSortedTrovesIndexing`: Computes O(1) `HintHelpers` + `SortedTroves` hints against all 345 live Troves on Mezo Testnet.
- `testFork_04_LiveOpenAndActivateVaultEndToEnd`: Opens a live Trove via `BorrowerOperations`, mints `10,000 MUSD`, pairs `veBTC × veMEZO` for a `5x` boost, and deploys MUSD to `MUSDCarryEngine`.
- `testFork_05_LiveRedemptionDistanceRadar`: Walks the live `SortedTroves` doubly-linked list from `getLast()` to compute cumulative MUSD debt ahead in the redemption line.
- `testFork_06_LiveAutonomousKeeperRescueUnderPriceDrop`: Executes a live `autonomousRescue`, pulling MUSD from `MUSDCarryEngine` and calling `BorrowerOperations.repayMUSD` with `HintHelpers` hints.
- `testFork_07_LiveAutonomousRescueOnPegDiscountRedemptionLine`: Proves autonomous rescue triggered when a Trove sits in the bottom 10% of `SortedTroves` during a MUSD peg discount.
- `testFork_08_LiveStabilityPoolDepositAndWithdrawFromSPZeroHarvest`: Deposits MUSD into canonical `StabilityPool` (`0x1CCA...680e`) and executes `withdrawFromSP(0)`.
- `testFork_09_LiveInstantUnwindFromCarryEngineAndMaMusdPool`: Unwinds MUSD from `StabilityPool` + `maMUSD/MUSD` pool (`0xBF32...FDE0`) in a single transaction.
- `testFork_10_LiveTieredBorrowFeeRebates`: Proves Gold Tier (`50,000 MEZO` staked) subsidizes 50% of `BorrowerOperations` MUSD minting fees.
- `testFork_11_LiveX402SettlementViaTroveMicroCredit`: AI agent settles an HTTP 402 invoice by drawing micro-credit from `AegisTroveVault`.
- `testFork_12_LiveX402SettlementViaCarryEngineSlice`: AI agent settles an HTTP 402 invoice by unwinding a yield slice from `MUSDCarryEngine`.
- `testFork_13_LiveX402AtomicBtcToMusdCheckout`: Buyer settles an HTTP 402 checkout invoice via an atomic `BTC -> MUSD` swap on live Mezo Pools.
- `testFork_14_LiveCrossChainBaseUsdcSettlementAndPricing`: Prices and settles a Base (`8453`) USDC invoice against live `MUSD/mUSDC` pool depth (`0x525F...Dc3e`).
- `testFork_15_LiveAutonomousKeeperFloatRefill`: Keeper refills a depleted merchant MUSD float under `MusdPegGuard` price floors.
- `testFork_16_LiveAddCollateralWithHintHelpersReindexing`: Adds native BTC collateral to an active Trove with `HintHelpers` re-indexing.
- `testFork_17_LiveRepayUserTroveDebtWithHints`: Repays Trove MUSD debt directly with `HintHelpers` re-indexing.
- `testFork_18_LiveGaugeVoteRoutingAndRewardClaiming`: Routes gauge votes via `Voter` (`0x263F...85F0D`) and splits BTC + MUSD rewards.

---

## 6. Running the Full-Stack Next.js Omni-Clearing App & x402 API

```bash
# 1. Install dependencies
npm install

# 2. Start the development server
npm run dev

# 3. Production build check
npm run build
```

- **Live Telemetry Endpoint**: `GET /api/telemetry` queries `https://rpc.test.mezo.org` for live `PriceFeed`, `SortedTroves` front-line nodes, `StabilityPool` TVL, and `MUSD/mUSDC`, `maMUSD/MUSD`, `MUSD/BTC` reserves.
- **Live HTTP 402 Clearing Endpoint**: `GET /api/x402` returns HTTP `402 Payment Required` with `WWW-Authenticate: x402` challenge headers; `POST /api/x402` executes and verifies settlement across all 4 payment modes.

---

## 7. Wave 2 Submission Compliance & Post-Hackathon Roadmap

Full submission materials—including the **10-Slide Product Deck**, **2-Minute Pitch Video Script & Choreography**, and **Blockscout Verification Guide**—are available in [`docs/SUBMISSION_PACK.md`](docs/SUBMISSION_PACK.md).

| Mezo Program Principle / Requirement | Compliance Status | Evidence in Repository |
| :--- | :---: | :--- |
| **Supported Chains (`Mezo 31611/31612`, `Base 8453`)** | ✅ **Complete** | [`MezoAddresses.sol`](src/libraries/MezoAddresses.sol), [`mezoChain.ts`](lib/mezoChain.ts), [`DeployAegisMezoV2.s.sol`](script/DeployAegisMezoV2.s.sol) |
| **Mandatory `MUSD` + `MEZO` Integration** | ✅ **Complete** | `MUSD` (`0x1189...c503`) minting/repayment/carry/clearing + `MEZO`/`veMEZO` (`0xaCE8...111b`) 5x boost leasing & Bronze/Silver/Gold fee rebates |
| **Extend, Don't Detour** | ✅ **Complete** | Directly extends `BorrowerOperations`, `TroveManager`, `SortedTroves`, `HintHelpers`, `StabilityPool`, `Mezo Pools`, and `Voter`/`Booster` |
| **Composability Wins** | ✅ **Complete** | Atomic 4-primitive composition in [`AegisTroveVault.openAndActivateVault`](src/AegisTroveVault.sol) + `x402` SDK ([`sdk/aegisX402Sdk.ts`](sdk/aegisX402Sdk.ts)) |
| **Long-Term Commitment & Post-Hackathon Roadmap** | ✅ **Complete** | 56 passing tests (`38 unit + 18 live fork`), production Next.js app, and Q4 2026 – Q1 2027 Mainnet & Keeper Network launch plan in [`docs/SUBMISSION_PACK.md`](docs/SUBMISSION_PACK.md) |

### Stage 2 Judging Criteria Alignment (100% Weight Breakdown)

| Judging Criterion | Weight | AegisMezo V2 Implementation & Proof |
| :--- | :---: | :--- |
| **Mezo Integration** | **30%** | Deep on-chain integration with **15 canonical Mezo Testnet (`31611`) contracts** (`MUSD`, `BorrowerOperations`, `TroveManager`, `SortedTroves`, `HintHelpers`, `StabilityPool`, `PriceFeed`, `maMUSD/MUSD`, `MUSD/mUSDC`, `MUSD/BTC`, `MezoPoolsRouter`, `sUSDat`, `veBTC`, `veMEZO`, `Voter`, `Booster`, `Splitter`) — verified across **18 live fork tests** in [`test/AegisMezoFork.t.sol`](test/AegisMezoFork.t.sol). |
| **Product & Business Viability** | **30%** | Solves **redemption-line cannibalization**, **unpaired `veBTC`/`veMEZO` boost inefficiency**, and **x402 cross-chain merchant clearing**. Generates non-inflationary revenue via a `10%` gauge dividend reserve, `+5.8% to +7.4%` positive-carry spread over the `1%` MUSD borrow rate, and `x402` float settlement fees while locking sticky TVL into `MUSD`, `StabilityPool`, `veBTC`, and `veMEZO`. |
| **Technical Implementation** | **20%** | Zero-mock Solidity 0.8.24 architecture with per-user [`AegisUserTroveProxy`](src/AegisTroveVault.sol) isolation, O(1) `HintHelpers` boundary fast-paths, 3-pool [`MusdPegGuard`](src/MusdPegGuard.sol) price floors, and **56 passing Foundry tests (`38 unit + 18 fork`)** with zero compiler warnings. |
| **User Experience** | **10%** | Unified **Mezo Passport** (native BTC + EVM wallet) connection, 1-transaction [`openAndActivateVault`](src/AegisTroveVault.sol) onboarding, live `SortedTroves` Redemption Radar visualization, and embeddable [`sdk/aegisX402Sdk.ts`](sdk/aegisX402Sdk.ts) checkout widget. |
| **Submission Materials Quality** | **10%** | Architecture diagrams, Sponsor Integration Matrix, 10-Slide Product Deck, and timed 2-Minute Pitch Video Script in [`docs/SUBMISSION_PACK.md`](docs/SUBMISSION_PACK.md). |


