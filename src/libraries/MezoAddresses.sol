// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MezoAddresses
/// @notice Canonical live contract addresses on Mezo Testnet (Matsnet, chainId: 31611) & Mainnet (chainId: 31612).
/// @dev Zero Mock Policy: Every address is verified against the canonical Mezo on-chain state.
library MezoAddresses {
    uint256 public constant MEZO_TESTNET_CHAIN_ID = 31611;
    uint256 public constant MEZO_MAINNET_CHAIN_ID = 31612;
    uint256 public constant BASE_MAINNET_CHAIN_ID = 8453;

    // =========================================================================
    // 1. Canonical MUSD Core Protocol (Mezo Testnet 31611)
    // =========================================================================
    address public constant MUSD = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address public constant BORROWER_OPERATIONS = 0xCdF7028ceAB81fA0C6971208e83fa7872994beE5;
    address public constant TROVE_MANAGER = 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0;
    address public constant SORTED_TROVES = 0x722E4D24FD6Ff8b0AC679450F3D91294607268fA;
    address public constant HINT_HELPERS = 0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6;
    address public constant STABILITY_POOL = 0x1CCA7E410eE41739792eA0A24e00349Dd247680e;
    address public constant PRICE_FEED = 0x86bCF0841622a5dAC14A313a15f96A95421b9366;
    address public constant INTEREST_RATE_MANAGER = 0xD4D6c36A592A2c5e86035A6bca1d57747a567f37;
    address public constant ACTIVE_POOL = 0x143A063F62340DA3A8bEA1C5642d18C6D0F7FF51;
    address public constant DEFAULT_POOL = 0x59851D252090283f9367c159f0C9036e75483300;
    address public constant COLL_SURPLUS_POOL = 0xB4C35747c26E4aB5F1a7CdC7E875B5946eFa6fa9;
    address public constant PCV = 0x4dDD70f4C603b6089c07875Be02fEdFD626b80Af;
    address public constant GAS_POOL = 0x8fa3EF45137C3AFF337e42f98023C1D7dd3666C0;
    address public constant BORROWER_OPS_SIGNATURES = 0xD757e3646AF370b15f32EB557F0F8380Df7D639e;

    // =========================================================================
    // 2. Canonical Mezo Pools, Real Yield (STRC / maMUSD), & Swapper
    // =========================================================================
    address public constant MAMUSD = 0xA8BAc7913D5163E2dF9aE3aF5B0AEeA44529Ac70;
    address public constant MAMUSD_MUSD_POOL = 0xBF329A2A130cb0D5B5218f1672E51Fb36089FDE0;
    address public constant MUSD_MUSDC_POOL = 0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e;
    address public constant MUSD_BTC_POOL = 0xd16A5Df82120ED8D626a1a15232bFcE2366d6AA9;
    address public constant MUSDC = 0xe1a26db653708A2AD8F824E92Db9852410e33A59;
    address public constant MEZO_POOLS_ROUTER = 0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9;
    address public constant MEZO_POOLS_FACTORY = 0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A;
    address public constant MEZO_POOLS_SWAPPER = 0x219cCC99aB55c001f9c48cEC3740d6a64518bD72;
    address public constant SUSDAT = 0xBCaf6f2a7BEfc4Fc64CeeC6D8e4872941d52Ee87;

    // =========================================================================
    // 3. Canonical Dual-Token Flywheel (veBTC, veMEZO, Gauges, Splitter)
    // =========================================================================
    address public constant BTC_ERC20 = 0x7b7C000000000000000000000000000000000000;
    address public constant MEZO_ERC20 = 0x7B7c000000000000000000000000000000000001;
    address public constant VE_BTC = 0x38E35d92E6Bfc6787272A62345856B13eA12130a;
    address public constant VE_MEZO = 0xaCE816CA2bcc9b12C59799dcC5A959Fb9b98111b;
    address public constant BOOSTER = 0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1;
    address public constant VOTER = 0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D;
    address public constant SPLITTER = 0x47FbB2e6d3f6EF14AF3553d139e8af6cc92ed51F;

    // =========================================================================
    // 4. Canonical Cross-Chain Settlement (Wormhole NTT)
    // =========================================================================
    address public constant WORMHOLE_NTT_MANAGER = 0xBA0486fdBbd2FF63Ac55FBB736805785E1BeD1E3;
    address public constant WORMHOLE_TRANSCEIVER = 0x770127Bfaf38293583A5dfB6345e5d413E63b4Cd;
}
