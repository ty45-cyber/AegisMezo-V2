import { NextResponse } from 'next/server';
import { createPublicClient, formatUnits, http } from 'viem';
import {
  mezoTestnet,
  MEZO_TESTNET_ADDRESSES,
  PRICE_FEED_ABI,
  SORTED_TROVES_ABI,
  TROVE_MANAGER_ABI,
  STABILITY_POOL_ABI,
  MEZO_POOL_ABI,
  BORROWER_OPERATIONS_ABI,
} from '../../../lib/mezoChain';

export const dynamic = 'force-dynamic';

const publicClient = createPublicClient({
  chain: mezoTestnet,
  transport: http('https://rpc.test.mezo.org', { timeout: 12_000 }),
});

export async function GET() {
  try {
    const [
      blockNumber,
      btcPriceWei,
      queueSize,
      firstTrove,
      lastTrove,
      spTotalMusd,
      spTotalBtcGains,
      borrowingRate,
      minNetDebt,
      mamusdReserves,
      musdcReserves,
      btcPoolReserves,
    ] = await Promise.all([
      publicClient.getBlockNumber(),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.PRICE_FEED,
        abi: PRICE_FEED_ABI,
        functionName: 'fetchPrice',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.SORTED_TROVES,
        abi: SORTED_TROVES_ABI,
        functionName: 'getSize',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.SORTED_TROVES,
        abi: SORTED_TROVES_ABI,
        functionName: 'getFirst',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.SORTED_TROVES,
        abi: SORTED_TROVES_ABI,
        functionName: 'getLast',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.STABILITY_POOL,
        abi: STABILITY_POOL_ABI,
        functionName: 'getTotalMUSDDeposits',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.STABILITY_POOL,
        abi: STABILITY_POOL_ABI,
        functionName: 'getCollateralBalance',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.BORROWER_OPERATIONS,
        abi: BORROWER_OPERATIONS_ABI,
        functionName: 'borrowingRate',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.BORROWER_OPERATIONS,
        abi: BORROWER_OPERATIONS_ABI,
        functionName: 'minNetDebt',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.MAMUSD_MUSD_POOL,
        abi: MEZO_POOL_ABI,
        functionName: 'getReserves',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.MUSD_MUSDC_POOL,
        abi: MEZO_POOL_ABI,
        functionName: 'getReserves',
      }),
      publicClient.readContract({
        address: MEZO_TESTNET_ADDRESSES.MUSD_BTC_POOL,
        abi: MEZO_POOL_ABI,
        functionName: 'getReserves',
      }),
    ]);

    // Walk the bottom 6 Troves from the redemption front-line (SortedTroves tail -> prev)
    const frontLineNodes: Array<{
      rankFromFront: number;
      owner: string;
      icrPct: number;
      debtMusd: number;
      collBtc: number;
      cumulativeMusdAhead: number;
    }> = [];

    let cursor = lastTrove;
    let cumulativeDebt = 0;

    for (let i = 0; i < 6 && cursor && cursor !== '0x0000000000000000000000000000000000000000'; i++) {
      const [icr, debtAndColl, prevNode] = await Promise.all([
        publicClient.readContract({
          address: MEZO_TESTNET_ADDRESSES.TROVE_MANAGER,
          abi: TROVE_MANAGER_ABI,
          functionName: 'getCurrentICR',
          args: [cursor, btcPriceWei],
        }),
        publicClient.readContract({
          address: MEZO_TESTNET_ADDRESSES.TROVE_MANAGER,
          abi: TROVE_MANAGER_ABI,
          functionName: 'getEntireDebtAndColl',
          args: [cursor],
        }),
        publicClient.readContract({
          address: MEZO_TESTNET_ADDRESSES.SORTED_TROVES,
          abi: SORTED_TROVES_ABI,
          functionName: 'getPrev',
          args: [cursor],
        }),
      ]);

      const debtMusd = Number(formatUnits(debtAndColl[0], 18));
      const collBtc = Number(formatUnits(debtAndColl[1], 18));
      const icrPct = Number((Number(formatUnits(icr, 18)) * 100).toFixed(2));

      frontLineNodes.push({
        rankFromFront: i + 1,
        owner: cursor,
        icrPct,
        debtMusd: Number(debtMusd.toFixed(2)),
        collBtc: Number(collBtc.toFixed(6)),
        cumulativeMusdAhead: Number(cumulativeDebt.toFixed(2)),
      });

      cumulativeDebt += debtMusd;
      cursor = prevNode;
    }

    const btcPriceUsd = Number(formatUnits(btcPriceWei, 18));
    const musdPoolRes = Number(formatUnits(musdcReserves[0], 18));
    const musdcPoolRes = Number(formatUnits(musdcReserves[1], 6));
    const mamusdPoolMUSD = Number(formatUnits(mamusdReserves[0], 18));
    const mamusdPoolShares = Number(formatUnits(mamusdReserves[1], 18));
    const btcPoolMusd = Number(formatUnits(btcPoolReserves[0], 18));
    const btcPoolBtc = Number(formatUnits(btcPoolReserves[1], 18));

    return NextResponse.json({
      ok: true,
      chainId: 31611,
      network: 'Mezo Testnet (Matsnet)',
      blockNumber: Number(blockNumber),
      timestamp: new Date().toISOString(),
      oracle: {
        priceFeedAddress: MEZO_TESTNET_ADDRESSES.PRICE_FEED,
        btcPriceUsd: Number(btcPriceUsd.toFixed(2)),
        btcPriceWei: btcPriceWei.toString(),
      },
      sortedTroves: {
        address: MEZO_TESTNET_ADDRESSES.SORTED_TROVES,
        hintHelpersAddress: MEZO_TESTNET_ADDRESSES.HINT_HELPERS,
        totalActiveTroves: Number(queueSize),
        headSafestTrove: firstTrove,
        tailRedemptionFrontRunner: lastTrove,
        frontLineRadar: frontLineNodes,
      },
      stabilityPool: {
        address: MEZO_TESTNET_ADDRESSES.STABILITY_POOL,
        totalMusdDeposits: Number(Number(formatUnits(spTotalMusd, 18)).toFixed(2)),
        totalBtcLiquidationGains: Number(Number(formatUnits(spTotalBtcGains, 18)).toFixed(6)),
      },
      borrowerParams: {
        address: MEZO_TESTNET_ADDRESSES.BORROWER_OPERATIONS,
        borrowingRatePct: Number((Number(formatUnits(borrowingRate, 18)) * 100).toFixed(2)),
        minNetDebtMusd: Number(formatUnits(minNetDebt, 18)),
      },
      pools: {
        mamusdMusd: {
          address: MEZO_TESTNET_ADDRESSES.MAMUSD_MUSD_POOL,
          musdReserve: Number(mamusdPoolMUSD.toFixed(2)),
          mamusdReserve: Number(mamusdPoolShares.toFixed(2)),
          exchangeRate: mamusdPoolMUSD > 0 ? Number((mamusdPoolShares / mamusdPoolMUSD).toFixed(4)) : 1.0,
        },
        musdMusdc: {
          address: MEZO_TESTNET_ADDRESSES.MUSD_MUSDC_POOL,
          musdReserve: Number(musdPoolRes.toFixed(2)),
          musdcReserve: Number(musdcPoolRes.toFixed(2)),
          impliedPegUsd: 1.0,
        },
        musdBtc: {
          address: MEZO_TESTNET_ADDRESSES.MUSD_BTC_POOL,
          musdReserve: Number(btcPoolMusd.toFixed(2)),
          btcReserve: Number(btcPoolBtc.toFixed(4)),
        },
      },
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Telemetry RPC error';
    return NextResponse.json(
      { ok: false, error: message },
      { status: 500 }
    );
  }
}
