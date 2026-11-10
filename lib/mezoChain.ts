import { defineChain, parseAbi } from "viem";

export const mezoTestnet = defineChain({
  id: 31611,
  name: "Mezo Testnet (Matsnet)",
  nativeCurrency: {
    decimals: 18,
    name: "Bitcoin",
    symbol: "BTC"
  },
  rpcUrls: {
    default: {
      http: ["https://rpc.test.mezo.org"]
    }
  },
  blockExplorers: {
    default: {
      name: "Mezo Testnet Explorer",
      url: "https://explorer.test.mezo.org"
    }
  },
  testnet: true
});

export const mezoMainnet = defineChain({
  id: 31612,
  name: "Mezo Mainnet",
  nativeCurrency: {
    decimals: 18,
    name: "Bitcoin",
    symbol: "BTC"
  },
  rpcUrls: {
    default: {
      http: ["https://rpc-http.mezo.boar.network"]
    }
  },
  blockExplorers: {
    default: {
      name: "Mezo Explorer",
      url: "https://explorer.mezo.org"
    }
  }
});

export const MEZO_CANONICAL_ADDRESSES = {
  // Core MUSD Protocol (Mezo Testnet 31611)
  MUSD: "0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503",
  BORROWER_OPERATIONS: "0xCdF7028ceAB81fA0C6971208e83fa7872994beE5",
  TROVE_MANAGER: "0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0",
  SORTED_TROVES: "0x722E4D24FD6Ff8b0AC679450F3D91294607268fA",
  HINT_HELPERS: "0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6",
  STABILITY_POOL: "0x1CCA7E410eE41739792eA0A24e00349Dd247680e",
  PRICE_FEED: "0x86bCF0841622a5dAC14A313a15f96A95421b9366",
  INTEREST_RATE_MANAGER: "0xD4D6c36A592A2c5e86035A6bca1d57747a567f37",
  ACTIVE_POOL: "0x143A063F62340DA3A8bEA1C5642d18C6D0F7FF51",
  DEFAULT_POOL: "0x59851D252090283f9367c159f0C9036e75483300",
  PCV: "0x4dDD70f4C603b6089c07875Be02fEdFD626b80Af",

  // Mezo Pools, Real Yield (STRC / maMUSD), & Swapper
  MAMUSD: "0xA8BAc7913D5163E2dF9aE3aF5B0AEeA44529Ac70",
  MAMUSD_MUSD_POOL: "0xBF329A2A130cb0D5B5218f1672E51Fb36089FDE0",
  MUSD_MUSDC_POOL: "0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e",
  MUSD_BTC_POOL: "0xd16A5Df82120ED8D626a1a15232bFcE2366d6AA9",
  MUSDC: "0xe1a26db653708A2AD8F824E92Db9852410e33A59",
  MEZO_POOLS_ROUTER: "0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9",
  MEZO_POOLS_FACTORY: "0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A",
  MEZO_POOLS_SWAPPER: "0x219cCC99aB55c001f9c48cEC3740d6a64518bD72",
  SUSDAT: "0xBCaf6f2a7BEfc4Fc64CeeC6D8e4872941d52Ee87",

  // Dual-Token Flywheel (veBTC, veMEZO, Gauges, Splitter)
  BTC_ERC20: "0x7b7C000000000000000000000000000000000000",
  MEZO_ERC20: "0x7B7c000000000000000000000000000000000001",
  VE_BTC: "0x38E35d92E6Bfc6787272A62345856B13eA12130a",
  VE_MEZO: "0xaCE816CA2bcc9b12C59799dcC5A959Fb9b98111b",
  BOOSTER: "0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1",
  VOTER: "0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D",
  SPLITTER: "0x47FbB2e6d3f6EF14AF3553d139e8af6cc92ed51F",

  // Cross-Chain Wormhole NTT
  WORMHOLE_NTT_MANAGER: "0xBA0486fdBbd2FF63Ac55FBB736805785E1BeD1E3",
  WORMHOLE_TRANSCEIVER: "0x770127Bfaf38293583A5dfB6345e5d413E63b4Cd"
} as const;

export const MEZO_CORE_ABIS = {
  priceFeed: parseAbi(["function fetchPrice() view returns (uint256)"]),
  sortedTroves: parseAbi([
    "function getSize() view returns (uint256)",
    "function getFirst() view returns (address)",
    "function getLast() view returns (address)",
    "function getPrev(address _id) view returns (address)",
    "function getNext(address _id) view returns (address)",
    "function contains(address _id) view returns (bool)",
    "function findInsertPosition(uint256 _NICR, address _prevId, address _nextId) view returns (address, address)"
  ]),
  troveManager: parseAbi([
    "function getTroveColl(address _borrower) view returns (uint256)",
    "function getTroveDebt(address _borrower) view returns (uint256)",
    "function getEntireDebtAndColl(address _borrower) view returns (uint256 debt, uint256 coll, uint256 pendingMUSDReward, uint256 pendingCollateralReward)",
    "function getCurrentICR(address _borrower, uint256 _price) view returns (uint256)",
    "function getNominalICR(address _borrower) view returns (uint256)",
    "function getEntireSystemColl() view returns (uint256)",
    "function getEntireSystemDebt() view returns (uint256)"
  ]),
  borrowerOperations: parseAbi([
    "function openTrove(uint256 _debtAmount, address _upperHint, address _lowerHint) payable",
    "function repayMUSD(uint256 _amount, address _upperHint, address _lowerHint)",
    "function addColl(address _upperHint, address _lowerHint) payable",
    "function getBorrowingFee(uint256 _debt) view returns (uint256)",
    "function minNetDebt() view returns (uint256)",
    "function MUSD_GAS_COMPENSATION() view returns (uint256)",
    "function borrowingRate() view returns (uint256)"
  ]),
  hintHelpers: parseAbi([
    "function computeNominalCR(uint256 _coll, uint256 _debt) pure returns (uint256)",
    "function getApproxHint(uint256 _CR, uint256 _numTrials, uint256 _inputRandomSeed) view returns (address hintAddress, uint256 diff, uint256 latestRandomSeed)",
    "function getRedemptionHints(uint256 _amount, uint256 _price, uint256 _maxIterations) view returns (address firstRedemptionHint, uint256 partialRedemptionHintNICR, uint256 truncatedMUSDamount)"
  ]),
  stabilityPool: parseAbi([
    "function provideToSP(uint256 _amount)",
    "function withdrawFromSP(uint256 _amount)",
    "function getTotalMUSDDeposits() view returns (uint256)",
    "function getCollateralBalance() view returns (uint256)",
    "function getCompoundedMUSDDeposit(address _depositor) view returns (uint256)",
    "function getDepositorCollateralGain(address _depositor) view returns (uint256)"
  ]),
  mezoPool: parseAbi([
    "function getReserves() view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast)",
    "function getAmountOut(uint256 amountIn, address tokenIn) view returns (uint256)"
  ]),
  aegisVault: parseAbi([
    "function openAndActivateVault(uint256 debtAmountMusd, uint256 boostLockBtc, uint256 carryDeployPercentBps, address upperHint, address lowerHint) payable returns (address troveProxy, uint256 mintedMusd)",
    "function autonomousRescue(address user, uint256 maxRepayMusd, uint256 maxRadarIterations) returns (uint256 musdRepaid, uint256 icrAfter)",
    "function addCollateralToTrove(address upperHint, address lowerHint) payable",
    "function repayUserTroveDebt(address user, uint256 musdAmount, address upperHint, address lowerHint)"
  ])
};

export const MEZO_TESTNET_ADDRESSES = MEZO_CANONICAL_ADDRESSES;
export const PRICE_FEED_ABI = MEZO_CORE_ABIS.priceFeed;
export const SORTED_TROVES_ABI = MEZO_CORE_ABIS.sortedTroves;
export const TROVE_MANAGER_ABI = MEZO_CORE_ABIS.troveManager;
export const BORROWER_OPERATIONS_ABI = MEZO_CORE_ABIS.borrowerOperations;
export const HINT_HELPERS_ABI = MEZO_CORE_ABIS.hintHelpers;
export const STABILITY_POOL_ABI = MEZO_CORE_ABIS.stabilityPool;
export const MEZO_POOL_ABI = MEZO_CORE_ABIS.mezoPool;
export const AEGIS_TROVE_VAULT_ABI = MEZO_CORE_ABIS.aegisVault;

export const MEZO_FLOAT_REFILLER_ABI = parseAbi([
  "function quoteBtcForExactMusd(uint256 musdOutDesired, uint256 maxSlippageBps) view returns (uint256 btcInRequired, uint256 minMusdOut)",
  "function priceCrossChainSettlement(uint256 musdAmount) view returns (uint256 usdcEquivalent, uint256 rate18, bool safeToSettle)",
  "function payInvoiceWithMusd(bytes32 invoiceId)",
  "function payInvoiceWithVaultCredit(bytes32 invoiceId, bool unwindFromCarry)",
  "function payInvoiceWithAtomicBtcSwap(bytes32 invoiceId, uint256 minMusdOut) payable"
]);

export const MUSD_PEG_GUARD_ABI = parseAbi([
  "function inspectPeg() view returns ((uint256 btcOraclePrice, uint256 musdToMusdcRate, uint256 musdToMaMusdRate, uint256 musdBtcImpliedRate, uint256 compositePegPrice, uint256 pegDeviationBps, bool isPegDiscounted, uint256 redemptionPressureBps))"
]);

export const ERC20_ABI = parseAbi([
  "function balanceOf(address account) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transfer(address to, uint256 amount) returns (bool)"
]);
