// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MezoAddresses} from "../src/libraries/MezoAddresses.sol";
import {MusdPegGuard} from "../src/MusdPegGuard.sol";
import {MUSDCarryEngine} from "../src/MUSDCarryEngine.sol";
import {MezoBoostExchange} from "../src/MezoBoostExchange.sol";
import {AegisTroveVault} from "../src/AegisTroveVault.sol";
import {MezoFloatRefiller} from "../src/MezoFloatRefiller.sol";

/// @title DeployAegisMezoV2
/// @notice Canonical deployment script for AegisMezo V2 on Mezo Testnet (chainId: 31611) & Mainnet.
///         Binds exclusively to live canonical Mezo sponsor contracts (Zero Mock Policy).
contract DeployAegisMezoV2 is Script {
    struct Deployment {
        MusdPegGuard pegGuard;
        MUSDCarryEngine carryEngine;
        MezoBoostExchange boostExchange;
        AegisTroveVault aegisVault;
        MezoFloatRefiller floatRefiller;
    }

    function run() external returns (Deployment memory d) {
        vm.startBroadcast();
        d = deploySystem();
        vm.stopBroadcast();

        console2.log("=== AegisMezo V2 Canonical Deployment (Chain ID: %d) ===", block.chainid);
        console2.log("MusdPegGuard:      ", address(d.pegGuard));
        console2.log("MUSDCarryEngine:   ", address(d.carryEngine));
        console2.log("MezoBoostExchange: ", address(d.boostExchange));
        console2.log("AegisTroveVault:   ", address(d.aegisVault));
        console2.log("MezoFloatRefiller: ", address(d.floatRefiller));
    }

    function deploySystem() public returns (Deployment memory d) {
        d.pegGuard = new MusdPegGuard(
            MezoAddresses.PRICE_FEED,
            MezoAddresses.MUSD,
            MezoAddresses.MUSDC,
            MezoAddresses.MAMUSD,
            MezoAddresses.MUSD_MUSDC_POOL,
            MezoAddresses.MAMUSD_MUSD_POOL,
            MezoAddresses.MUSD_BTC_POOL
        );

        d.carryEngine = new MUSDCarryEngine(
            MezoAddresses.MUSD,
            MezoAddresses.STABILITY_POOL,
            MezoAddresses.MAMUSD,
            MezoAddresses.MAMUSD_MUSD_POOL,
            MezoAddresses.MEZO_POOLS_ROUTER,
            MezoAddresses.MEZO_POOLS_FACTORY,
            MezoAddresses.MEZO_POOLS_SWAPPER,
            MezoAddresses.SUSDAT
        );

        d.boostExchange = new MezoBoostExchange(
            MezoAddresses.MUSD,
            MezoAddresses.BTC_ERC20,
            MezoAddresses.MEZO_ERC20,
            MezoAddresses.VE_BTC,
            MezoAddresses.VE_MEZO,
            MezoAddresses.BOOSTER,
            MezoAddresses.VOTER,
            MezoAddresses.SPLITTER
        );

        d.aegisVault = new AegisTroveVault(
            MezoAddresses.MUSD,
            MezoAddresses.BORROWER_OPERATIONS,
            MezoAddresses.TROVE_MANAGER,
            MezoAddresses.SORTED_TROVES,
            MezoAddresses.HINT_HELPERS,
            MezoAddresses.PRICE_FEED,
            address(d.pegGuard),
            payable(address(d.carryEngine)),
            payable(address(d.boostExchange))
        );

        d.floatRefiller = new MezoFloatRefiller(
            MezoAddresses.MUSD,
            MezoAddresses.MUSDC,
            MezoAddresses.MUSD_MUSDC_POOL,
            MezoAddresses.MUSD_BTC_POOL,
            MezoAddresses.MEZO_POOLS_ROUTER,
            MezoAddresses.MEZO_POOLS_SWAPPER,
            MezoAddresses.PRICE_FEED,
            MezoAddresses.WORMHOLE_NTT_MANAGER,
            address(d.pegGuard),
            payable(address(d.aegisVault)),
            payable(address(d.carryEngine))
        );

        // Wire cross-module authorizations
        d.carryEngine.setAuthorizedModules(address(d.aegisVault), address(d.floatRefiller));
        d.boostExchange.setAegisVault(address(d.aegisVault));
        d.aegisVault.setFloatRefiller(address(d.floatRefiller));
    }
}
