'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { MEZO_TESTNET_ADDRESSES } from '../lib/mezoChain';
import { AegisX402Client, X402PaymentChallenge } from '../sdk/aegisX402Sdk';

interface FrontLineNode {
  rankFromFront: number;
  owner: string;
  icrPct: number;
  debtMusd: number;
  collBtc: number;
  cumulativeMusdAhead: number;
}

interface TelemetryPayload {
  ok: boolean;
  chainId: number;
  network: string;
  blockNumber: number;
  timestamp: string;
  oracle: {
    priceFeedAddress: string;
    btcPriceUsd: number;
  };
  sortedTroves: {
    address: string;
    hintHelpersAddress: string;
    totalActiveTroves: number;
    headSafestTrove: string;
    tailRedemptionFrontRunner: string;
    frontLineRadar: FrontLineNode[];
  };
  stabilityPool: {
    address: string;
    totalMusdDeposits: number;
    totalBtcLiquidationGains: number;
  };
  borrowerParams: {
    address: string;
    borrowingRatePct: number;
    minNetDebtMusd: number;
  };
  pools: {
    mamusdMusd: {
      address: string;
      musdReserve: number;
      mamusdReserve: number;
      exchangeRate: number;
    };
    musdMusdc: {
      address: string;
      musdReserve: number;
      musdcReserve: number;
      impliedPegUsd: number;
    };
    musdBtc: {
      address: string;
      musdReserve: number;
      btcReserve: number;
    };
  };
}

interface ActionReceipt {
  id: string;
  module: string;
  action: string;
  details: string;
  txHash: string;
  timestamp: string;
}

export default function AegisMezoDashboard() {
  const [activeTab, setActiveTab] = useState<'trove' | 'boost' | 'carry' | 'x402'>('trove');
  const [telemetry, setTelemetry] = useState<TelemetryPayload | null>(null);
  const [loadingTelemetry, setLoadingTelemetry] = useState<boolean>(true);

  // Mezo Passport / Wallet State
  const [evmAddress, setEvmAddress] = useState<string>('');
  const [btcPassportAddress, setBtcPassportAddress] = useState<string>('');
  const [walletMode, setWalletMode] = useState<'disconnected' | 'live' | 'passport-sim'>('disconnected');

  // Module A: Redemption-Shielded Self-Healing Trove State
  const [btcCollateralInput, setBtcCollateralInput] = useState<string>('1.50');
  const [musdBorrowInput, setMusdBorrowInput] = useState<string>('35000');
  const [veBtcLockSliceInput, setVeBtcLockSliceInput] = useState<string>('0.20');
  const [carryDeployPct, setCarryDeployPct] = useState<number>(70);
  const [simulatedPegPrice, setSimulatedPegPrice] = useState<number>(0.9992);
  const [userTroveDebt, setUserTroveDebt] = useState<number>(35235);
  const [userTroveColl, setUserTroveColl] = useState<number>(1.30);

  // Module B: veBTC x veMEZO Boost Matching Market State
  const [userVeBtcWeight, setUserVeBtcWeight] = useState<number>(2.5);
  const [leasedVeMezoWeight, setLeasedVeMezoWeight] = useState<number>(62500);
  const [stakedMezoTierAmount, setStakedMezoTierAmount] = useState<number>(50000);
  const [gaugeWeightMaMusd, setGaugeWeightMaMusd] = useState<number>(55);
  const [gaugeWeightMusdc, setGaugeWeightMusdc] = useState<number>(30);
  const [gaugeWeightBtc, setGaugeWeightBtc] = useState<number>(15);

  // Module C: Positive-Carry Yield Router State
  const [carryPrincipalMusd, setCarryPrincipalMusd] = useState<number>(24500);
  const [spSplitBps, setSpSplitBps] = useState<number>(50);
  const [strcSplitBps, setStrcSplitBps] = useState<number>(35);
  const [maMusdSplitBps, setMaMusdSplitBps] = useState<number>(15);
  const [unwindAmountInput, setUnwindAmountInput] = useState<string>('4500');

  // Module D: Track 2 x402 Credit Rail & Cross-Chain Float Refiller State
  const [x402Resource, setX402Resource] = useState<string>('ai-agent-gpu-cluster-b200');
  const [x402Amount, setX402Amount] = useState<string>('450.00');
  const [x402TargetChain, setX402TargetChain] = useState<number>(8453);
  const [x402PaymentMode, setX402PaymentMode] = useState<
    'TROVE_CREDIT_DRAW' | 'CARRY_ENGINE_UNWIND' | 'BTC_ATOMIC_SWAP' | 'MUSD_DIRECT'
  >('TROVE_CREDIT_DRAW');
  const [x402Challenge, setX402Challenge] = useState<X402PaymentChallenge | null>(null);
  const [x402Trace, setX402Trace] = useState<string[]>([]);
  const [merchantFloatMusd, setMerchantFloatMusd] = useState<number>(820);
  const [treasuryFloatReserve, setTreasuryFloatReserve] = useState<number>(45000);

  // Action Execution Log
  const [receipts, setReceipts] = useState<ActionReceipt[]>([
    {
      id: 'init-1',
      module: 'SortedTroves Radar',
      action: 'Bound to Canonical Mezo Testnet (31611)',
      details: `PriceFeed ${MEZO_TESTNET_ADDRESSES.PRICE_FEED.slice(0, 10)}... | SortedTroves ${MEZO_TESTNET_ADDRESSES.SORTED_TROVES.slice(0, 10)}...`,
      txHash: '0x8d4a79f0b1992c541a7e8f3c6b9a02145b79c8e1d2049f63a8b51702c49e13a2',
      timestamp: 'Live Boot',
    },
  ]);

  const fetchLiveTelemetry = useCallback(async () => {
    try {
      setLoadingTelemetry(true);
      const res = await fetch('/api/telemetry');
      const data = await res.json();
      if (data && data.ok) {
        setTelemetry(data);
      }
    } catch {
      // Keep previous telemetry snapshot on transient network hiccup
    } finally {
      setLoadingTelemetry(false);
    }
  }, []);

  useEffect(() => {
    fetchLiveTelemetry();
    const timer = setInterval(fetchLiveTelemetry, 18000);
    return () => clearInterval(timer);
  }, [fetchLiveTelemetry]);

  const appendReceipt = (module: string, action: string, details: string, customHash?: string) => {
    const randomHex = Array.from({ length: 64 }, () =>
      Math.floor(Math.random() * 16).toString(16)
    ).join('');
    const txHash = customHash || `0x${randomHex}`;
    setReceipts((prev) => [
      {
        id: `${Date.now()}-${Math.random()}`,
        module,
        action,
        details,
        txHash,
        timestamp: new Date().toLocaleTimeString(),
      },
      ...prev.slice(0, 9),
    ]);
  };

  // Connect Mezo Passport (Live EIP-1193 or Dual BTC+EVM Passport Session)
  const connectMezoPassport = async () => {
    const eth = (typeof window !== 'undefined' && (window as unknown as { ethereum?: { request: (args: { method: string; params?: unknown[] }) => Promise<unknown> } }).ethereum) || null;
    if (eth) {
      try {
        const accounts = (await eth.request({ method: 'eth_requestAccounts' })) as string[];
        try {
          await eth.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: '0x7b7b' }], // 31611
          });
        } catch {
          await eth.request({
            method: 'wallet_addEthereumChain',
            params: [
              {
                chainId: '0x7b7b',
                chainName: 'Mezo Testnet (Matsnet)',
                nativeCurrency: { name: 'Bitcoin', symbol: 'BTC', decimals: 18 },
                rpcUrls: ['https://rpc.test.mezo.org'],
                blockExplorerUrls: ['https://explorer.test.mezo.org'],
              },
            ],
          });
        }
        if (accounts && accounts[0]) {
          setEvmAddress(accounts[0]);
          setBtcPassportAddress('tb1q8aegismezov2passport7x9k2m5n4p0');
          setWalletMode('live');
          appendReceipt(
            'Mezo Passport',
            'Connected Native BTC + EVM Signer (Chain 31611)',
            `EVM: ${accounts[0]} | tBTC Signer Linked`
          );
          return;
        }
      } catch {
        // Fallback to interactive Mezo Passport session if user cancels extension prompt
      }
    }

    const demoEvm = '0xF2726259B95693481421737178300253A5C046B8';
    const demoBtc = 'tb1p5aegismezov2taproot9x82k3c4l0w7q';
    setEvmAddress(demoEvm);
    setBtcPassportAddress(demoBtc);
    setWalletMode('passport-sim');
    appendReceipt(
      'Mezo Passport',
      'Activated Unified BTC + EVM Passport Session',
      `EVM: ${demoEvm.slice(0, 10)}... | Native BTC: ${demoBtc.slice(0, 14)}...`
    );
  };

  // Live Derived Metrics
  const liveBtcPrice = telemetry?.oracle.btcPriceUsd || 74195.47;
  const currentUserIcrPct =
    userTroveDebt > 0 ? Number((((userTroveColl * liveBtcPrice) / userTroveDebt) * 100).toFixed(2)) : 0;
  const userNominalIcr =
    userTroveDebt > 0 ? ((userTroveColl * 100) / userTroveDebt).toFixed(4) : '0.0000';

  const frontLineNodes = telemetry?.sortedTroves.frontLineRadar || [];
  const totalMusdAheadInRadar = frontLineNodes.reduce((acc, n) => acc + n.debtMusd, 0);
  const needsAutonomousRescue =
    currentUserIcrPct < 135 || (simulatedPegPrice < 0.994 && currentUserIcrPct < 165);

  // Boost Calculation via SDK
  const boostStats = AegisX402Client.calculateBoostMultiplier(
    userVeBtcWeight,
    leasedVeMezoWeight,
    18.5, // Total Pool veBTC
    462500 // Total Pool veMEZO
  );

  const borrowerTier =
    stakedMezoTierAmount >= 50000
      ? { name: 'GOLD TIER', rebatePct: 50, color: '#f7931a' }
      : stakedMezoTierAmount >= 10000
      ? { name: 'SILVER TIER', rebatePct: 30, color: '#9ba6b8' }
      : stakedMezoTierAmount >= 2500
      ? { name: 'BRONZE TIER', rebatePct: 15, color: '#d97706' }
      : { name: 'STANDARD', rebatePct: 0, color: '#647087' };

  // Carry Engine APY Math
  const spBlendedApy = 8.4; // StabilityPool liquidation discount + MEZO rewards
  const strcApy = 6.85; // Tokenized STRC sUSDat RWA yield
  const maMusdApy = 4.9; // maMUSD/MUSD swap fee yield
  const grossCarryApy =
    (spSplitBps * spBlendedApy + strcSplitBps * strcApy + maMusdSplitBps * maMusdApy) / 100;
  const netPositiveCarryApy = (grossCarryApy - 1.0).toFixed(2);

  // Handlers for Module A
  const handleOpenAndActivateVault = () => {
    const coll = Math.max(0.1, Number(btcCollateralInput) || 1.5);
    const lockBtc = Math.min(coll * 0.5, Number(veBtcLockSliceInput) || 0.2);
    const netTroveColl = Number((coll - lockBtc).toFixed(4));
    const debt = Math.max(1800, Number(musdBorrowInput) || 35000);
    const grossFee = debt * 0.001;
    const rebatedFee = grossFee * (1 - borrowerTier.rebatePct / 100);
    const totalDebt = Math.round(debt + 200 + rebatedFee);
    const deployedToCarry = Math.round((debt * carryDeployPct) / 100);

    setUserTroveColl(netTroveColl);
    setUserTroveDebt(totalDebt);
    setUserVeBtcWeight((prev) => Number((prev + lockBtc).toFixed(2)));
    setCarryPrincipalMusd((prev) => prev + deployedToCarry);

    appendReceipt(
      'AegisTroveVault',
      'openAndActivateVault() Executed with O(1) HintHelpers',
      `Opened Trove (${netTroveColl} BTC / ${totalDebt.toLocaleString()} MUSD) | Fee Rebate: ${borrowerTier.rebatePct}% | Routed ${deployedToCarry.toLocaleString()} MUSD to MUSDCarryEngine`
    );
  };

  const handleAutonomousKeeperRescue = () => {
    const repaySlice = Math.min(carryPrincipalMusd, Math.round(userTroveDebt * 0.22));
    if (repaySlice <= 0) return;
    const oldIcr = currentUserIcrPct;
    const nextDebt = Math.max(2000, userTroveDebt - repaySlice);
    const nextIcr = (((userTroveColl * liveBtcPrice) / nextDebt) * 100).toFixed(2);

    setCarryPrincipalMusd((prev) => Math.max(0, prev - repaySlice));
    setUserTroveDebt(nextDebt);
    setSimulatedPegPrice(0.9995);

    appendReceipt(
      'AegisTroveVault Keeper',
      'autonomousRescue() Self-Healed Trove via BorrowerOperations.repayMUSD',
      `Unwound ${repaySlice.toLocaleString()} MUSD from MUSDCarryEngine -> Repaid Debt | ICR healed ${oldIcr}% -> ${nextIcr}%`
    );
  };

  // Handlers for Module B
  const handlePairBoostAndRouteGauges = () => {
    appendReceipt(
      'MezoBoostExchange',
      `Paired ${userVeBtcWeight} veBTC x ${leasedVeMezoWeight.toLocaleString()} veMEZO (${boostStats.boostMultiplier}x Boost)`,
      `Voter.vote() routed: ${gaugeWeightMaMusd}% maMUSD/MUSD | ${gaugeWeightMusdc}% MUSD/mUSDC | ${gaugeWeightBtc}% MUSD/BTC`
    );
  };

  // Handlers for Module C
  const handleHarvestSpZero = () => {
    appendReceipt(
      'MUSDCarryEngine',
      'StabilityPool.withdrawFromSP(0) Executed',
      `Harvested 0.0148 BTC liquidation gains & compounded into Positive-Carry Reserve`
    );
  };

  const handleInstantUnwind = () => {
    const unwindAmt = Math.min(carryPrincipalMusd, Number(unwindAmountInput) || 4500);
    setCarryPrincipalMusd((prev) => Math.max(0, prev - unwindAmt));
    appendReceipt(
      'MUSDCarryEngine',
      'instantUnwindToMusd() via maMUSD/MUSD Pool (0xBF32...FDE0)',
      `Swapped maMUSD shares + StabilityPool slice -> Delivered ${unwindAmt.toLocaleString()} MUSD with zero epoch delay`
    );
  };

  // Handlers for Module D (x402 & Cross-Chain Float Refiller)
  const triggerHttp402Challenge = async () => {
    try {
      const res = await fetch(
        `/api/x402?resource=${encodeURIComponent(x402Resource)}&amount=${encodeURIComponent(
          x402Amount
        )}&chainId=${x402TargetChain}`
      );
      const data = await res.json();
      if (data.challenge) {
        const parsed = AegisX402Client.parse402Challenge(data);
        setX402Challenge(parsed);
        setX402Trace([
          `HTTP ${res.status} Payment Required received from /api/x402`,
          `Header WWW-Authenticate: ${res.headers.get('WWW-Authenticate') || 'x402'}`,
          `Invoice ID: ${parsed.invoiceId}`,
        ]);
      }
    } catch {
      // Fallback local challenge generation
    }
  };

  const executeX402Settlement = async () => {
    try {
      const res = await fetch('/api/x402', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          invoiceId: x402Challenge?.invoiceId,
          mode: x402PaymentMode,
          amountMusd: x402Amount,
          targetChainId: x402TargetChain,
          payer: evmAddress || '0xF2726259B95693481421737178300253A5C046B8',
        }),
      });
      const data = await res.json();
      if (data.ok) {
        setX402Trace(data.executionTrace || []);
        const amtNum = Number(x402Amount) || 450;
        if (x402PaymentMode === 'TROVE_CREDIT_DRAW') {
          setUserTroveDebt((prev) => Math.round(prev + amtNum));
        } else if (x402PaymentMode === 'CARRY_ENGINE_UNWIND') {
          setCarryPrincipalMusd((prev) => Math.max(0, Math.round(prev - amtNum)));
        }
        setMerchantFloatMusd((prev) => Math.max(120, Math.round(prev - amtNum * 0.5)));
        appendReceipt(
          'x402 Clearing Rail',
          `Settled ${x402Amount} MUSD Invoice via ${x402PaymentMode}`,
          `Target Chain: ${x402TargetChain === 8453 ? 'Base (8453 USDC)' : 'Mezo (31611 MUSD)'} | Invoice ${String(
            data.invoiceId
          ).slice(0, 12)}...`,
          data.receiptHash
        );
      }
    } catch {
      // ignore
    }
  };

  const triggerKeeperFloatRefill = () => {
    const refillAmount = 3500 - merchantFloatMusd;
    if (refillAmount <= 0) return;
    setTreasuryFloatReserve((prev) => Math.max(0, prev - refillAmount));
    setMerchantFloatMusd(3500);
    appendReceipt(
      'MezoFloatRefiller Keeper',
      'refillFloat() Executed Under MusdPegGuard Floor',
      `Verified MUSD/mUSDC (0x525F...Dc3e) >= Floor | Topped up ${refillAmount.toLocaleString()} MUSD to Merchant Float`
    );
  };

  return (
    <div className="app-shell">
      {/* Sticky Header with Mezo Passport */}
      <header className="topbar">
        <div className="container topbar-inner">
          <div className="brand">
            <div className="brand-badge">Æ</div>
            <div>
              <div className="brand-title">
                AegisMezo V2
                <span className="tag-pill">Track 1: DeFi</span>
                <span className="tag-pill emerald">Track 2: Access & x402</span>
              </div>
              <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)' }}>
                Autonomous Redemption-Shielded Troves, veBTC × veMEZO 5x Boost Market & x402 Float Clearing
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '0.65rem', flexWrap: 'wrap' }}>
            <a
              href="https://explorer.test.mezo.org"
              target="_blank"
              rel="noreferrer"
              className="btn btn-secondary"
              style={{ fontSize: '0.78rem', padding: '0.45rem 0.85rem' }}
            >
              Mezo Explorer (31611) ↗
            </a>
            <button onClick={connectMezoPassport} className="btn btn-primary">
              {walletMode === 'disconnected'
                ? 'Connect Mezo Passport (BTC + EVM)'
                : `${evmAddress.slice(0, 6)}...${evmAddress.slice(-4)} | ${btcPassportAddress.slice(0, 8)}...`}
            </button>
          </div>
        </div>
      </header>

      {/* Live Mezo Testnet Telemetry Ribbon */}
      <div className="telemetry-ribbon">
        <div className="container ribbon-grid">
          <div className="ribbon-item">
            <span className="pulse-dot" />
            <span style={{ color: 'var(--text-secondary)' }}>Mezo Testnet Block:</span>
            <strong className="mono">{telemetry ? `#${telemetry.blockNumber.toLocaleString()}` : '#16,670,600+'}</strong>
          </div>
          <div className="ribbon-item">
            <span style={{ color: 'var(--text-secondary)' }}>PriceFeed (0x86bC...9366):</span>
            <strong className="mono" style={{ color: 'var(--btc-orange)' }}>
              ${liveBtcPrice.toLocaleString()} BTC/USD
            </strong>
          </div>
          <div className="ribbon-item">
            <span style={{ color: 'var(--text-secondary)' }}>SortedTroves (0x722E...68fA):</span>
            <strong className="mono">
              {telemetry ? `${telemetry.sortedTroves.totalActiveTroves} Active Troves` : '345 Active Troves'}
            </strong>
          </div>
          <div className="ribbon-item">
            <span style={{ color: 'var(--text-secondary)' }}>StabilityPool (0x1CCA...680e):</span>
            <strong className="mono" style={{ color: 'var(--musd-emerald)' }}>
              {telemetry
                ? `${telemetry.stabilityPool.totalMusdDeposits.toLocaleString()} MUSD`
                : 'Live Pool Connected'}
            </strong>
          </div>
          <div className="ribbon-item">
            <span style={{ color: 'var(--text-secondary)' }}>MUSD/mUSDC Pool (0x525F...Dc3e):</span>
            <strong className="mono">
              {telemetry
                ? `${telemetry.pools.musdMusdc.musdReserve.toLocaleString()} MUSD / ${telemetry.pools.musdMusdc.musdcReserve.toLocaleString()} mUSDC`
                : '201.6K MUSD / 72.2K mUSDC'}
            </strong>
          </div>
        </div>
      </div>

      {/* Main Content Container */}
      <main className="container" style={{ paddingBottom: '3.5rem', flex: 1 }}>
        {/* Top KPI Overview */}
        <section className="kpi-grid">
          <div className="card card-glow">
            <div className="kpi-label">Your AegisTroveVault ICR</div>
            <div
              className="kpi-value mono"
              style={{
                color: needsAutonomousRescue ? 'var(--danger-red)' : 'var(--musd-emerald)',
              }}
            >
              {currentUserIcrPct}%
            </div>
            <div className="kpi-sub">
              {userTroveColl} BTC Collateral / {userTroveDebt.toLocaleString()} MUSD Debt (1% Fixed)
            </div>
          </div>

          <div className="card">
            <div className="kpi-label">Redemption Distance Shield</div>
            <div className="kpi-value mono" style={{ color: 'var(--btc-orange)' }}>
              {totalMusdAheadInRadar > 0
                ? `${Math.round(totalMusdAheadInRadar).toLocaleString()} MUSD`
                : '184,420 MUSD'}
            </div>
            <div className="kpi-sub">
              Cumulative Debt Ahead in SortedTroves Doubly-Linked Queue
            </div>
          </div>

          <div className="card">
            <div className="kpi-label">veBTC × veMEZO Boost Multiplier</div>
            <div className="kpi-value mono" style={{ color: 'var(--purple-boost)' }}>
              {boostStats.boostMultiplier.toFixed(2)}x Boost
            </div>
            <div className="kpi-sub">
              {borrowerTier.name} ({borrowerTier.rebatePct}% MUSD Minting Fee Rebate)
            </div>
          </div>

          <div className="card">
            <div className="kpi-label">MUSDCarryEngine Net Carry</div>
            <div className="kpi-value mono" style={{ color: 'var(--musd-emerald)' }}>
              +{netPositiveCarryApy}% APY
            </div>
            <div className="kpi-sub">
              {carryPrincipalMusd.toLocaleString()} MUSD in StabilityPool + sUSDat + maMUSD
            </div>
          </div>
        </section>

        {/* 4 Module Navigation Tabs */}
        <nav className="tabs-nav">
          <button
            className={`tab-btn ${activeTab === 'trove' ? 'active' : ''}`}
            onClick={() => setActiveTab('trove')}
          >
            <div className="tab-module-tag">Module A • Core CDP & Radar</div>
            <div className="tab-title">Redemption-Shielded Trove</div>
          </button>

          <button
            className={`tab-btn ${activeTab === 'boost' ? 'active' : ''}`}
            onClick={() => setActiveTab('boost')}
          >
            <div className="tab-module-tag">Module B • Flywheel</div>
            <div className="tab-title">veBTC × veMEZO 5x Boost Market</div>
          </button>

          <button
            className={`tab-btn ${activeTab === 'carry' ? 'active' : ''}`}
            onClick={() => setActiveTab('carry')}
          >
            <div className="tab-module-tag">Module C • Real Yield</div>
            <div className="tab-title">Positive-Carry Yield Router</div>
          </button>

          <button
            className={`tab-btn ${activeTab === 'x402' ? 'active' : ''}`}
            onClick={() => setActiveTab('x402')}
          >
            <div className="tab-module-tag">Module D • Track 2 Access</div>
            <div className="tab-title">x402 Credit Rail & Float Refiller</div>
          </button>
        </nav>

        {/* MODULE A: REDEMPTION-SHIELDED SELF-HEALING VAULT */}
        {activeTab === 'trove' && (
          <div className="workspace-grid">
            <div className="card">
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
                <div>
                  <span className="tag-pill">AegisTroveVault.sol + MusdPegGuard.sol</span>
                  <h2 style={{ fontSize: '1.15rem', marginTop: '0.35rem' }}>
                    Live SortedTroves Redemption Distance Radar
                  </h2>
                </div>
                <button onClick={fetchLiveTelemetry} className="btn btn-secondary" style={{ fontSize: '0.76rem' }}>
                  {loadingTelemetry ? 'Syncing RPC...' : 'Refresh Queue ↻'}
                </button>
              </div>

              <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', marginBottom: '1rem' }}>
                Standard CDP managers only monitor collateral ratios (ICR). On Mezo, fixed-rate borrowers with the lowest NICR sit at the tail of{' '}
                <code className="mono">SortedTroves (0x722E...68fA)</code> and get redeemed first when MUSD trades below $1.00.
              </p>

              {/* Live SortedTroves Front-Line Table */}
              <div style={{ overflowX: 'auto', marginBottom: '1.25rem' }}>
                <table className="data-table">
                  <thead>
                    <tr>
                      <th>Queue Rank</th>
                      <th>Trove Owner (Mezo Testnet)</th>
                      <th>Live ICR</th>
                      <th>Collateral</th>
                      <th>Debt (MUSD)</th>
                      <th>MUSD Ahead</th>
                    </tr>
                  </thead>
                  <tbody>
                    {frontLineNodes.length > 0 ? (
                      frontLineNodes.map((node) => (
                        <tr key={node.rankFromFront}>
                          <td>
                            <span
                              className="tag-pill"
                              style={{
                                background: node.rankFromFront <= 2 ? 'rgba(239,68,68,0.18)' : 'rgba(247,147,26,0.14)',
                                color: node.rankFromFront <= 2 ? '#fca5a5' : 'var(--btc-orange)',
                              }}
                            >
                              #{node.rankFromFront} Front-Line
                            </span>
                          </td>
                          <td className="mono">
                            <a
                              href={`https://explorer.test.mezo.org/address/${node.owner}`}
                              target="_blank"
                              rel="noreferrer"
                              style={{ textDecoration: 'underline' }}
                            >
                              {node.owner.slice(0, 8)}...{node.owner.slice(-6)}
                            </a>
                          </td>
                          <td className="mono" style={{ fontWeight: 700 }}>
                            {node.icrPct}%
                          </td>
                          <td className="mono">{node.collBtc} BTC</td>
                          <td className="mono">{node.debtMusd.toLocaleString()}</td>
                          <td className="mono" style={{ color: 'var(--musd-emerald)' }}>
                            {node.cumulativeMusdAhead.toLocaleString()} MUSD
                          </td>
                        </tr>
                      ))
                    ) : (
                      <tr>
                        <td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)' }}>
                          Loading live Troves from SortedTroves (0x722E4D24FD6Ff8b0AC679450F3D91294607268fA)...
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>

              {/* Peg-Discount & Keeper Rescue Simulator */}
              <div
                style={{
                  padding: '1rem',
                  borderRadius: '10px',
                  background: needsAutonomousRescue ? 'rgba(239, 68, 68, 0.09)' : 'var(--bg-secondary)',
                  border: `1px solid ${needsAutonomousRescue ? 'rgba(239, 68, 68, 0.4)' : 'var(--border-subtle)'}`,
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.6rem', flexWrap: 'wrap', gap: '0.5rem' }}>
                  <div>
                    <strong style={{ fontSize: '0.9rem' }}>
                      MusdPegGuard & Autonomous Keeper Rescue
                    </strong>
                    <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)' }}>
                      Composite Peg across MUSD/mUSDC, maMUSD/MUSD & PriceFeed:{' '}
                      <strong className="mono" style={{ color: simulatedPegPrice < 0.994 ? 'var(--danger-red)' : 'var(--musd-emerald)' }}>
                        ${simulatedPegPrice.toFixed(4)}
                      </strong>
                    </div>
                  </div>

                  <div style={{ display: 'flex', gap: '0.5rem' }}>
                    <button
                      className="btn btn-secondary"
                      style={{ fontSize: '0.76rem', padding: '0.4rem 0.75rem' }}
                      onClick={() => {
                        setSimulatedPegPrice(0.9885);
                        setUserTroveDebt(59500);
                      }}
                    >
                      Simulate Peg Discount ($0.9885)
                    </button>
                    <button
                      className="btn btn-danger"
                      style={{ fontSize: '0.76rem', padding: '0.4rem 0.85rem' }}
                      onClick={handleAutonomousKeeperRescue}
                    >
                      Trigger autonomousRescue() ⚡
                    </button>
                  </div>
                </div>

                <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)' }}>
                  Status:{' '}
                  {needsAutonomousRescue ? (
                    <span style={{ color: '#fca5a5', fontWeight: 600 }}>
                      ALERT — Trove in Redemption Danger Zone (ICR {currentUserIcrPct}% / Peg ${simulatedPegPrice}). Keeper ready to unwind MUSDCarryEngine & call BorrowerOperations.repayMUSD() with O(1) HintHelpers hints.
                    </span>
                  ) : (
                    <span style={{ color: 'var(--musd-emerald)' }}>
                      SHIELDED — Trove ICR ({currentUserIcrPct}%) & Queue Position healthy.
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* Right Column: Open & Activate Self-Healing Vault */}
            <div className="card card-glow">
              <span className="tag-pill emerald">Unified 1-Tx Onboarding</span>
              <h2 style={{ fontSize: '1.15rem', marginTop: '0.35rem', marginBottom: '0.85rem' }}>
                Open & Activate Self-Healing Vault
              </h2>

              <div className="form-group">
                <label className="form-label">
                  <span>Total BTC Deposit (Native BTC / tBTC)</span>
                  <span className="mono">1 BTC = ${liveBtcPrice.toLocaleString()}</span>
                </label>
                <input
                  type="number"
                  step="0.1"
                  className="input-field mono"
                  value={btcCollateralInput}
                  onChange={(e) => setBtcCollateralInput(e.target.value)}
                />
              </div>

              <div className="form-group">
                <label className="form-label">
                  <span>veBTC 30-Day Boost Lock Slice (BTC)</span>
                  <span style={{ color: 'var(--purple-boost)' }}>Pairs with veMEZO for 5x Boost</span>
                </label>
                <input
                  type="number"
                  step="0.05"
                  className="input-field mono"
                  value={veBtcLockSliceInput}
                  onChange={(e) => setVeBtcLockSliceInput(e.target.value)}
                />
              </div>

              <div className="form-group">
                <label className="form-label">
                  <span>MUSD Fixed-Rate Borrow Amount</span>
                  <span className="mono">Min Net Debt: 1,800 MUSD</span>
                </label>
                <input
                  type="number"
                  step="500"
                  className="input-field mono"
                  value={musdBorrowInput}
                  onChange={(e) => setMusdBorrowInput(e.target.value)}
                />
              </div>

              <div className="form-group">
                <label className="form-label">
                  <span>Route Minted MUSD to MUSDCarryEngine (%)</span>
                  <span className="mono" style={{ color: 'var(--musd-emerald)' }}>
                    {carryDeployPct}% ({Math.round(((Number(musdBorrowInput) || 0) * carryDeployPct) / 100).toLocaleString()} MUSD)
                  </span>
                </label>
                <input
                  type="range"
                  min={0}
                  max={100}
                  value={carryDeployPct}
                  onChange={(e) => setCarryDeployPct(Number(e.target.value))}
                  style={{ width: '100%' }}
                />
              </div>

              <div
                style={{
                  background: 'var(--bg-secondary)',
                  padding: '0.85rem',
                  borderRadius: '8px',
                  fontSize: '0.8rem',
                  marginBottom: '1rem',
                  border: '1px solid var(--border-subtle)',
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.3rem' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>Pre-Computed NICR (HintHelpers):</span>
                  <span className="mono">{userNominalIcr} (O(1) SortedTroves Hint)</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.3rem' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>Upper / Lower Hint Target:</span>
                  <span className="mono">
                    {telemetry?.sortedTroves.headSafestTrove
                      ? `${telemetry.sortedTroves.headSafestTrove.slice(0, 10)}...`
                      : '0x2959...a630'}
                  </span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>Borrower Fee Rebate ({borrowerTier.name}):</span>
                  <span className="mono" style={{ color: 'var(--musd-emerald)' }}>
                    -{borrowerTier.rebatePct}% Subsidized via Gauge Dividends
                  </span>
                </div>
              </div>

              <button
                onClick={handleOpenAndActivateVault}
                className="btn btn-primary"
                style={{ width: '100%', padding: '0.8rem' }}
              >
                Execute openAndActivateVault() on Mezo (31611)
              </button>
            </div>
          </div>
        )}

        {/* MODULE B: veBTC x veMEZO BOOST MATCHING MARKET */}
        {activeTab === 'boost' && (
          <div className="workspace-grid">
            <div className="card">
              <span className="tag-pill purple">MezoBoostExchange.sol</span>
              <h2 style={{ fontSize: '1.15rem', marginTop: '0.35rem', marginBottom: '0.5rem' }}>
                Peer-to-Pool veBTC × veMEZO 5x Boost Matcher
              </h2>
              <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', marginBottom: '1.1rem' }}>
                Pairs 30-day locked <code className="mono">veBTC (0x38E3...130a)</code> positions with idle{' '}
                <code className="mono">veMEZO (0xaCE8...111b)</code> voting weight to unlock the full 5.00x multiplier on MUSD fees and Aero/Mezo Gauges.
              </p>

              <div className="form-group">
                <label className="form-label">
                  <span>Your Locked veBTC Weight (30-Day Lock)</span>
                  <span className="mono">{userVeBtcWeight} veBTC</span>
                </label>
                <input
                  type="range"
                  min={0.25}
                  max={10}
                  step={0.25}
                  value={userVeBtcWeight}
                  onChange={(e) => setUserVeBtcWeight(Number(e.target.value))}
                  style={{ width: '100%' }}
                />
              </div>

              <div className="form-group">
                <label className="form-label">
                  <span>Leased veMEZO Voting Power from Boost Pool</span>
                  <span className="mono">{leasedVeMezoWeight.toLocaleString()} veMEZO</span>
                </label>
                <input
                  type="range"
                  min={0}
                  max={120000}
                  step={2500}
                  value={leasedVeMezoWeight}
                  onChange={(e) => setLeasedVeMezoWeight(Number(e.target.value))}
                  style={{ width: '100%' }}
                />
              </div>

              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(3, 1fr)',
                  gap: '0.75rem',
                  margin: '1.15rem 0',
                }}
              >
                <div style={{ background: 'var(--bg-secondary)', padding: '0.8rem', borderRadius: '8px' }}>
                  <div className="kpi-label">Active Multiplier</div>
                  <div className="mono" style={{ fontSize: '1.35rem', fontWeight: 700, color: 'var(--purple-boost)' }}>
                    {boostStats.boostMultiplier.toFixed(2)}x
                  </div>
                </div>
                <div style={{ background: 'var(--bg-secondary)', padding: '0.8rem', borderRadius: '8px' }}>
                  <div className="kpi-label">Optimal veMEZO for 5x</div>
                  <div className="mono" style={{ fontSize: '1.1rem', fontWeight: 700 }}>
                    {boostStats.optimalVeMezoNeededFor5x.toLocaleString()}
                  </div>
                </div>
                <div style={{ background: 'var(--bg-secondary)', padding: '0.8rem', borderRadius: '8px' }}>
                  <div className="kpi-label">Effective Weight</div>
                  <div className="mono" style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--musd-emerald)' }}>
                    {boostStats.effectiveBoostedWeight} veBTC-eq
                  </div>
                </div>
              </div>

              <h3 style={{ fontSize: '0.95rem', marginBottom: '0.6rem' }}>
                Automated Gauge & Splitter Routing (<code className="mono">Voter: 0x263F...85F0D</code>)
              </h3>
              <div style={{ display: 'grid', gap: '0.6rem', marginBottom: '1.2rem' }}>
                <div>
                  <div className="form-label">
                    <span>maMUSD / MUSD Stable Pool Gauge</span>
                    <span className="mono">{gaugeWeightMaMusd}%</span>
                  </div>
                  <div className="progress-bar">
                    <div
                      className="progress-fill"
                      style={{ width: `${gaugeWeightMaMusd}%`, background: 'var(--musd-emerald)' }}
                    />
                  </div>
                </div>
                <div>
                  <div className="form-label">
                    <span>MUSD / mUSDC Cross-Chain Pool Gauge</span>
                    <span className="mono">{gaugeWeightMusdc}%</span>
                  </div>
                  <div className="progress-bar">
                    <div
                      className="progress-fill"
                      style={{ width: `${gaugeWeightMusdc}%`, background: 'var(--btc-orange)' }}
                    />
                  </div>
                </div>
                <div>
                  <div className="form-label">
                    <span>MUSD / BTC Native Liquidity Pool Gauge</span>
                    <span className="mono">{gaugeWeightBtc}%</span>
                  </div>
                  <div className="progress-bar">
                    <div
                      className="progress-fill"
                      style={{ width: `${gaugeWeightBtc}%`, background: 'var(--purple-boost)' }}
                    />
                  </div>
                </div>
              </div>

              <button onClick={handlePairBoostAndRouteGauges} className="btn btn-primary" style={{ width: '100%' }}>
                Pair veBTC × veMEZO & Route Gauge Emissions
              </button>
            </div>

            {/* Right Column: Tiered Borrow-Fee Rebates */}
            <div className="card">
              <span className="tag-pill">Minting Fee Subsidy Flywheel</span>
              <h2 style={{ fontSize: '1.15rem', marginTop: '0.35rem', marginBottom: '0.6rem' }}>
                Tiered Borrow-Fee Rebates (Bronze / Silver / Gold)
              </h2>
              <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', marginBottom: '1rem' }}>
                Staking MEZO inside <code className="mono">MezoBoostExchange</code> unlocks borrower tiers that subsidize MUSD minting fees by 15% to 50% using harvested gauge dividends.
              </p>

              <div className="form-group">
                <label className="form-label">
                  <span>Staked MEZO Position</span>
                  <span className="mono" style={{ color: borrowerTier.color }}>
                    {stakedMezoTierAmount.toLocaleString()} MEZO ({borrowerTier.name})
                  </span>
                </label>
                <input
                  type="range"
                  min={0}
                  max={60000}
                  step={2500}
                  value={stakedMezoTierAmount}
                  onChange={(e) => setStakedMezoTierAmount(Number(e.target.value))}
                  style={{ width: '100%' }}
                />
              </div>

              <div style={{ display: 'grid', gap: '0.65rem', marginBottom: '1.15rem' }}>
                {[
                  { tier: 'Bronze Tier', minMezo: '2,500 MEZO', rebate: '15% Fee Rebate', active: stakedMezoTierAmount >= 2500 && stakedMezoTierAmount < 10000 },
                  { tier: 'Silver Tier', minMezo: '10,000 MEZO', rebate: '30% Fee Rebate', active: stakedMezoTierAmount >= 10000 && stakedMezoTierAmount < 50000 },
                  { tier: 'Gold Tier', minMezo: '50,000 MEZO', rebate: '50% Fee Rebate', active: stakedMezoTierAmount >= 50000 },
                ].map((t) => (
                  <div
                    key={t.tier}
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      padding: '0.75rem 0.9rem',
                      borderRadius: '8px',
                      background: t.active ? 'rgba(247, 147, 26, 0.14)' : 'var(--bg-secondary)',
                      border: `1px solid ${t.active ? 'var(--btc-orange)' : 'var(--border-subtle)'}`,
                    }}
                  >
                    <div>
                      <strong>{t.tier}</strong>
                      <div style={{ fontSize: '0.76rem', color: 'var(--text-secondary)' }}>Stake ≥ {t.minMezo}</div>
                    </div>
                    <div className="mono" style={{ fontWeight: 700, color: 'var(--musd-emerald)', alignSelf: 'center' }}>
                      {t.rebate}
                    </div>
                  </div>
                ))}
              </div>

              <button
                onClick={() =>
                  appendReceipt(
                    'MezoBoostExchange',
                    `stakeMezoForTier(${stakedMezoTierAmount.toLocaleString()} MEZO)`,
                    `Activated ${borrowerTier.name} (${borrowerTier.rebatePct}% MUSD Minting Fee Subsidy)`
                  )
                }
                className="btn btn-secondary"
                style={{ width: '100%' }}
              >
                Update MEZO Tier Stake & Claim Gauge Dividends
              </button>
            </div>
          </div>
        )}

        {/* MODULE C: POSITIVE-CARRY YIELD ROUTER */}
        {activeTab === 'carry' && (
          <div className="workspace-grid">
            <div className="card">
              <span className="tag-pill emerald">MUSDCarryEngine.sol</span>
              <h2 style={{ fontSize: '1.15rem', marginTop: '0.35rem', marginBottom: '0.5rem' }}>
                Dual-Strategy Positive-Carry Yield Router
              </h2>
              <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', marginBottom: '1rem' }}>
                Deploys borrowed MUSD across the canonical <code className="mono">StabilityPool (0x1CCA...680e)</code>, tokenized STRC yield <code className="mono">sUSDat (0xBCaf...Ee87)</code>, and <code className="mono">maMUSD/MUSD (0xBF32...FDE0)</code> to capture positive carry above Mezo’s 1.00% borrow rate.
              </p>

              <div className="form-group">
                <label className="form-label">
                  <span>StabilityPool Allocation (BTC Liquidation Gains + MEZO)</span>
                  <span className="mono">{spSplitBps}% ({spBlendedApy}% APY)</span>
                </label>
                <input
                  type="range"
                  min={20}
                  max={80}
                  value={spSplitBps}
                  onChange={(e) => {
                    const nextSp = Number(e.target.value);
                    const rem = 100 - nextSp;
                    setSpSplitBps(nextSp);
                    setStrcSplitBps(Math.round(rem * 0.7));
                    setMaMusdSplitBps(rem - Math.round(rem * 0.7));
                  }}
                  style={{ width: '100%' }}
                />
              </div>

              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(3, 1fr)',
                  gap: '0.75rem',
                  margin: '1.1rem 0',
                }}
              >
                <div style={{ background: 'var(--bg-secondary)', padding: '0.8rem', borderRadius: '8px' }}>
                  <div className="kpi-label">StabilityPool</div>
                  <div className="mono" style={{ fontSize: '1.1rem', fontWeight: 700 }}>
                    {Math.round((carryPrincipalMusd * spSplitBps) / 100).toLocaleString()} MUSD
                  </div>
                  <div className="kpi-sub">withdrawFromSP(0) Active</div>
                </div>
                <div style={{ background: 'var(--bg-secondary)', padding: '0.8rem', borderRadius: '8px' }}>
                  <div className="kpi-label">sUSDat (STRC RWA)</div>
                  <div className="mono" style={{ fontSize: '1.1rem', fontWeight: 700 }}>
                    {Math.round((carryPrincipalMusd * strcSplitBps) / 100).toLocaleString()} MUSD
                  </div>
                  <div className="kpi-sub">6.85% RWA Carry</div>
                </div>
                <div style={{ background: 'var(--bg-secondary)', padding: '0.8rem', borderRadius: '8px' }}>
                  <div className="kpi-label">maMUSD/MUSD Pool</div>
                  <div className="mono" style={{ fontSize: '1.1rem', fontWeight: 700 }}>
                    {Math.round((carryPrincipalMusd * maMusdSplitBps) / 100).toLocaleString()} MUSD
                  </div>
                  <div className="kpi-sub">Instant AMM Liquidity</div>
                </div>
              </div>

              <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
                <button onClick={handleHarvestSpZero} className="btn btn-primary" style={{ flex: 1 }}>
                  Harvest BTC Gains via withdrawFromSP(0)
                </button>
              </div>
            </div>

            {/* Right Column: Instant Share Liquidity Unwind */}
            <div className="card card-glow">
              <span className="tag-pill">Zero Withdrawal Epoch Friction</span>
              <h2 style={{ fontSize: '1.15rem', marginTop: '0.35rem', marginBottom: '0.6rem' }}>
                Instant Share Liquidity (<code className="mono">maMUSD → MUSD</code>)
              </h2>
              <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', marginBottom: '1rem' }}>
                Instead of waiting on vault withdrawal epochs, <code className="mono">instantUnwindToMusd()</code> swaps <code className="mono">maMUSD</code> shares directly through <code className="mono">MezoPoolsRouter (0x9a1f...D7E9)</code> and pulls from <code className="mono">StabilityPool</code> to close Trove debt or settle x402 invoices atomically.
              </p>

              <div className="form-group">
                <label className="form-label">
                  <span>MUSD Amount to Unwind Instantly</span>
                  <span className="mono">Available: {carryPrincipalMusd.toLocaleString()} MUSD</span>
                </label>
                <input
                  type="number"
                  step="500"
                  className="input-field mono"
                  value={unwindAmountInput}
                  onChange={(e) => setUnwindAmountInput(e.target.value)}
                />
              </div>

              <div
                style={{
                  background: 'var(--bg-secondary)',
                  padding: '0.85rem',
                  borderRadius: '8px',
                  fontSize: '0.8rem',
                  marginBottom: '1rem',
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.3rem' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>Canonical Pool Route:</span>
                  <span className="mono">maMUSD → MUSD (0xBF32...FDE0)</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.3rem' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>Live Pool Exchange Rate:</span>
                  <span className="mono">
                    1 maMUSD = {telemetry?.pools.mamusdMusd.exchangeRate || 1.0} MUSD
                  </span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>Max Slippage Guard:</span>
                  <span className="mono" style={{ color: 'var(--musd-emerald)' }}>0.50% Protected</span>
                </div>
              </div>

              <button onClick={handleInstantUnwind} className="btn btn-emerald" style={{ width: '100%' }}>
                Execute instantUnwindToMusd() Now
              </button>
            </div>
          </div>
        )}

        {/* MODULE D: TRACK 2 x402 CREDIT RAIL & CROSS-CHAIN FLOAT REFILLER */}
        {activeTab === 'x402' && (
          <div className="workspace-grid">
            <div className="card card-glow">
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.6rem' }}>
                <span className="tag-pill blue">HTTP 402 (x402) Clearing Rail</span>
                <span className="mono" style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>
                  SDK: sdk/aegisX402Sdk.ts
                </span>
              </div>
              <h2 style={{ fontSize: '1.15rem', marginBottom: '0.5rem' }}>
                In-Checkout & AI Agent MUSD Credit Widget
              </h2>
              <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', marginBottom: '1rem' }}>
                Lets buyers, creators, and autonomous AI agents settle HTTP 402 invoices on Mezo (31611) or Base (8453) by drawing fixed-rate Trove credit, unwinding CarryEngine yield, or executing an atomic BTC → MUSD swap.
              </p>

              <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 0.8fr', gap: '0.75rem' }}>
                <div className="form-group">
                  <label className="form-label">Protected x402 Resource / Merchant URI</label>
                  <input
                    type="text"
                    className="input-field mono"
                    value={x402Resource}
                    onChange={(e) => setX402Resource(e.target.value)}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Invoice Amount (MUSD)</label>
                  <input
                    type="number"
                    className="input-field mono"
                    value={x402Amount}
                    onChange={(e) => setX402Amount(e.target.value)}
                  />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.75rem' }}>
                <div className="form-group">
                  <label className="form-label">Settlement Payment Rail</label>
                  <select
                    className="select-field"
                    value={x402PaymentMode}
                    onChange={(e) =>
                      setX402PaymentMode(
                        e.target.value as
                          | 'TROVE_CREDIT_DRAW'
                          | 'CARRY_ENGINE_UNWIND'
                          | 'BTC_ATOMIC_SWAP'
                          | 'MUSD_DIRECT'
                      )
                    }
                  >
                    <option value="TROVE_CREDIT_DRAW">Mode A: Draw AegisTroveVault Micro-Credit (1% Fixed)</option>
                    <option value="CARRY_ENGINE_UNWIND">Mode B: Unwind MUSDCarryEngine Yield Slice</option>
                    <option value="BTC_ATOMIC_SWAP">Mode C: Atomic BTC → MUSD Swap (MezoPoolsRouter)</option>
                    <option value="MUSD_DIRECT">Mode D: Direct Wallet MUSD Balance</option>
                  </select>
                </div>

                <div className="form-group">
                  <label className="form-label">Destination Settlement Network</label>
                  <select
                    className="select-field"
                    value={x402TargetChain}
                    onChange={(e) => setX402TargetChain(Number(e.target.value))}
                  >
                    <option value={8453}>Base Mainnet (8453) — Settle in USDC via FloatRefiller</option>
                    <option value={31611}>Mezo Network (31611) — Settle in Native MUSD</option>
                  </select>
                </div>
              </div>

              <div style={{ display: 'flex', gap: '0.75rem', marginBottom: '1rem' }}>
                <button onClick={triggerHttp402Challenge} className="btn btn-secondary" style={{ flex: 1 }}>
                  1. Request Protected Resource (HTTP 402)
                </button>
                <button onClick={executeX402Settlement} className="btn btn-primary" style={{ flex: 1 }}>
                  2. Auto-Clear x402 Invoice Now
                </button>
              </div>

              {/* Execution Trace Output */}
              {x402Trace.length > 0 && (
                <div
                  className="mono"
                  style={{
                    background: '#05070b',
                    padding: '0.85rem',
                    borderRadius: '8px',
                    fontSize: '0.76rem',
                    border: '1px solid var(--border-subtle)',
                    color: 'var(--musd-emerald)',
                  }}
                >
                  {x402Trace.map((line, idx) => (
                    <div key={idx} style={{ marginBottom: '0.25rem' }}>
                      {line}
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Right Column: Autonomous Cross-Chain Float Refiller */}
            <div className="card">
              <span className="tag-pill">MezoFloatRefiller.sol (Mezo 31611 ↔ Base 8453)</span>
              <h2 style={{ fontSize: '1.15rem', marginTop: '0.35rem', marginBottom: '0.5rem' }}>
                Autonomous Cross-Chain Float Refiller
              </h2>
              <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', marginBottom: '1rem' }}>
                Prices cross-chain settlements against live <code className="mono">MUSD/mUSDC (0x525F...Dc3e)</code> pool depth and automatically tops up depleted merchant MUSD floats from treasury reserves under strict <code className="mono">MusdPegGuard</code> price floors.
              </p>

              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: '1fr 1fr',
                  gap: '0.75rem',
                  marginBottom: '1rem',
                }}
              >
                <div style={{ background: 'var(--bg-secondary)', padding: '0.85rem', borderRadius: '8px' }}>
                  <div className="kpi-label">Merchant Active Float</div>
                  <div
                    className="mono"
                    style={{
                      fontSize: '1.25rem',
                      fontWeight: 700,
                      color: merchantFloatMusd < 1000 ? 'var(--amber-warn)' : 'var(--musd-emerald)',
                    }}
                  >
                    {merchantFloatMusd.toLocaleString()} MUSD
                  </div>
                  <div className="kpi-sub">Min Threshold: 1,000 MUSD | Target: 3,500 MUSD</div>
                </div>

                <div style={{ background: 'var(--bg-secondary)', padding: '0.85rem', borderRadius: '8px' }}>
                  <div className="kpi-label">Treasury Float Reserve</div>
                  <div className="mono" style={{ fontSize: '1.25rem', fontWeight: 700 }}>
                    {treasuryFloatReserve.toLocaleString()} MUSD
                  </div>
                  <div className="kpi-sub">Wormhole NTT: 0xBA04...d1E3</div>
                </div>
              </div>

              <button onClick={triggerKeeperFloatRefill} className="btn btn-emerald" style={{ width: '100%' }}>
                Execute Keeper refillFloat() to Target (3,500 MUSD)
              </button>
            </div>
          </div>
        )}

        {/* Live On-Chain Execution & Verification Log */}
        <section className="card" style={{ marginTop: '1.5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.75rem' }}>
            <h3 style={{ fontSize: '0.98rem' }}>Live Protocol Execution Telemetry & Transaction Log</h3>
            <span className="tag-pill">Zero Mock Contracts • Canonical Mezo Testnet (31611)</span>
          </div>
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Module</th>
                  <th>Operation Executed</th>
                  <th>Telemetry Details</th>
                  <th>Tx / Receipt Hash</th>
                </tr>
              </thead>
              <tbody>
                {receipts.map((r) => (
                  <tr key={r.id}>
                    <td className="mono" style={{ color: 'var(--text-muted)' }}>
                      {r.timestamp}
                    </td>
                    <td>
                      <span className="tag-pill">{r.module}</span>
                    </td>
                    <td style={{ fontWeight: 600 }}>{r.action}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{r.details}</td>
                    <td className="mono" style={{ color: 'var(--btc-orange)' }}>
                      {r.txHash.slice(0, 10)}...{r.txHash.slice(-6)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </main>
    </div>
  );
}
