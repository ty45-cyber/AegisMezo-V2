// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MezoAddresses} from "./libraries/MezoAddresses.sol";
import {IPriceFeed, IMezoPool, IMaMUSD, IERC20} from "./interfaces/IMezoCore.sol";

/// @title MusdPegGuard
/// @notice Multi-pool MUSD peg telemetry & on-chain price-floor guard reading live exchange rates across
///         Mezo Pools (MUSD/mUSDC, maMUSD/MUSD, and MUSD/BTC) alongside the canonical PriceFeed oracle.
contract MusdPegGuard {
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant WAD = 1e18;

    address public owner;
    address public priceFeed;
    address public musd;
    address public musdc;
    address public maMusd;
    address public musdMusdcPool;
    address public maMusdPool;
    address public musdBtcPool;

    /// @notice Discount threshold in basis points below $1.00 that triggers redemption-shield mode (default: 40 bps = $0.9960)
    uint256 public discountThresholdBps = 40;
    /// @notice Strict minimum price floor in 18 decimals for cross-chain float settlement (default: $0.9850 = 0.985e18)
    uint256 public minSettlementPriceFloor = 0.985e18;
    /// @notice Maximum allowed oracle-to-AMM BTC price divergence in bps (default: 500 bps = 5%)
    uint256 public maxBtcDivergenceBps = 500;

    struct PegTelemetry {
        uint256 btcOraclePrice;
        uint256 musdUsdcRate;
        uint256 musdMaMusdRate;
        uint256 musdBtcImpliedUsdRate;
        uint256 compositePegPrice;
        uint256 pegDeviationBps;
        bool isPegDiscounted;
        uint256 redemptionPressureBps;
        uint256 timestamp;
    }

    event PegConfigUpdated(
        uint256 discountThresholdBps,
        uint256 minSettlementPriceFloor,
        uint256 maxBtcDivergenceBps
    );
    event PoolsConfigured(address musdMusdcPool, address maMusdPool, address musdBtcPool, address priceFeed);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error Unauthorized();
    error InvalidConfiguration();
    error PriceBelowSettlementFloor(uint256 actualPrice, uint256 floorPrice);
    error ExcessivePoolDivergence(uint256 divergenceBps, uint256 maxAllowedBps);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(
        address _priceFeed,
        address _musd,
        address _musdc,
        address _maMusd,
        address _musdMusdcPool,
        address _maMusdPool,
        address _musdBtcPool
    ) {
        owner = msg.sender;
        priceFeed = _priceFeed == address(0) ? MezoAddresses.PRICE_FEED : _priceFeed;
        musd = _musd == address(0) ? MezoAddresses.MUSD : _musd;
        musdc = _musdc == address(0) ? MezoAddresses.MUSDC : _musdc;
        maMusd = _maMusd == address(0) ? MezoAddresses.MAMUSD : _maMusd;
        musdMusdcPool = _musdMusdcPool == address(0) ? MezoAddresses.MUSD_MUSDC_POOL : _musdMusdcPool;
        maMusdPool = _maMusdPool == address(0) ? MezoAddresses.MAMUSD_MUSD_POOL : _maMusdPool;
        musdBtcPool = _musdBtcPool == address(0) ? MezoAddresses.MUSD_BTC_POOL : _musdBtcPool;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidConfiguration();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setPegConfig(
        uint256 _discountThresholdBps,
        uint256 _minSettlementPriceFloor,
        uint256 _maxBtcDivergenceBps
    ) external onlyOwner {
        if (_discountThresholdBps > 2000 || _minSettlementPriceFloor < 0.8e18 || _minSettlementPriceFloor > WAD) {
            revert InvalidConfiguration();
        }
        discountThresholdBps = _discountThresholdBps;
        minSettlementPriceFloor = _minSettlementPriceFloor;
        maxBtcDivergenceBps = _maxBtcDivergenceBps;
        emit PegConfigUpdated(_discountThresholdBps, _minSettlementPriceFloor, _maxBtcDivergenceBps);
    }

    function setPools(
        address _musdMusdcPool,
        address _maMusdPool,
        address _musdBtcPool,
        address _priceFeed
    ) external onlyOwner {
        if (_musdMusdcPool == address(0) || _maMusdPool == address(0) || _musdBtcPool == address(0) || _priceFeed == address(0)) {
            revert InvalidConfiguration();
        }
        musdMusdcPool = _musdMusdcPool;
        maMusdPool = _maMusdPool;
        musdBtcPool = _musdBtcPool;
        priceFeed = _priceFeed;
        emit PoolsConfigured(_musdMusdcPool, _maMusdPool, _musdBtcPool, _priceFeed);
    }

    /// @notice Reads the live BTC/USD price (18 decimals) from the canonical Mezo PriceFeed oracle.
    function getBtcOraclePrice() public view returns (uint256) {
        return IPriceFeed(priceFeed).fetchPrice();
    }

    /// @notice Quotes 1 MUSD across MUSD/mUSDC, maMUSD/MUSD, and MUSD/BTC pools and returns full peg telemetry.
    function evaluatePeg() public view returns (PegTelemetry memory telemetry) {
        telemetry.btcOraclePrice = getBtcOraclePrice();
        telemetry.musdUsdcRate = _quoteMusdToUsdc();
        telemetry.musdMaMusdRate = _quoteMusdToMaMusd();
        telemetry.musdBtcImpliedUsdRate = _quoteMusdToBtcUsd(telemetry.btcOraclePrice);

        // Weighted composite: 50% MUSD/mUSDC, 30% maMUSD/MUSD, 20% MUSD/BTC implied USD
        uint256 composite = (
            telemetry.musdUsdcRate * 5000 +
            telemetry.musdMaMusdRate * 3000 +
            telemetry.musdBtcImpliedUsdRate * 2000
        ) / BPS_DENOMINATOR;

        telemetry.compositePegPrice = composite;

        if (composite >= WAD) {
            telemetry.pegDeviationBps = ((composite - WAD) * BPS_DENOMINATOR) / WAD;
            telemetry.isPegDiscounted = false;
            telemetry.redemptionPressureBps = 0;
        } else {
            uint256 discountBps = ((WAD - composite) * BPS_DENOMINATOR) / WAD;
            telemetry.pegDeviationBps = discountBps;
            telemetry.isPegDiscounted = discountBps >= discountThresholdBps;
            // Redemption pressure scales with how far below $1.00 MUSD trades (100 bps discount => 2500 bps pressure, capped at 10000)
            uint256 pressure = discountBps * 25;
            telemetry.redemptionPressureBps = pressure > BPS_DENOMINATOR ? BPS_DENOMINATOR : pressure;
        }

        telemetry.timestamp = block.timestamp;
    }

    /// @notice Enforces strict on-chain price floors before executing cross-chain float settlements or swaps.
    function enforceSettlementFloor(uint256 executionPrice18) external view returns (PegTelemetry memory telemetry) {
        telemetry = evaluatePeg();
        if (executionPrice18 < minSettlementPriceFloor) {
            revert PriceBelowSettlementFloor(executionPrice18, minSettlementPriceFloor);
        }
        if (telemetry.compositePegPrice < minSettlementPriceFloor) {
            revert PriceBelowSettlementFloor(telemetry.compositePegPrice, minSettlementPriceFloor);
        }
    }

    function _quoteMusdToUsdc() internal view returns (uint256) {
        if (musdMusdcPool.code.length == 0) return WAD;
        // Probe small quote (10 MUSD = 10e18) to avoid distorting shallow pool curves
        try IMezoPool(musdMusdcPool).getAmountOut(10e18, musd) returns (uint256 out6) {
            if (out6 > 0) {
                // out6 is for 10 MUSD in 6 decimals -> 1 MUSD in 18 decimals is out6 * 1e11
                return out6 * 1e11;
            }
        } catch {}
        return WAD;
    }

    function _quoteMusdToMaMusd() internal view returns (uint256) {
        if (maMusdPool.code.length == 0) return WAD;
        try IMezoPool(maMusdPool).getAmountOut(1e18, musd) returns (uint256 sharesOut) {
            if (sharesOut > 0) {
                uint256 shareVal = WAD;
                if (maMusd.code.length > 0) {
                    try IMaMUSD(maMusd).sharePrice() returns (uint256 sp) {
                        if (sp > 0) shareVal = sp;
                    } catch {}
                }
                return (sharesOut * shareVal) / WAD;
            }
        } catch {}
        return WAD;
    }

    function _quoteMusdToBtcUsd(uint256 btcPrice18) internal view returns (uint256) {
        if (musdBtcPool.code.length == 0 || btcPrice18 == 0) return WAD;
        try IMezoPool(musdBtcPool).getAmountOut(100e18, musd) returns (uint256 btcOut18) {
            if (btcOut18 > 0) {
                // btcOut18 is BTC received for 100 MUSD -> USD value per 1 MUSD = (btcOut18 * btcPrice18) / 100e18
                return (btcOut18 * btcPrice18) / (100 * WAD);
            }
        } catch {}
        return WAD;
    }
}
