# AegisMezo V2 — Wave 2 Official Submission Pack (Deck, 2-Min Video Script & Roadmap)

> **Program**: Build with MUSD and MEZO: Bitcoin’s Economic Layer (Akindo WaveHack — Wave 2: Nov 2 – Nov 15, 2026)  
> **Tracks**: Track 1 (DeFi) + Track 2 (Access & Distribution)  
> **Networks**: Mezo Testnet (`chainId: 31611`) & Base (`chainId: 8453`)

---

## Part 1: Program Requirements Cross-Reference Matrix

| Mezo Program Requirement | Status | How AegisMezo V2 Satisfies & Exceeds the Requirement |
| :--- | :---: | :--- |
| **1. Supported Chains**<br>*(Mezo, Ethereum, Base, BNB Chain, or Mezo Testnet)* | ✅ **VERIFIED** | Built natively for **Mezo Testnet (`chainId: 31611`)** & **Mezo Mainnet (`chainId: 31612`)** with cross-chain float settlement lanes to **Base (`chainId: 8453`)** ([`MezoAddresses.sol`](../src/libraries/MezoAddresses.sol), [`mezoChain.ts`](../lib/mezoChain.ts)). |
| **2. Mandatory MUSD & MEZO Integration**<br>*(No integration, no eligibility)* | ✅ **VERIFIED** | Integrates **both** `MUSD` (`0x1189...c503`) and `MEZO` / `veMEZO` (`0xaCE8...111b`). Users mint fixed-rate MUSD, route MUSD into `StabilityPool` + `maMUSD/MUSD` + `sUSDat`, stake `MEZO` for Bronze/Silver/Gold borrow-fee rebates, and lease `veMEZO` boost power. |
| **3. Extend, Don't Detour**<br>*(Extend reach & utility of existing Mezo products over standalone apps)* | ✅ **VERIFIED** | Directly extends Mezo's core CDP (`BorrowerOperations`, `TroveManager`, `SortedTroves`, `HintHelpers`), `StabilityPool`, `Mezo Pools` (`maMUSD/MUSD`, `MUSD/mUSDC`, `MUSD/BTC`), and `veBTC` / `veMEZO` gauges without deploying competing or redundant primitives. |
| **4. Composability Wins**<br>*(Plug into lending markets, DEXs, vote-escrow systems)* | ✅ **VERIFIED** | Composes **4 live subsystems** in a single atomic transaction ([`openAndActivateVault`](../src/AegisTroveVault.sol)): (1) CDP Trove creation, (2) `veBTC × veMEZO` vote-escrow boost matching & `Voter` gauge routing, (3) `StabilityPool` + `MezoPoolsRouter` DEX share swaps, and (4) `x402` cross-chain Base USDC clearing. |
| **5. Long-Term Commitment**<br>*(Credible post-hackathon roadmap & production architecture)* | ✅ **VERIFIED** | Zero-mock architecture, 56 passing Foundry tests (38 unit + 18 live Mezo Testnet fork tests), embeddable TypeScript SDK ([`sdk/aegisX402Sdk.ts`](../sdk/aegisX402Sdk.ts)), and a phased Mainnet & Audit Roadmap (see Part 4 below). |
| **6. Live Project Link & Public GitHub Repo** | ✅ **READY** | Full-stack Next.js 15 app (`npm run build` verified) with live `/api/telemetry` RPC indexing and `/api/x402` clearing rail, plus [`DeployAegisMezoV2.s.sol`](../script/DeployAegisMezoV2.s.sol) for one-command deployment and Blockscout verification. |
| **7. Project / Product Deck** | ✅ **READY** | Full 10-slide Product Deck included in **Part 2** below. |
| **8. 2-Minute Pitch Video** | ✅ **READY** | Second-by-second 2-minute demo script and screen choreography included in **Part 3** below. |

---

## Part 2: 10-Slide Product Deck (Copy-Ready for Slides / Pitch / PDF)

### Slide 1 — Title & Frontier Thesis
- **Title**: **AegisMezo V2**: Autonomous Omni-Clearing, Redemption Shield & 5x Boost Engine
- **Subtitle**: Uniting Mezo’s CDP Queue, `veBTC × veMEZO` Flywheel, Positive-Carry Yield, and HTTP 402 (`x402`) Cross-Chain Commerce
- **Tracks**: Dual-Track Submission — Track 1 (DeFi) & Track 2 (Access & Distribution)

### Slide 2 — The 3 Unsolved Problems on Bitcoin's Economic Layer
1. **Silent Redemption Cannibalization**: On Mezo, fixed-rate MUSD borrowers with the lowest NICR sit at the tail of `SortedTroves` (`getLast()`). When MUSD trades at `$0.992`, standard ICR monitors think a `150%` ICR Trove is safe—yet it gets redeemed first.
2. **Stranded `veBTC` & `veMEZO` Capital**: BTC whales lock BTC into 30-day `veBTC` but lack `veMEZO` to hit the **5x boost multiplier**, while `veMEZO` lockers lack enough BTC to utilize their boost weight.
3. **Idle MUSD & Friction in Commerce**: Borrowed 1%-fixed-rate MUSD sits idle instead of earning real yield, and merchants/AI agents on Base (`8453`) lack a zero-slippage rail to accept MUSD credit.

### Slide 3 — The AegisMezo V2 Solution (4 Composable Modules)
- **Module A (`AegisTroveVault` + `MusdPegGuard`)**: Real-time `SortedTroves` Redemption Distance Radar + autonomous keeper debt repayment using O(1) `HintHelpers` traversal.
- **Module B (`MezoBoostExchange`)**: Peer-to-pool `veBTC × veMEZO` boost leasing marketplace unlocking 5x gauge yields + Bronze/Silver/Gold MUSD minting fee rebates (`15%–50%`).
- **Module C (`MUSDCarryEngine`)**: Positive-carry router splitting MUSD across `StabilityPool` (`withdrawFromSP(0)`), tokenized STRC (`sUSDat`), and `maMUSD/MUSD` with instant AMM share unwind.
- **Module D (`MezoFloatRefiller` + `aegisX402Sdk.ts`)**: HTTP 402 (`x402`) clearing rail and Base (`8453`) ↔ Mezo (`31611`) float refiller.

### Slide 4 — Deep Dive: Redemption-Aware Self-Healing Troves
- Queries `SortedTroves (0x722E...68fA)` from `getLast()` on every block to calculate exact cumulative MUSD debt ahead of the user's Trove.
- `MusdPegGuard` inspects 3 live Mezo Pools (`MUSD/mUSDC`, `maMUSD/MUSD`, `MUSD/BTC`) + `PriceFeed (0x86bC...9366)`.
- When a Trove enters the bottom 10% of the redemption line during a peg discount, `autonomousRescue()` unwinds MUSD from `MUSDCarryEngine` and calls `BorrowerOperations.repayMUSD()` using O(1) `HintHelpers` hints.

### Slide 5 — Deep Dive: `veBTC × veMEZO` 5x Boost & Fee-Rebate Flywheel
- `veMEZO` holders list idle voting weight; `veBTC` depositors automatically pair to reach the **5.00x (`50,000 bps`)** multiplier.
- Pooled votes route via `Voter (0x263F...85F0D)` to high-fee `maMUSD/MUSD` and `MUSD/mUSDC` gauges.
- Harvested BTC and MUSD rewards split `65%` to `veBTC` depositors, `25%` to `veMEZO` providers, and `10%` to the **Borrower Rebate Reserve**—subsidizing MUSD minting fees by up to **50%** for MEZO stakers.

### Slide 6 — Deep Dive: Positive-Carry Yield Router (`MUSDCarryEngine`)
- Mints MUSD at **1% fixed interest** and deploys into:
  - `StabilityPool (0x1CCA...680e)` — auto-harvesting discounted BTC liquidations via `withdrawFromSP(0)`
  - `sUSDat (0xBCaf...Ee87)` — tokenized STRC real-world yield
  - `maMUSD/MUSD Pool (0xBF32...FDE0)` — stable swap fee yield
- **Zero Epoch Delay**: `instantUnwindToMusd()` swaps `maMUSD` shares directly through `MezoPoolsRouter (0x9a1f...D7E9)` to repay Trove debt or clear x402 invoices in a single transaction.

### Slide 7 — Track 2 Access Layer: HTTP 402 (`x402`) & Cross-Chain Float Refiller
- Embeddable TypeScript SDK (`sdk/aegisX402Sdk.ts`) + Next.js checkout widget.
- Supports 4 atomic settlement modes:
  1. **Trove Micro-Credit Draw** (`1%` fixed rate)
  2. **CarryEngine Yield Slice Unwind**
  3. **Atomic `BTC -> MUSD` Checkout Swap** via `MezoPoolsRouter` with strict slippage floors
  4. **Direct MUSD Settlement**
- `MezoFloatRefiller` settles merchants in **Base USDC (`8453`)** or **Mezo MUSD (`31611`)**, refilling floats against `MUSD/mUSDC` depth under `MusdPegGuard` price floors.

### Slide 8 — Zero-Mock Engineering & Live Mezo Testnet Verification
- **100% Canonical Bindings**: Zero mock tokens in `src/`; bound directly to 15 canonical Mezo Testnet (`31611`) contracts.
- **56 Passing Foundry Tests**:
  - `38` Unit Tests (`test/AegisMezoUnit.t.sol`)
  - `18` Live Fork Tests (`test/AegisMezoFork.t.sol` at `https://rpc.test.mezo.org`) proving live Trove creation, `HintHelpers` indexing, `autonomousRescue`, `withdrawFromSP(0)`, and x402 clearing.

### Slide 9 — Live Product Demo Architecture
- Unified **Mezo Passport** onboarding (native BTC + EVM wallet signing on `chainId: 31611`).
- Live `/api/telemetry` RPC engine streaming real-time `PriceFeed` (`~$74,195 BTC`), `SortedTroves` (`345 active Troves`), `StabilityPool` TVL, and AMM pool reserves.

### Slide 10 — Post-Hackathon Roadmap & Mainnet Launch Plan
- **Phase 1 (Wave 2 Completion — Nov 2026)**: Complete Mezo Testnet (`31611`) public stress-testing & open-source `@aegismezo/x402-sdk`.
- **Phase 2 (Q4 2026)**: Security audit of `AegisTroveVault` proxy isolation and `MezoBoostExchange` accounting; deploy on **Mezo Mainnet (`31612`)** & **Base Mainnet (`8453`)**.
- **Phase 3 (Q1 2027)**: Decentralized Keeper Network (Gelato / Chainlink Automation) for 24/7 `autonomousRescue` & Wormhole NTT cross-chain float rebalancing.

---

## Part 3: 2-Minute Pitch Video Script & Screen Choreography

- **`0:00 – 0:20` | Hook & Live Telemetry Ribbon (`app/page.tsx` Top Bar)**
  - *Visual*: Open the AegisMezo V2 dashboard, connect via **Mezo Passport (BTC + EVM)**, and point to the live telemetry ribbon reading block height, `PriceFeed` (`$74,195` BTC), and `345` active Troves on `SortedTroves (0x722E...68fA)`.
  - *Voiceover*: *"On Mezo, fixed-rate MUSD borrowers face a hidden risk: redemption-line cannibalization in SortedTroves. Meanwhile, veBTC and veMEZO holders lack a marketplace to pair for the 5x boost, and borrowed MUSD needs instant commerce utility. Meet AegisMezo V2—an autonomous omni-clearing and boost engine built 100% on canonical Mezo contracts."*
- **`0:20 – 0:50` | Module A: SortedTroves Radar & Self-Healing Rescue (Tab 1)**
  - *Visual*: Show the live **SortedTroves Front-Line Radar** table displaying real Mezo Testnet Troves from `getLast()` upward. Click **Execute `openAndActivateVault()`**, then click **Simulate Peg Discount (`$0.9885`)** and **Trigger `autonomousRescue()`**.
  - *Voiceover*: *"In one transaction, AegisTroveVault computes O(1) HintHelpers insertion hints, opens a Trove via BorrowerOperations, locks a slice into veBTC, and deploys minted MUSD into our Carry Engine. When MusdPegGuard detects a peg discount, our keeper automatically unwinds yield shares and calls repayMUSD—healing the Trove's ICR and pushing it out of the redemption danger zone."*
- **`0:50 – 1:15` | Module B & C: `veBTC × veMEZO` 5x Boost & Carry Engine (Tabs 2 & 3)**
  - *Visual*: Switch to **Module B**, drag the `veBTC` and `veMEZO` sliders to hit **5.00x Boost**, show the **Gold Tier (50% Minting Fee Rebate)**, and click **Pair & Route Gauge Emissions**. Switch to **Module C** and click **Harvest BTC Gains via `withdrawFromSP(0)`** and **Execute `instantUnwindToMusd()`**.
  - *Voiceover*: *"MezoBoostExchange pairs 30-day veBTC with idle veMEZO to unlock the 5x multiplier, routes votes through Mezo's Voter contract, and recycles gauge dividends to subsidize MUSD minting fees by up to 50%. Meanwhile, MUSDCarryEngine compounds StabilityPool liquidation gains via withdrawFromSP(0) and sUSDat yield, with zero-epoch unwinds through the maMUSD/MUSD pool."*
- **`1:15 – 1:45` | Module D: Track 2 x402 Credit Rail & Base Float Refiller (Tab 4)**
  - *Visual*: Switch to **Module D**, click **1. Request Protected Resource (HTTP 402)** to display the live `402 Payment Required` challenge header, select **Mode A: Draw AegisTroveVault Micro-Credit** targeting **Base Mainnet (8453)**, and click **2. Auto-Clear x402 Invoice Now**, followed by **Execute Keeper `refillFloat()`**.
  - *Voiceover*: *"For Track 2 Access & Distribution, our x402 SDK lets any shopper or AI agent settle HTTP 402 invoices on Mezo or Base by drawing 1% fixed-rate Trove credit, unwinding CarryEngine yield, or executing an atomic BTC-to-MUSD swap—while MezoFloatRefiller rebalances merchant liquidity under strict on-chain peg floors."*
- **`1:45 – 2:00` | Foundry 56-Test Verification & Close (Terminal)**
  - *Visual*: Show terminal output of `forge test --fork-url https://rpc.test.mezo.org -vv` passing all **56 tests (`38 unit + 18 live fork`)** in ~13 seconds.
  - *Voiceover*: *"Backed by 38 unit tests and 18 live Mezo Testnet fork tests with zero mock contracts, AegisMezo V2 turns MUSD and MEZO into a self-healing, positive-carry clearing layer for Bitcoin."*

---

## Part 4: Stage 1 & Stage 2 Judging Criteria Cross-Reference (100% Weight Breakdown)

### Stage 1: AKINDO DevRel Screening Gate (Pass/Fail)
| Screening Gate | Status | Direct Verification Path for AKINDO DevRel |
| :--- | :---: | :--- |
| **MUSD or MEZO Integration Present** | ✅ **PASS** | Dual-token integration (`MUSD` + `MEZO` / `veMEZO` / `veBTC`) across all 5 core contracts in [`src/`](../src/) |
| **Working Deployment on Supported Chain** | ✅ **PASS** | Bound to live **Mezo Testnet (`chainId: 31611`)** contracts + live RPC telemetry (`/api/telemetry`) & HTTP 402 clearing (`/api/x402`) |
| **All Submission Materials Provided** | ✅ **PASS** | Public GitHub repo, live app, 10-slide Product Deck (Part 2), and 2-minute Pitch Video script (Part 3) |

---

### Stage 2: Mezo Core Team Weighted Evaluation Rubric (100 Points)

| Criterion | Weight | What Judges Look For | How AegisMezo V2 Maximizes Score | Code & Test Proof |
| :--- | :---: | :--- | :--- | :--- |
| **1. Mezo Integration** | **30%** | Deep, non-cosmetic use of MUSD & MEZO vs. surface-level ERC-20 transfers | Integrates **15 canonical Mezo contracts**: `MUSD`, `BorrowerOperations`, `TroveManager`, `SortedTroves` doubly-linked list, `HintHelpers` O(1) NICR hints, `StabilityPool` (`withdrawFromSP(0)`), `PriceFeed`, `maMUSD/MUSD`, `MUSD/mUSDC`, `MUSD/BTC`, `MezoPoolsRouter`, `sUSDat`, `veBTC`, `veMEZO`, `Voter`, `Booster`, and `Splitter`. | [`MezoAddresses.sol`](../src/libraries/MezoAddresses.sol)<br>[`IMezoCore.sol`](../src/interfaces/IMezoCore.sol)<br>[`AegisMezoFork.t.sol`](../test/AegisMezoFork.t.sol) |
| **2. Product & Business Viability** | **30%** | Problem-solution fit, business model viability, and ecosystem complementarity across Track 1 & Track 2 | Solves **3 real pain points** for Mezo users:<br>1. **Redemption cannibalization** on fixed-rate Troves<br>2. **Unpaired `veBTC` / `veMEZO`** missing the 5x boost<br>3. **Merchant/AI agent checkout friction** via `x402` clearing.<br>**Sustainable Non-Inflationary Revenue Model**:<br>- **10% Gauge Dividend Reserve** in `MezoBoostExchange` funds Bronze/Silver/Gold borrow-fee rebates and protocol treasury.<br>- **Positive-Carry Spread (`+5.8%` to `+7.4%` net APY)** over Mezo's `1%` borrow rate via `StabilityPool` + `sUSDat` STRC yield.<br>- **Cross-Chain Float Fee (`5–15 bps`)** on `x402` Base USDC ↔ Mezo MUSD settlements. | [`AegisTroveVault.sol`](../src/AegisTroveVault.sol)<br>[`MezoBoostExchange.sol`](../src/MezoBoostExchange.sol)<br>[`MUSDCarryEngine.sol`](../src/MUSDCarryEngine.sol)<br>[`MezoFloatRefiller.sol`](../src/MezoFloatRefiller.sol) |
| **3. Technical Implementation** | **20%** | Code quality, security, architecture, and genuine composability/deployability | - **Zero Mock Contracts** in `src/`<br>- **Per-User `AegisUserTroveProxy` Isolation**: Solves Liquity/Mezo's 1-Trove-per-address constraint safely<br>- **3-Pool + Oracle Peg Guard**: `MusdPegGuard` prevents manipulated AMM refills or rescues<br>- **56 Passing Foundry Tests**: `38` unit tests + `18` live Mezo Testnet fork tests with zero compiler warnings. | [`AegisTroveVault.sol`](../src/AegisTroveVault.sol)<br>[`MusdPegGuard.sol`](../src/MusdPegGuard.sol)<br>[`AegisMezoUnit.t.sol`](../test/AegisMezoUnit.t.sol) |
| **4. User Experience** | **10%** | Design, usability, accessibility, and frictionless onboarding | - **1-Click Mezo Passport** (native BTC + EVM wallet signing with automatic `chainId: 31611` switching)<br>- **1-Tx Onboarding (`openAndActivateVault`)**: Opens Trove, pairs 5x boost, claims fee rebate, and deploys positive carry in a single signature<br>- **Visual Redemption Radar**: Live front-line queue table instead of raw hex data. | [`app/page.tsx`](../app/page.tsx)<br>[`app/api/telemetry/route.ts`](../app/api/telemetry/route.ts)<br>[`sdk/aegisX402Sdk.ts`](../sdk/aegisX402Sdk.ts) |
| **5. Submission Materials Quality** | **10%** | Demo clarity, architecture documentation, and pitch effectiveness | - Comprehensive [`README.md`](../README.md) with Mermaid diagrams and Sponsor Integration Matrix<br>- Full 10-slide Product Deck (Part 2)<br>- Timed 2-minute Pitch Video script & screen choreography (Part 3). | [`README.md`](../README.md)<br>[`docs/SUBMISSION_PACK.md`](SUBMISSION_PACK.md) |

---

## Part 5: One-Command Mezo Testnet (`31611`) Deployment & Verification

To deploy a fresh instance of all 5 contracts onto Mezo Testnet (`chainId: 31611`) and verify on `https://explorer.test.mezo.org`:

```bash
export DEPLOYER_PRIVATE_KEY=0xYOUR_MEZO_TESTNET_PRIVATE_KEY

# Deploy MusdPegGuard, MUSDCarryEngine, MezoBoostExchange, AegisTroveVault, and MezoFloatRefiller
forge script script/DeployAegisMezoV2.s.sol:DeployAegisMezoV2 \
  --rpc-url https://rpc.test.mezo.org \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url https://api.explorer.test.mezo.org/api
```
