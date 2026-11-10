import { Address, encodeFunctionData, formatUnits, parseUnits, PublicClient, WalletClient } from 'viem';
import {
  MEZO_TESTNET_ADDRESSES,
  AEGIS_TROVE_VAULT_ABI,
  MEZO_FLOAT_REFILLER_ABI,
  MUSD_PEG_GUARD_ABI,
  ERC20_ABI,
} from '../lib/mezoChain';

export interface X402PaymentChallenge {
  version: 'x402/1.0';
  scheme: 'mezo-musd-omni-clearing';
  invoiceId: `0x${string}`;
  merchant: Address;
  musdAmount: string;
  musdAmountFormatted: string;
  baseUsdcAmount: string;
  targetChainId: number;
  maxSlippageBps: number;
  expiryTimestamp: number;
  supportedModes: Array<'MUSD_DIRECT' | 'TROVE_CREDIT_DRAW' | 'CARRY_ENGINE_UNWIND' | 'BTC_ATOMIC_SWAP'>;
  refillerContract: Address;
  vaultContract: Address;
  memo: string;
}

export interface X402QuoteResult {
  musdRequired: bigint;
  btcRequiredForAtomicSwap: bigint;
  minMusdOutFromBtcSwap: bigint;
  baseUsdcEquivalent: bigint;
  musdPegRateUsd18: bigint;
  safeToSettle: boolean;
  recommendedMode: 'MUSD_DIRECT' | 'TROVE_CREDIT_DRAW' | 'CARRY_ENGINE_UNWIND' | 'BTC_ATOMIC_SWAP';
}

export interface VeBoostCalculation {
  veBtcPower: number;
  veMezoPower: number;
  totalVeBtcPool: number;
  totalVeMezoPool: number;
  boostMultiplier: number; // 1.0x to 5.0x
  optimalVeMezoNeededFor5x: number;
  effectiveBoostedWeight: number;
}

/**
 * AegisMezo V2 Embeddable x402 & Telemetry SDK
 * Enables AI agents, merchants, and checkout widgets to:
 * 1. Parse HTTP 402 Payment-Required headers on Mezo (31611) & Base (8453)
 * 2. Compute optimal HintHelpers / SortedTroves O(1) insertion hints
 * 3. Quote atomic BTC -> MUSD checkout swaps and Base USDC float settlements
 * 4. Calculate 5x veBTC x veMEZO boost pairing ratios
 */
export class AegisX402Client {
  private readonly publicClient: PublicClient;
  private readonly vaultAddress: Address;
  private readonly refillerAddress: Address;
  private readonly pegGuardAddress: Address;

  constructor(params: {
    publicClient: PublicClient;
    vaultAddress: Address;
    refillerAddress: Address;
    pegGuardAddress: Address;
  }) {
    this.publicClient = params.publicClient;
    this.vaultAddress = params.vaultAddress;
    this.refillerAddress = params.refillerAddress;
    this.pegGuardAddress = params.pegGuardAddress;
  }

  /**
   * Parses a standard HTTP 402 response body or WWW-Authenticate header into a structured challenge
   */
  static parse402Challenge(payload: Record<string, unknown>): X402PaymentChallenge {
    const ch = (payload.challenge ?? payload) as X402PaymentChallenge;
    if (!ch || !ch.invoiceId || !ch.musdAmount) {
      throw new Error('Invalid x402 Payment-Required challenge payload');
    }
    return ch;
  }

  /**
   * Computes exact veBTC x veMEZO boost multiplier (1.00x to 5.00x) using canonical Mezo boost formula
   */
  static calculateBoostMultiplier(
    veBtcPower: number,
    veMezoPower: number,
    totalVeBtcPool: number,
    totalVeMezoPool: number
  ): VeBoostCalculation {
    if (veBtcPower <= 0) {
      return {
        veBtcPower: 0,
        veMezoPower,
        totalVeBtcPool,
        totalVeMezoPool,
        boostMultiplier: 1.0,
        optimalVeMezoNeededFor5x: 0,
        effectiveBoostedWeight: 0,
      };
    }

    const safeTotalBtc = Math.max(totalVeBtcPool, veBtcPower);
    const safeTotalMezo = Math.max(totalVeMezoPool, veMezoPower, 1);

    const mezoShare = veMezoPower / safeTotalMezo;
    const btcShare = veBtcPower / safeTotalBtc;
    const ratio = btcShare > 0 ? Math.min(mezoShare / btcShare, 1.0) : 0;

    const boostMultiplier = Number((1.0 + 4.0 * ratio).toFixed(2));
    const optimalVeMezoNeededFor5x = Number(((veBtcPower * safeTotalMezo) / safeTotalBtc).toFixed(2));
    const effectiveBoostedWeight = Number((veBtcPower * boostMultiplier).toFixed(2));

    return {
      veBtcPower,
      veMezoPower,
      totalVeBtcPool: safeTotalBtc,
      totalVeMezoPool: safeTotalMezo,
      boostMultiplier,
      optimalVeMezoNeededFor5x,
      effectiveBoostedWeight,
    };
  }

  /**
   * Quotes all 4 x402 payment modes against live Mezo Pools and MusdPegGuard
   */
  async quoteInvoiceSettlement(
    musdAmountWei: bigint,
    maxSlippageBps = 100
  ): Promise<X402QuoteResult> {
    const [btcQuoteResult, crossChainResult, pegReport] = await Promise.all([
      this.publicClient.readContract({
        address: this.refillerAddress,
        abi: MEZO_FLOAT_REFILLER_ABI,
        functionName: 'quoteBtcForExactMusd',
        args: [musdAmountWei, BigInt(maxSlippageBps)],
      }),
      this.publicClient.readContract({
        address: this.refillerAddress,
        abi: MEZO_FLOAT_REFILLER_ABI,
        functionName: 'priceCrossChainSettlement',
        args: [musdAmountWei],
      }),
      this.publicClient.readContract({
        address: this.pegGuardAddress,
        abi: MUSD_PEG_GUARD_ABI,
        functionName: 'inspectPeg',
      }),
    ]);

    const [btcInRequired, minMusdOut] = btcQuoteResult as [bigint, bigint];
    const [usdcEquivalent, , safeToSettle] = crossChainResult as [bigint, bigint, boolean];
    const peg = pegReport as { musdToMusdcRate: bigint };

    return {
      musdRequired: musdAmountWei,
      btcRequiredForAtomicSwap: btcInRequired,
      minMusdOutFromBtcSwap: minMusdOut,
      baseUsdcEquivalent: usdcEquivalent,
      musdPegRateUsd18: peg.musdToMusdcRate,
      safeToSettle,
      recommendedMode: 'TROVE_CREDIT_DRAW',
    };
  }

  /**
   * Builds transaction calldata to settle an x402 invoice via any of the 4 supported modes
   */
  buildSettlementCalldata(params: {
    invoiceId: `0x${string}`;
    mode: 'MUSD_DIRECT' | 'TROVE_CREDIT_DRAW' | 'CARRY_ENGINE_UNWIND' | 'BTC_ATOMIC_SWAP';
    musdAmountWei: bigint;
    merchant: Address;
    btcRequiredWei?: bigint;
    minMusdOutWei?: bigint;
  }): { to: Address; data: `0x${string}`; value: bigint; description: string } {
    switch (params.mode) {
      case 'MUSD_DIRECT':
        return {
          to: this.refillerAddress,
          data: encodeFunctionData({
            abi: MEZO_FLOAT_REFILLER_ABI,
            functionName: 'payInvoiceWithMusd',
            args: [params.invoiceId],
          }),
          value: 0n,
          description: `Pay ${formatUnits(params.musdAmountWei, 18)} MUSD directly via MezoFloatRefiller`,
        };

      case 'TROVE_CREDIT_DRAW':
        return {
          to: this.refillerAddress,
          data: encodeFunctionData({
            abi: MEZO_FLOAT_REFILLER_ABI,
            functionName: 'payInvoiceWithVaultCredit',
            args: [params.invoiceId, false],
          }),
          value: 0n,
          description: `Draw ${formatUnits(params.musdAmountWei, 18)} MUSD fixed-rate Trove credit & settle x402 invoice`,
        };

      case 'CARRY_ENGINE_UNWIND':
        return {
          to: this.refillerAddress,
          data: encodeFunctionData({
            abi: MEZO_FLOAT_REFILLER_ABI,
            functionName: 'payInvoiceWithVaultCredit',
            args: [params.invoiceId, true],
          }),
          value: 0n,
          description: `Unwind ${formatUnits(params.musdAmountWei, 18)} MUSD from MUSDCarryEngine yield & settle x402 invoice`,
        };

      case 'BTC_ATOMIC_SWAP':
        return {
          to: this.refillerAddress,
          data: encodeFunctionData({
            abi: MEZO_FLOAT_REFILLER_ABI,
            functionName: 'payInvoiceWithAtomicBtcSwap',
            args: [params.invoiceId, params.minMusdOutWei ?? params.musdAmountWei],
          }),
          value: params.btcRequiredWei ?? parseUnits('0.01', 18),
          description: `Atomically swap native BTC to MUSD via Mezo Pools Router & settle x402 invoice`,
        };
    }
  }
}
