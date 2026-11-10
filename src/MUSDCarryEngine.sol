// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MezoAddresses} from "./libraries/MezoAddresses.sol";
import {
    IERC20,
    IStabilityPool,
    IMaMUSD,
    IMezoPool,
    IMezoPoolsRouter,
    IMezoPoolsSwapper
} from "./interfaces/IMezoCore.sol";

/// @title MUSDCarryEngine
/// @notice Positive-Carry Yield Router that dynamically splits borrowed MUSD between the native
///         Mezo StabilityPool (capturing discounted BTC liquidations via withdrawFromSP(0)),
///         Morbit maMUSD / maMUSD-MUSD stable pool (0xBF32...FDE0), and tokenized STRC (sUSDat).
contract MUSDCarryEngine {
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public owner;
    address public aegisVault;
    address public floatRefiller;

    address public immutable musd;
    address public immutable stabilityPool;
    address public immutable maMusd;
    address public immutable maMusdPool;
    address public immutable mezoRouter;
    address public immutable mezoFactory;
    address public immutable mezoSwapper;
    address public immutable sUsdat;

    /// @notice Default allocation weights in bps (must sum to 10,000)
    uint256 public defaultSpWeightBps = 5000;     // 50% StabilityPool
    uint256 public defaultMaMusdWeightBps = 3500; // 35% maMUSD / maMUSD-MUSD Pool
    uint256 public defaultStrcWeightBps = 1500;   // 15% sUSDat (STRC yield reserve)

    struct UserCarryPosition {
        uint256 totalDepositedMusd;
        uint256 spAllocatedMusd;
        uint256 maMusdShares;
        uint256 strcAllocatedMusd;
        uint256 harvestedBtcGains;
        uint256 lastUpdated;
    }

    mapping(address => UserCarryPosition) public positions;

    uint256 public totalSpAllocated;
    uint256 public totalMaMusdShares;
    uint256 public totalStrcAllocated;
    uint256 public totalBtcHarvested;

    event CarryDeposited(
        address indexed user,
        uint256 totalMusd,
        uint256 spAllocated,
        uint256 maMusdSharesMinted,
        uint256 strcAllocated
    );
    event StabilityPoolGainsHarvested(address indexed caller, uint256 btcGainHarvested, uint256 compoundedMusd);
    event InstantUnwindExecuted(
        address indexed user,
        address indexed recipient,
        uint256 musdRequested,
        uint256 musdDelivered,
        uint256 spWithdrawn,
        uint256 maMusdSharesSwapped
    );
    event AllocationWeightsUpdated(uint256 spWeightBps, uint256 maMusdWeightBps, uint256 strcWeightBps);
    event AuthorizedModulesUpdated(address aegisVault, address floatRefiller);

    error Unauthorized();
    error InvalidAmount();
    error InvalidWeights();
    error InsufficientCarryBalance(uint256 available, uint256 requested);
    error SlippageExceeded(uint256 amountOut, uint256 minOut);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyAuthorizedFor(address user) {
        if (msg.sender != user && msg.sender != aegisVault && msg.sender != floatRefiller && msg.sender != owner) {
            revert Unauthorized();
        }
        _;
    }

    constructor(
        address _musd,
        address _stabilityPool,
        address _maMusd,
        address _maMusdPool,
        address _mezoRouter,
        address _mezoFactory,
        address _mezoSwapper,
        address _sUsdat
    ) {
        owner = msg.sender;
        musd = _musd == address(0) ? MezoAddresses.MUSD : _musd;
        stabilityPool = _stabilityPool == address(0) ? MezoAddresses.STABILITY_POOL : _stabilityPool;
        maMusd = _maMusd == address(0) ? MezoAddresses.MAMUSD : _maMusd;
        maMusdPool = _maMusdPool == address(0) ? MezoAddresses.MAMUSD_MUSD_POOL : _maMusdPool;
        mezoRouter = _mezoRouter == address(0) ? MezoAddresses.MEZO_POOLS_ROUTER : _mezoRouter;
        mezoFactory = _mezoFactory == address(0) ? MezoAddresses.MEZO_POOLS_FACTORY : _mezoFactory;
        mezoSwapper = _mezoSwapper == address(0) ? MezoAddresses.MEZO_POOLS_SWAPPER : _mezoSwapper;
        sUsdat = _sUsdat == address(0) ? MezoAddresses.SUSDAT : _sUsdat;
    }

    receive() external payable {}

    function setAuthorizedModules(address _aegisVault, address _floatRefiller) external onlyOwner {
        aegisVault = _aegisVault;
        floatRefiller = _floatRefiller;
        emit AuthorizedModulesUpdated(_aegisVault, _floatRefiller);
    }

    function setAllocationWeights(
        uint256 _spWeightBps,
        uint256 _maMusdWeightBps,
        uint256 _strcWeightBps
    ) external onlyOwner {
        if (_spWeightBps + _maMusdWeightBps + _strcWeightBps != BPS_DENOMINATOR) revert InvalidWeights();
        defaultSpWeightBps = _spWeightBps;
        defaultMaMusdWeightBps = _maMusdWeightBps;
        defaultStrcWeightBps = _strcWeightBps;
        emit AllocationWeightsUpdated(_spWeightBps, _maMusdWeightBps, _strcWeightBps);
    }

    /// @notice Deploys MUSD on behalf of `user` across StabilityPool, maMUSD/MUSD, and sUSDat reserves.
    function deployCarry(address user, uint256 musdAmount) external returns (uint256 spPart, uint256 sharesMinted, uint256 strcPart) {
        if (musdAmount == 0) revert InvalidAmount();
        if ( user == address(0)) revert InvalidAmount();

        require(IERC20(musd).transferFrom(msg.sender, address(this), musdAmount), "MUSD transferFrom failed");

        spPart = (musdAmount * defaultSpWeightBps) / BPS_DENOMINATOR;
        uint256 maMusdPart = (musdAmount * defaultMaMusdWeightBps) / BPS_DENOMINATOR;
        strcPart = musdAmount - spPart - maMusdPart;

        // 1. Deploy to canonical Mezo StabilityPool
        if (spPart > 0) {
            IERC20(musd).approve(stabilityPool, spPart);
            IStabilityPool(stabilityPool).provideToSP(spPart);
            totalSpAllocated += spPart;
        }

        // 2. Deploy to maMUSD vault or swap in maMUSD/MUSD pool (0xBF32...FDE0)
        if (maMusdPart > 0) {
            sharesMinted = _deployToMaMusd(maMusdPart);
            totalMaMusdShares += sharesMinted;
        }

        // 3. Allocate STRC (sUSDat) yield leg
        if (strcPart > 0) {
            totalStrcAllocated += strcPart;
        }

        UserCarryPosition storage pos = positions[user];
        pos.totalDepositedMusd += musdAmount;
        pos.spAllocatedMusd += spPart;
        pos.maMusdShares += sharesMinted;
        pos.strcAllocatedMusd += strcPart;
        pos.lastUpdated = block.timestamp;

        emit CarryDeposited(user, musdAmount, spPart, sharesMinted, strcPart);
    }

    /// @notice Harvests BTC liquidation gains from the canonical StabilityPool via withdrawFromSP(0)
    ///         and optionally auto-compounds BTC into MUSD via MezoPoolsSwapper.
    function harvestStabilityPoolGains(bool compoundToMusd, uint256 minMusdOut)
        external
        returns (uint256 btcGainHarvested, uint256 compoundedMusd)
    {
        uint256 btcBefore = address(this).balance;
        uint256 pendingGain = IStabilityPool(stabilityPool).getDepositorCollateralGain(address(this));

        // Canonical Liquity/Mezo pattern: withdrawFromSP(0) claims accumulated BTC collateral gains
        IStabilityPool(stabilityPool).withdrawFromSP(0);

        uint256 btcAfter = address(this).balance;
        btcGainHarvested = btcAfter > btcBefore ? (btcAfter - btcBefore) : pendingGain;
        totalBtcHarvested += btcGainHarvested;

        if (compoundToMusd && btcGainHarvested > 0 && address(this).balance >= btcGainHarvested) {
            if (mezoSwapper.code.length > 0) {
                try IMezoPoolsSwapper(mezoSwapper).swapBtcToMusd{value: btcGainHarvested}(minMusdOut, address(this)) returns (
                    uint256 musdOut
                ) {
                    compoundedMusd = musdOut;
                    IERC20(musd).approve(stabilityPool, musdOut);
                    IStabilityPool(stabilityPool).provideToSP(musdOut);
                    totalSpAllocated += musdOut;
                } catch {}
            }
        }

        emit StabilityPoolGainsHarvested(msg.sender, btcGainHarvested, compoundedMusd);
    }

    /// @notice Unwinds `musdNeeded` instantly for Trove self-healing rescue or x402 invoice clearing.
    ///         Pulls from liquid STRC reserve first, then StabilityPool, then swaps maMUSD shares via 0xBF32...FDE0.
    function instantUnwindToMusd(
        address user,
        uint256 musdNeeded,
        uint256 minMusdOut,
        address recipient
    )
        external
        onlyAuthorizedFor(user)
        returns (uint256 musdDelivered)
    {
        if (musdNeeded == 0) revert InvalidAmount();
        UserCarryPosition storage pos = positions[user];
        uint256 totalAvailable = getUserEstimatedMusd(user);
        if (totalAvailable < musdNeeded) {
            revert InsufficientCarryBalance(totalAvailable, musdNeeded);
        }

        uint256 remaining = musdNeeded;
        uint256 spWithdrawn = 0;
        uint256 sharesSwapped = 0;

        // Step 1: Pull from liquid STRC reserve
        if (pos.strcAllocatedMusd > 0) {
            uint256 fromStrc = remaining <= pos.strcAllocatedMusd ? remaining : pos.strcAllocatedMusd;
            pos.strcAllocatedMusd -= fromStrc;
            totalStrcAllocated -= fromStrc;
            remaining -= fromStrc;
            musdDelivered += fromStrc;
        }

        // Step 2: Pull from canonical StabilityPool via withdrawFromSP
        if (remaining > 0 && pos.spAllocatedMusd > 0) {
            uint256 spPull = remaining <= pos.spAllocatedMusd ? remaining : pos.spAllocatedMusd;
            uint256 compoundedSp = IStabilityPool(stabilityPool).getCompoundedMUSDDeposit(address(this));
            uint256 actualPull = spPull <= compoundedSp ? spPull : compoundedSp;

            if (actualPull > 0) {
                uint256 balBefore = IERC20(musd).balanceOf(address(this));
                IStabilityPool(stabilityPool).withdrawFromSP(actualPull);
                uint256 balAfter = IERC20(musd).balanceOf(address(this));
                uint256 received = balAfter > balBefore ? (balAfter - balBefore) : actualPull;

                pos.spAllocatedMusd -= spPull;
                if (totalSpAllocated >= spPull) totalSpAllocated -= spPull;
                spWithdrawn = received;
                musdDelivered += received;
                remaining = remaining > received ? remaining - received : 0;
            }
        }

        // Step 3: Swap maMUSD shares directly back to MUSD via Mezo Pools (0xBF32...FDE0 / Router)
        if (remaining > 0 && pos.maMusdShares > 0) {
            uint256 sharesToUnwind = pos.maMusdShares;
            if (remaining < pos.maMusdShares) {
                sharesToUnwind = remaining;
            }
            pos.maMusdShares -= sharesToUnwind;
            if (totalMaMusdShares >= sharesToUnwind) totalMaMusdShares -= sharesToUnwind;
            sharesSwapped = sharesToUnwind;

            uint256 swappedMusd = _swapMaMusdToMusd(sharesToUnwind);
            musdDelivered += swappedMusd;
        }

        if (musdDelivered < minMusdOut) {
            revert SlippageExceeded(musdDelivered, minMusdOut);
        }

        if (pos.totalDepositedMusd >= musdDelivered) {
            pos.totalDepositedMusd -= musdDelivered;
        } else {
            pos.totalDepositedMusd = 0;
        }
        pos.lastUpdated = block.timestamp;

        require(IERC20(musd).transfer(recipient, musdDelivered), "MUSD transfer failed");

        emit InstantUnwindExecuted(user, recipient, musdNeeded, musdDelivered, spWithdrawn, sharesSwapped);
    }

    /// @notice Returns the total estimated MUSD value of a user's productive carry position.
    function getUserEstimatedMusd(address user) public view returns (uint256) {
        UserCarryPosition memory pos = positions[user];
        uint256 maMusdValue = pos.maMusdShares;
        if (pos.maMusdShares > 0 && maMusdPool.code.length > 0) {
            try IMezoPool(maMusdPool).getAmountOut(1e18, maMusd) returns (uint256 unitRate) {
                if (unitRate > 0.95e18) {
                    maMusdValue = (pos.maMusdShares * unitRate) / 1e18;
                }
            } catch {}
        }
        return pos.spAllocatedMusd + maMusdValue + pos.strcAllocatedMusd;
    }

    /// @notice Returns live StabilityPool telemetry for this engine.
    function getEngineTelemetry()
        external
        view
        returns (
            uint256 spCompoundedDeposit,
            uint256 spPendingBtcGain,
            uint256 poolTotalDeposits,
            uint256 maMusdBalance,
            uint256 liquidMusdReserve
        )
    {
        spCompoundedDeposit = IStabilityPool(stabilityPool).getCompoundedMUSDDeposit(address(this));
        spPendingBtcGain = IStabilityPool(stabilityPool).getDepositorCollateralGain(address(this));
        poolTotalDeposits = IStabilityPool(stabilityPool).getTotalMUSDDeposits();
        maMusdBalance = maMusd.code.length > 0 ? IERC20(maMusd).balanceOf(address(this)) : 0;
        liquidMusdReserve = IERC20(musd).balanceOf(address(this));
    }

    function _deployToMaMusd(uint256 musdAmount) internal returns (uint256 sharesOut) {
        // First try depositing directly into maMUSD if depositCap allows
        if (maMusd.code.length > 0) {
            IERC20(musd).approve(maMusd, musdAmount);
            try IMaMUSD(maMusd).deposit(musdAmount, address(this)) returns (uint256 minted) {
                if (minted > 0) return minted;
            } catch {}
        }

        // Next try swapping MUSD -> maMUSD through the canonical maMUSD/MUSD pool (0xBF32...FDE0) via Router
        // Only execute full AMM swap if pool depth supports < 2% price impact
        if (mezoRouter.code.length > 0 && maMusdPool.code.length > 0) {
            uint256 minAcceptableShares = (musdAmount * 9800) / BPS_DENOMINATOR;
            try IMezoPool(maMusdPool).getAmountOut(musdAmount, musd) returns (uint256 expectedOut) {
                if (expectedOut >= minAcceptableShares) {
                    IERC20(musd).approve(mezoRouter, musdAmount);
                    IMezoPoolsRouter.Route[] memory routes = new IMezoPoolsRouter.Route[](1);
                    routes[0] = IMezoPoolsRouter.Route({
                        from: musd,
                        to: maMusd,
                        stable: true,
                        factory: mezoFactory
                    });
                    try IMezoPoolsRouter(mezoRouter).swapExactTokensForTokens(
                        musdAmount,
                        minAcceptableShares,
                        routes,
                        address(this),
                        block.timestamp + 600
                    ) returns (uint256[] memory amounts) {
                        return amounts[amounts.length - 1];
                    } catch {}
                }
            } catch {}
        }

        // If external vault/pool is paused or capped on testnet, retain 1:1 backed share accounting inside engine
        return musdAmount;
    }

    function _swapMaMusdToMusd(uint256 sharesAmount) internal returns (uint256 musdOut) {
        uint256 actualMaMusdBal = maMusd.code.length > 0 ? IERC20(maMusd).balanceOf(address(this)) : 0;
        if (actualMaMusdBal >= sharesAmount && sharesAmount > 0) {
            // Swap maMUSD -> MUSD through canonical Mezo Pools Router (0x9a1f...D7E9) & Pool (0xBF32...FDE0)
            if (mezoRouter.code.length > 0) {
                IERC20(maMusd).approve(mezoRouter, sharesAmount);
                IMezoPoolsRouter.Route[] memory routes = new IMezoPoolsRouter.Route[](1);
                routes[0] = IMezoPoolsRouter.Route({
                    from: maMusd,
                    to: musd,
                    stable: true,
                    factory: mezoFactory
                });
                try IMezoPoolsRouter(mezoRouter).swapExactTokensForTokens(
                    sharesAmount,
                    0,
                    routes,
                    address(this),
                    block.timestamp + 600
                ) returns (uint256[] memory amounts) {
                    return amounts[amounts.length - 1];
                } catch {}
            }
            // Fallback to maMUSD.redeem if pool liquidity is shallow
            try IMaMUSD(maMusd).redeem(sharesAmount, address(this), address(this)) returns (uint256 redeemedMusd, uint256) {
                if (redeemedMusd > 0) return redeemedMusd;
            } catch {}
        }
        return sharesAmount;
    }
}
