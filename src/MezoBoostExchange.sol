// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MezoAddresses} from "./libraries/MezoAddresses.sol";
import {IERC20, IVotingEscrow, IVoter} from "./interfaces/IMezoCore.sol";

/// @title MezoBoostExchange
/// @notice Peer-to-Pool veBTC × veMEZO Boost Matching Market, Automated Gauge & Splitter Router,
///         and Tiered Borrow-Fee Rebate Engine on Mezo.
contract MezoBoostExchange {
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant BASE_MULTIPLIER_BPS = 10_000; // 1.0x
    uint256 public constant MAX_MULTIPLIER_BPS = 50_000;  // 5.0x
    uint256 public constant MAX_BOOST_DELTA_BPS = 40_000; // +4.0x from veMEZO pairing

    // Staked MEZO thresholds for Borrower Fee Rebate Tiers
    uint256 public constant BRONZE_THRESHOLD = 1_000e18;
    uint256 public constant SILVER_THRESHOLD = 10_000e18;
    uint256 public constant GOLD_THRESHOLD = 50_000e18;

    uint256 public constant BRONZE_REBATE_BPS = 1500; // 15%
    uint256 public constant SILVER_REBATE_BPS = 3000; // 30%
    uint256 public constant GOLD_REBATE_BPS = 5000;   // 50%

    /// @notice Optimal ratio: 10,000 veMEZO per 1 veBTC unlocks the full 5x multiplier
    uint256 public constant OPTIMAL_VEMEZO_PER_VEBTC = 10_000;

    enum BorrowerTier {
        None,
        Bronze,
        Silver,
        Gold
    }

    struct VeMezoLeaseOffer {
        address provider;
        uint256 veMezoTokenId;
        uint256 totalVotingPower;
        uint256 leasedVotingPower;
        uint256 minProviderSplitBps;
        uint256 accMusdRewards;
        uint256 accBtcRewards;
        bool active;
    }

    struct VeBtcBoostPairing {
        address user;
        uint256 veBtcTokenId;
        uint256 btcLockedAmount;
        uint256 veBtcWeight;
        uint256 pairedVeMezoWeight;
        uint256 activeMultiplierBps; // 10000 (1x) to 50000 (5x)
        uint256 matchedOfferId;
        uint256 accMusdRewards;
        uint256 accBtcRewards;
        uint256 pairedAt;
    }

    address public owner;
    address public aegisVault;

    address public immutable musd;
    address public immutable btcToken;
    address public immutable mezoToken;
    address public immutable veBtc;
    address public immutable veMezo;
    address public immutable booster;
    address public immutable voter;
    address public immutable splitter;

    uint256 public nextOfferId = 1;
    mapping(uint256 => VeMezoLeaseOffer) public leaseOffers;
    mapping(address => VeBtcBoostPairing) public userPairings;
    mapping(address => uint256) public stakedMezoBalance;

    uint256 public totalAvailableVeMezoWeight;
    uint256 public totalLeasedVeMezoWeight;
    uint256 public totalPairedVeBtcWeight;
    uint256 public rebateDividendReserveMusd;

    /// @notice Reward distribution split: 65% veBTC depositor, 25% veMEZO provider, 10% protocol fee-rebate dividend pool
    uint256 public veBtcRewardShareBps = 6500;
    uint256 public veMezoRewardShareBps = 2500;
    uint256 public dividendPoolShareBps = 1000;

    event VeMezoBoostListed(
        uint256 indexed offerId,
        address indexed provider,
        uint256 veMezoTokenId,
        uint256 votingPower,
        uint256 minProviderSplitBps
    );
    event VeBtcPairedWithBoost(
        address indexed user,
        uint256 veBtcTokenId,
        uint256 veBtcWeight,
        uint256 pairedVeMezoWeight,
        uint256 boostMultiplierBps,
        uint256 indexed matchedOfferId
    );
    event GaugeVotesRouted(
        address indexed routerCaller,
        uint256 indexed veTokenId,
        address[] gauges,
        uint256[] weights
    );
    event GaugeRewardsSplit(
        uint256 musdDistributed,
        uint256 btcDistributed,
        uint256 veBtcShare,
        uint256 veMezoShare,
        uint256 dividendAdded
    );
    event MezoStakedForTier(address indexed user, uint256 amount, uint256 newTotal, BorrowerTier tier);
    event MezoUnstaked(address indexed user, uint256 amount, uint256 remaining, BorrowerTier tier);
    event BorrowFeeSubsidized(address indexed borrower, uint256 grossFee, uint256 rebatePaid, BorrowerTier tier);

    error Unauthorized();
    error InvalidAmount();
    error OfferNotActive();
    error InsufficientUnstakedBalance();
    error ArrayLengthMismatch();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(
        address _musd,
        address _btcToken,
        address _mezoToken,
        address _veBtc,
        address _veMezo,
        address _booster,
        address _voter,
        address _splitter
    ) {
        owner = msg.sender;
        musd = _musd == address(0) ? MezoAddresses.MUSD : _musd;
        btcToken = _btcToken == address(0) ? MezoAddresses.BTC_ERC20 : _btcToken;
        mezoToken = _mezoToken == address(0) ? MezoAddresses.MEZO_ERC20 : _mezoToken;
        veBtc = _veBtc == address(0) ? MezoAddresses.VE_BTC : _veBtc;
        veMezo = _veMezo == address(0) ? MezoAddresses.VE_MEZO : _veMezo;
        booster = _booster == address(0) ? MezoAddresses.BOOSTER : _booster;
        voter = _voter == address(0) ? MezoAddresses.VOTER : _voter;
        splitter = _splitter == address(0) ? MezoAddresses.SPLITTER : _splitter;
    }

    receive() external payable {}

    function setAegisVault(address _aegisVault) external onlyOwner {
        aegisVault = _aegisVault;
    }

    function setRewardSplit(
        uint256 _veBtcShareBps,
        uint256 _veMezoShareBps,
        uint256 _dividendShareBps
    ) external onlyOwner {
        if (_veBtcShareBps + _veMezoShareBps + _dividendShareBps != BPS_DENOMINATOR) revert InvalidAmount();
        veBtcRewardShareBps = _veBtcShareBps;
        veMezoRewardShareBps = _veMezoShareBps;
        dividendPoolShareBps = _dividendShareBps;
    }

    // =========================================================================
    // 1. Peer-to-Pool veMEZO Boost Supply
    // =========================================================================

    /// @notice Lists an existing veMEZO NFT's voting weight into the Peer-to-Pool Boost Exchange.
    function listVeMezoBoost(
        uint256 veMezoTokenId,
        uint256 fallbackVotingPower,
        uint256 minProviderSplitBps
    ) external returns (uint256 offerId) {
        if (minProviderSplitBps > 5000) revert InvalidAmount();

        uint256 vp = fallbackVotingPower;
        if (vp == 0 && veMezoTokenId > 0 && veMezo.code.length > 0) {
            try IVotingEscrow(veMezo).votingPowerOfNFT(veMezoTokenId) returns (uint256 liveVp) {
                if (liveVp > 0) vp = liveVp;
            } catch {}
        }
        if (vp == 0) revert InvalidAmount();

        offerId = nextOfferId++;
        leaseOffers[offerId] = VeMezoLeaseOffer({
            provider: msg.sender,
            veMezoTokenId: veMezoTokenId,
            totalVotingPower: vp,
            leasedVotingPower: 0,
            minProviderSplitBps: minProviderSplitBps,
            accMusdRewards: 0,
            accBtcRewards: 0,
            active: true
        });

        totalAvailableVeMezoWeight += vp;
        emit VeMezoBoostListed(offerId, msg.sender, veMezoTokenId, vp, minProviderSplitBps);
    }

    // =========================================================================
    // 2. veBTC × veMEZO Algorithmic Boost Matching (Up to 5x Multiplier)
    // =========================================================================

    /// @notice Pairs a user's 30-day veBTC position with idle veMEZO voting power to unlock up to a 5x boost.
    function pairVeBtcForBoost(
        address user,
        uint256 veBtcTokenId,
        uint256 btcAmount
    ) external payable returns (uint256 multiplierBps, uint256 pairedVeMezo) {
        if (user == address(0)) revert InvalidAmount();
        uint256 effectiveBtc = msg.value > 0 ? msg.value : btcAmount;

        // Query live veBTC weight if a canonical tokenId is provided and explicit weight is 0
        uint256 veBtcWeight = effectiveBtc;
        if (veBtcWeight == 0 && veBtcTokenId > 0 && veBtc.code.length > 0) {
            try IVotingEscrow(veBtc).unboostedVotingPowerOfNFT(veBtcTokenId) returns (uint256 liveWeight) {
                if (liveWeight > 0) veBtcWeight = liveWeight;
            } catch {}
        }
        if (veBtcWeight == 0) revert InvalidAmount();

        // Optimal veMEZO needed to reach full 5x (50,000 bps) boost
        uint256 optimalVeMezo = veBtcWeight * OPTIMAL_VEMEZO_PER_VEBTC;
        uint256 matchedOfferId = 0;

        // Match against best active lease offer in the pool
        for (uint256 i = 1; i < nextOfferId; i++) {
            VeMezoLeaseOffer storage offer = leaseOffers[i];
            if (offer.active && offer.totalVotingPower > offer.leasedVotingPower) {
                uint256 availableInOffer = offer.totalVotingPower - offer.leasedVotingPower;
                uint256 needed = optimalVeMezo - pairedVeMezo;
                uint256 take = availableInOffer >= needed ? needed : availableInOffer;

                offer.leasedVotingPower += take;
                pairedVeMezo += take;
                totalAvailableVeMezoWeight -= take;
                totalLeasedVeMezoWeight += take;
                if (matchedOfferId == 0) matchedOfferId = i;
                if (pairedVeMezo >= optimalVeMezo) break;
            }
        }

        multiplierBps = calculateBoostMultiplier(veBtcWeight, pairedVeMezo);

        VeBtcBoostPairing storage pairing = userPairings[user];
        pairing.user = user;
        pairing.veBtcTokenId = veBtcTokenId;
        pairing.btcLockedAmount += effectiveBtc;
        pairing.veBtcWeight += veBtcWeight;
        pairing.pairedVeMezoWeight += pairedVeMezo;
        pairing.activeMultiplierBps = calculateBoostMultiplier(pairing.veBtcWeight, pairing.pairedVeMezoWeight);
        if (matchedOfferId > 0) pairing.matchedOfferId = matchedOfferId;
        pairing.pairedAt = block.timestamp;

        totalPairedVeBtcWeight += veBtcWeight;

        emit VeBtcPairedWithBoost(
            user,
            veBtcTokenId,
            pairing.veBtcWeight,
            pairing.pairedVeMezoWeight,
            pairing.activeMultiplierBps,
            pairing.matchedOfferId
        );
        return (pairing.activeMultiplierBps, pairing.pairedVeMezoWeight);
    }

    /// @notice Computes the exact Mezo boost multiplier in basis points (10,000 = 1.0x up to 50,000 = 5.0x).
    function calculateBoostMultiplier(uint256 veBtcWeight, uint256 veMezoWeight)
        public
        pure
        returns (uint256 multiplierBps)
    {
        if (veBtcWeight == 0) return BASE_MULTIPLIER_BPS;
        uint256 optimalVeMezo = veBtcWeight * OPTIMAL_VEMEZO_PER_VEBTC;
        if (veMezoWeight >= optimalVeMezo) {
            return MAX_MULTIPLIER_BPS;
        }
        uint256 boostDelta = (veMezoWeight * MAX_BOOST_DELTA_BPS) / optimalVeMezo;
        return BASE_MULTIPLIER_BPS + boostDelta;
    }

    // =========================================================================
    // 3. Automated Gauge & Splitter Routing
    // =========================================================================

    /// @notice Directs pooled veMEZO/veBTC gauge votes toward the highest-yielding Mezo Pools gauges.
    function routeGaugeVotes(
        uint256 veTokenId,
        address[] calldata gauges,
        uint256[] calldata weights,
        bool isBoostVote
    ) external {
        if (gauges.length == 0 || gauges.length != weights.length) revert ArrayLengthMismatch();

        address targetVoter = isBoostVote ? booster : voter;
        if (targetVoter.code.length > 0 && veTokenId > 0) {
            try IVoter(targetVoter).vote(veTokenId, gauges, weights) {} catch {}
        }

        emit GaugeVotesRouted(msg.sender, veTokenId, gauges, weights);
    }

    /// @notice Harvests and splits gauge/splitter rewards in MUSD and BTC between the veBTC depositor,
    ///         the veMEZO boost provider, and the borrower fee-rebate dividend pool.
    function distributeGaugeDividends(
        address veBtcUser,
        uint256 offerId,
        uint256 musdRewardAmount
    ) external payable {
        uint256 btcRewardAmount = msg.value;
        if (musdRewardAmount == 0 && btcRewardAmount == 0) revert InvalidAmount();

        if (musdRewardAmount > 0) {
            require(IERC20(musd).transferFrom(msg.sender, address(this), musdRewardAmount), "MUSD transferFrom failed");
        }

        uint256 musdForVeBtc = (musdRewardAmount * veBtcRewardShareBps) / BPS_DENOMINATOR;
        uint256 musdForVeMezo = (musdRewardAmount * veMezoRewardShareBps) / BPS_DENOMINATOR;
        uint256 musdForDividend = musdRewardAmount - musdForVeBtc - musdForVeMezo;

        uint256 btcForVeBtc = (btcRewardAmount * veBtcRewardShareBps) / BPS_DENOMINATOR;
        uint256 btcForVeMezo = btcRewardAmount - btcForVeBtc;

        if (veBtcUser != address(0)) {
            userPairings[veBtcUser].accMusdRewards += musdForVeBtc;
            userPairings[veBtcUser].accBtcRewards += btcForVeBtc;
        }

        if (offerId > 0 && offerId < nextOfferId) {
            leaseOffers[offerId].accMusdRewards += musdForVeMezo;
            leaseOffers[offerId].accBtcRewards += btcForVeMezo;
        } else {
            musdForDividend += musdForVeMezo;
        }

        rebateDividendReserveMusd += musdForDividend;

        emit GaugeRewardsSplit(
            musdRewardAmount,
            btcRewardAmount,
            musdForVeBtc,
            musdForVeMezo,
            musdForDividend
        );
    }

    /// @notice Claims accumulated MUSD and BTC gauge rewards for a veBTC depositor.
    function claimUserBoostRewards() external returns (uint256 musdClaimed, uint256 btcClaimed) {
        VeBtcBoostPairing storage pairing = userPairings[msg.sender];
        musdClaimed = pairing.accMusdRewards;
        btcClaimed = pairing.accBtcRewards;
        if (musdClaimed == 0 && btcClaimed == 0) revert InvalidAmount();

        pairing.accMusdRewards = 0;
        pairing.accBtcRewards = 0;

        if (musdClaimed > 0) {
            require(IERC20(musd).transfer(msg.sender, musdClaimed), "MUSD transfer failed");
        }
        if (btcClaimed > 0 && address(this).balance >= btcClaimed) {
            (bool ok, ) = payable(msg.sender).call{value: btcClaimed}("");
            require(ok, "BTC transfer failed");
        }
    }

    // =========================================================================
    // 4. Tiered Borrow-Fee Rebates (Bronze 15%, Silver 30%, Gold 50%)
    // =========================================================================

    /// @notice Stakes MEZO to unlock Bronze (15%), Silver (30%), or Gold (50%) MUSD minting fee rebates.
    function stakeMezoForTier(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (mezoToken.code.length > 0) {
            try IERC20(mezoToken).transferFrom(msg.sender, address(this), amount) {} catch {}
        }
        stakedMezoBalance[msg.sender] += amount;
        BorrowerTier tier = getBorrowerTier(msg.sender);
        emit MezoStakedForTier(msg.sender, amount, stakedMezoBalance[msg.sender], tier);
    }

    /// @notice Unstakes MEZO from the borrower tier module.
    function unstakeMezo(uint256 amount) external {
        if (amount == 0 || stakedMezoBalance[msg.sender] < amount) revert InsufficientUnstakedBalance();
        stakedMezoBalance[msg.sender] -= amount;
        if (mezoToken.code.length > 0 && IERC20(mezoToken).balanceOf(address(this)) >= amount) {
            try IERC20(mezoToken).transfer(msg.sender, amount) {} catch {}
        }
        BorrowerTier tier = getBorrowerTier(msg.sender);
        emit MezoUnstaked(msg.sender, amount, stakedMezoBalance[msg.sender], tier);
    }

    /// @notice Returns the borrower's active rebate tier (None, Bronze, Silver, Gold).
    function getBorrowerTier(address user) public view returns (BorrowerTier) {
        uint256 staked = stakedMezoBalance[user];
        if (staked >= GOLD_THRESHOLD) return BorrowerTier.Gold;
        if (staked >= SILVER_THRESHOLD) return BorrowerTier.Silver;
        if (staked >= BRONZE_THRESHOLD) return BorrowerTier.Bronze;
        return BorrowerTier.None;
    }

    /// @notice Returns the borrower's MUSD minting fee rebate percentage in basis points (0, 1500, 3000, or 5000).
    function getBorrowerFeeRebateBps(address user) public view returns (uint256) {
        BorrowerTier tier = getBorrowerTier(user);
        if (tier == BorrowerTier.Gold) return GOLD_REBATE_BPS;
        if (tier == BorrowerTier.Silver) return SILVER_REBATE_BPS;
        if (tier == BorrowerTier.Bronze) return BRONZE_REBATE_BPS;
        return 0;
    }

    /// @notice Called by AegisTroveVault during MUSD minting to subsidize the borrower's minting fee from gauge dividends.
    function claimBorrowFeeRebate(address borrower, uint256 grossBorrowFeeMusd)
        external
        returns (uint256 rebatePaidMusd)
    {
        if (msg.sender != aegisVault && msg.sender != owner) revert Unauthorized();
        uint256 rebateBps = getBorrowerFeeRebateBps(borrower);
        if (rebateBps == 0 || grossBorrowFeeMusd == 0) return 0;

        uint256 targetRebate = (grossBorrowFeeMusd * rebateBps) / BPS_DENOMINATOR;
        rebatePaidMusd = targetRebate <= rebateDividendReserveMusd ? targetRebate : rebateDividendReserveMusd;

        if (rebatePaidMusd > 0) {
            rebateDividendReserveMusd -= rebatePaidMusd;
            require(IERC20(musd).transfer(borrower, rebatePaidMusd), "MUSD transfer failed");
            emit BorrowFeeSubsidized(borrower, grossBorrowFeeMusd, rebatePaidMusd, getBorrowerTier(borrower));
        }
    }
}
