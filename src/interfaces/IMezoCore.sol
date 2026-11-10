// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IMUSD is IERC20 {
    function burn(address account, uint256 amount) external;
}

/// @notice Canonical Mezo PriceFeed (0x86bCF0841622a5dAC14A313a15f96A95421b9366)
interface IPriceFeed {
    function fetchPrice() external view returns (uint256);
    function oracle() external view returns (address);
    function TARGET_DIGITS() external view returns (uint8);
}

/// @notice Canonical Mezo BorrowerOperations (0xCdF7028ceAB81fA0C6971208e83fa7872994beE5)
interface IBorrowerOperations {
    function MCR() external view returns (uint256);
    function CCR() external view returns (uint256);
    function MUSD_GAS_COMPENSATION() external view returns (uint256);
    function minNetDebt() external view returns (uint256);
    function borrowingRate() external view returns (uint256);
    function getBorrowingFee(uint256 _debt) external view returns (uint256);
    function getEntireSystemColl() external view returns (uint256);
    function getEntireSystemDebt() external view returns (uint256);
    function musd() external view returns (address);
    function troveManager() external view returns (address);
    function sortedTroves() external view returns (address);
    function stabilityPoolAddress() external view returns (address);
    function priceFeed() external view returns (address);

    function openTrove(uint256 _debtAmount, address _upperHint, address _lowerHint) external payable;
    function addColl(address _upperHint, address _lowerHint) external payable;
    function withdrawColl(uint256 _amount, address _upperHint, address _lowerHint) external;
    function withdrawMUSD(uint256 _amount, address _upperHint, address _lowerHint) external;
    function repayMUSD(uint256 _amount, address _upperHint, address _lowerHint) external;
    function closeTrove() external;
    function adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable;
    function refinance(address _upperHint, address _lowerHint) external;
    function claimCollateral() external;
}

/// @notice Canonical Mezo TroveManager (0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0)
interface ITroveManager {
    function MCR() external view returns (uint256);
    function CCR() external view returns (uint256);
    function MUSD_GAS_COMPENSATION() external view returns (uint256);
    function getTroveOwnersCount() external view returns (uint256);
    function getTroveFromTroveOwnersArray(uint256 _index) external view returns (address);
    function getNominalICR(address _borrower) external view returns (uint256);
    function getCurrentICR(address _borrower, uint256 _price) external view returns (uint256);
    function getEntireDebtAndColl(address _borrower)
        external
        view
        returns (
            uint256 coll,
            uint256 principal,
            uint256 interest,
            uint256 pendingCollateral,
            uint256 pendingPrincipal,
            uint256 pendingInterest
        );
    function getTroveStatus(address _borrower) external view returns (uint8);
    function getTroveColl(address _borrower) external view returns (uint256);
    function getTroveDebt(address _borrower) external view returns (uint256);
    function getTrovePrincipal(address _borrower) external view returns (uint256);
    function getTroveInterestOwed(address _borrower) external view returns (uint256);
    function getTroveInterestRate(address _borrower) external view returns (uint16);
    function getTroveMaxBorrowingCapacity(address _borrower) external view returns (uint256);
    function checkRecoveryMode(uint256 _price) external view returns (bool);
    function getTCR(uint256 _price) external view returns (uint256);
    function getEntireSystemColl() external view returns (uint256);
    function getEntireSystemDebt() external view returns (uint256);
    function liquidate(address _borrower) external;
    function redeemCollateral(
        uint256 _amount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations
    ) external;
}

/// @notice Canonical Mezo SortedTroves (0x722E4D24FD6Ff8b0AC679450F3D91294607268fA)
interface ISortedTroves {
    function contains(address _id) external view returns (bool);
    function isFull() external view returns (bool);
    function isEmpty() external view returns (bool);
    function getSize() external view returns (uint256);
    function getMaxSize() external view returns (uint256);
    function getFirst() external view returns (address);
    function getLast() external view returns (address);
    function getNext(address _id) external view returns (address);
    function getPrev(address _id) external view returns (address);
    function validInsertPosition(uint256 _NICR, address _prevId, address _nextId) external view returns (bool);
    function findInsertPosition(uint256 _NICR, address _prevId, address _nextId)
        external
        view
        returns (address, address);
}

/// @notice Canonical Mezo HintHelpers (0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6)
interface IHintHelpers {
    function getRedemptionHints(uint256 _amount, uint256 _price, uint256 _maxIterations)
        external
        view
        returns (address firstRedemptionHint, uint256 partialRedemptionHintNICR, uint256 truncatedMUSDamount);
    function getApproxHint(uint256 _CR, uint256 _numTrials, uint256 _inputRandomSeed)
        external
        view
        returns (address hintAddress, uint256 diff, uint256 latestRandomSeed);
    function computeNominalCR(uint256 _coll, uint256 _debt) external pure returns (uint256);
    function computeCR(uint256 _coll, uint256 _debt, uint256 _price) external pure returns (uint256);
}

/// @notice Canonical Mezo StabilityPool (0x1CCA7E410eE41739792eA0A24e00349Dd247680e)
interface IStabilityPool {
    function provideToSP(uint256 _amount) external;
    function withdrawFromSP(uint256 _amount) external;
    function withdrawCollateralGainToTrove(address _upperHint, address _lowerHint) external;
    function getDepositorCollateralGain(address _depositor) external view returns (uint256);
    function getCompoundedMUSDDeposit(address _depositor) external view returns (uint256);
    function getTotalMUSDDeposits() external view returns (uint256);
    function getCollateralBalance() external view returns (uint256);
    function deposits(address _depositor) external view returns (uint256);
}

/// @notice Canonical Mezo InterestRateManager (0xD4D6c36A592A2c5e86035A6bca1d57747a567f37)
interface IInterestRateManager {
    function interestRate() external view returns (uint16);
    function getAccruedInterest() external view returns (uint256);
}

/// @notice Canonical Morbit Auto Earn MUSD Vault (0xA8BAc7913D5163E2dF9aE3aF5B0AEeA44529Ac70)
interface IMaMUSD is IERC20 {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner_)
        external
        returns (uint256 musdOut, uint256 btcOut);
    function previewRedeem(uint256 shares) external view returns (uint256 musdOut, uint256 btcOut);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function sharePrice() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function claimRewards() external returns (uint256);
}

/// @notice Canonical Mezo Pools AMM Pair (e.g. maMUSD/MUSD 0xBF329A2A130cb0D5B5218f1672E51Fb36089FDE0)
interface IMezoPool is IERC20 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function tokens() external view returns (address, address);
    function stable() external view returns (bool);
    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast);
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256);
    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);
}

/// @notice Canonical Mezo Pools Router (0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9)
interface IMezoPoolsRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function defaultFactory() external view returns (address);
    function poolFor(address tokenA, address tokenB, bool stable, address _factory) external view returns (address);
    function getReserves(address tokenA, address tokenB, bool stable, address _factory)
        external
        view
        returns (uint256 reserveA, uint256 reserveB);
    function getAmountsOut(uint256 amountIn, Route[] memory routes) external view returns (uint256[] memory amounts);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

/// @notice Canonical MezoPoolsSwapper (0x219cCC99aB55c001f9c48cEC3740d6a64518bD72)
interface IMezoPoolsSwapper {
    function swapBtcToMusd(uint256 minMusdOut, address recipient) external payable returns (uint256 musdOut);
    function swapMusdToBtc(uint256 musdIn, uint256 minBtcOut, address recipient) external returns (uint256 btcOut);
    function router() external view returns (address);
    function factory() external view returns (address);
}

/// @notice Canonical VotingEscrow (veBTC 0x38E3...130a & veMEZO 0xaCE8...111b)
interface IVotingEscrow {
    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
    }

    function token() external view returns (address);
    function voter() external view returns (address);
    function booster() external view returns (address);
    function balanceOf(address _owner) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function votingPowerOfNFT(uint256 _tokenId) external view returns (uint256);
    function unboostedVotingPowerOfNFT(uint256 _tokenId) external view returns (uint256);
    function totalVotingPower() external view returns (uint256);
    function unboostedTotalVotingPower() external view returns (uint256);
    function locked(uint256 _tokenId) external view returns (LockedBalance memory);
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256 tokenId);
    function createLockFor(uint256 _value, uint256 _lockDuration, address _to) external returns (uint256 tokenId);
    function depositFor(uint256 _tokenId, uint256 _value) external;
    function increaseAmount(uint256 _tokenId, uint256 _value) external;
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external;
    function withdraw(uint256 _tokenId) external;
    function approve(address _approved, uint256 _tokenId) external;
    function transferFrom(address _from, address _to, uint256 _tokenId) external;
}

/// @notice Canonical Mezo Booster (0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1) and Voter (0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D)
interface IVoter {
    function ve() external view returns (address);
    function splitter() external view returns (address);
    function totalWeight() external view returns (uint256);
    function weights(address _gaugeOrBoostable) external view returns (uint256);
    function usedWeights(uint256 _tokenId) external view returns (uint256);
    function length() external view returns (uint256);
    function gauges(uint256 _index) external view returns (address);
    function isGauge(address _gauge) external view returns (bool);
    function isAlive(address _gauge) external view returns (bool);
    function getBoost(uint256 boostableTokenId) external view returns (uint256);
    function vote(uint256 _tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external;
    function reset(uint256 _tokenId) external;
    function poke(uint256 _tokenId) external;
    function claimRewards(address[] calldata _gauges) external;
    function claimFees(address[] calldata _fees, address[][] calldata _tokens, uint256 _tokenId) external;
    function claimBribes(address[] calldata _bribes, address[][] calldata _tokens, uint256 _tokenId) external;
}
