// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MezoAddresses} from "./libraries/MezoAddresses.sol";
import {
    IERC20,
    IBorrowerOperations,
    ITroveManager,
    ISortedTroves,
    IHintHelpers,
    IPriceFeed
} from "./interfaces/IMezoCore.sol";
import {MusdPegGuard} from "./MusdPegGuard.sol";
import {MUSDCarryEngine} from "./MUSDCarryEngine.sol";
import {MezoBoostExchange} from "./MezoBoostExchange.sol";

/// @title AegisUserTroveProxy
/// @notice Isolated per-user smart-vault node inside Mezo's canonical SortedTroves doubly linked list.
///         Controlled exclusively by AegisTroveVault so each borrower owns an independent on-chain Trove.
contract AegisUserTroveProxy {
    address public immutable vault;
    address public immutable borrowerOperations;
    address public immutable musd;

    error OnlyVault();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(address _vault, address _borrowerOperations, address _musd) {
        vault = _vault;
        borrowerOperations = _borrowerOperations;
        musd = _musd;
    }

    receive() external payable {}

    function executeOpenTrove(
        uint256 debtAmount,
        address upperHint,
        address lowerHint,
        address musdRecipient
    ) external payable onlyVault returns (uint256 mintedMusd) {
        IBorrowerOperations(borrowerOperations).openTrove{value: msg.value}(debtAmount, upperHint, lowerHint);
        mintedMusd = IERC20(musd).balanceOf(address(this));
        if (mintedMusd > 0) {
            require(IERC20(musd).transfer(musdRecipient, mintedMusd), "MUSD transfer failed");
        }
    }

    function executeAddColl(address upperHint, address lowerHint) external payable onlyVault {
        IBorrowerOperations(borrowerOperations).addColl{value: msg.value}(upperHint, lowerHint);
    }

    function executeWithdrawMusd(
        uint256 amount,
        address upperHint,
        address lowerHint,
        address musdRecipient
    ) external onlyVault {
        IBorrowerOperations(borrowerOperations).withdrawMUSD(amount, upperHint, lowerHint);
        uint256 bal = IERC20(musd).balanceOf(address(this));
        if (bal > 0) {
            require(IERC20(musd).transfer(musdRecipient, bal), "MUSD transfer failed");
        }
    }

    function executeRepayMusd(uint256 amount, address upperHint, address lowerHint) external onlyVault {
        IERC20(musd).approve(borrowerOperations, amount);
        IBorrowerOperations(borrowerOperations).repayMUSD(amount, upperHint, lowerHint);
    }

    function executeCloseTrove(address btcRecipient) external onlyVault returns (uint256 btcReturned) {
        uint256 debt = ITroveManager(IBorrowerOperations(borrowerOperations).troveManager()).getTroveDebt(address(this));
        IERC20(musd).approve(borrowerOperations, debt);
        IBorrowerOperations(borrowerOperations).closeTrove();
        btcReturned = address(this).balance;
        if (btcReturned > 0) {
            (bool ok, ) = payable(btcRecipient).call{value: btcReturned}("");
            require(ok, "BTC return failed");
        }
    }
}

/// @title AegisTroveVault
/// @notice Module A: Redemption-Shielded Self-Healing Vault on Mezo.
///         - Direct integration with BorrowerOperations, TroveManager, SortedTroves, HintHelpers, and PriceFeed
///         - Redemption Distance Radar computing exact MUSD debt ahead in SortedTroves queue
///         - O(1) HintHelpers + SortedTroves insertion hint computation
///         - Autonomous Keeper Rescue pulling yield from MUSDCarryEngine to execute repayMUSD
contract AegisTroveVault {
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant WAD = 1e18;

    address public owner;
    address public immutable musd;
    address public immutable borrowerOperations;
    address public immutable troveManager;
    address public immutable sortedTroves;
    address public immutable hintHelpers;
    address public immutable priceFeed;

    MusdPegGuard public pegGuard;
    MUSDCarryEngine public carryEngine;
    MezoBoostExchange public boostExchange;
    address public floatRefiller;

    /// @notice ICR threshold below which a Trove is eligible for autonomous self-healing rescue (default: 135% = 1.35e18)
    uint256 public rescueIcrThreshold = 1.35e18;
    /// @notice Target post-rescue ICR (default: 155% = 1.55e18)
    uint256 public targetHealthyIcr = 1.55e18;
    /// @notice Bottom percentile of SortedTroves redemption queue that triggers rescue during peg discount (default: 10% = 1000 bps)
    uint256 public redemptionDangerPercentileBps = 1000;

    /// @notice Maps user address -> isolated AegisUserTroveProxy address in SortedTroves
    mapping(address => address) public userTroveProxies;
    /// @notice Maps proxy address -> user owner
    mapping(address => address) public proxyToOwner;
    /// @notice Authorized x402 credit agents per user (user => agent => remaining credit allowance)
    mapping(address => mapping(address => uint256)) public agentCreditAllowance;

    struct RedemptionRadar {
        address troveAddress;
        bool isActiveInQueue;
        uint256 troveCollateralBtc;
        uint256 troveTotalDebtMusd;
        uint256 currentIcr;
        uint256 nominalIcr;
        uint256 trovesAheadInQueue;
        uint256 totalQueueSize;
        uint256 musdDebtAheadInQueue;
        uint256 queuePercentileBps; // 0 = very front of redemption line, 10000 = safest tail
        bool inRedemptionDangerZone;
        bool needsAutonomousRescue;
    }

    event UserTroveOpened(
        address indexed user,
        address indexed troveProxy,
        uint256 collBtc,
        uint256 mintedMusd,
        uint256 boostBtcLocked,
        uint256 carryDeployedMusd,
        uint256 feeRebateMusd
    );
    event AutonomousRescueExecuted(
        address indexed user,
        address indexed troveProxy,
        uint256 musdRepaid,
        uint256 icrBefore,
        uint256 icrAfter,
        uint256 musdAheadBefore,
        address upperHint,
        address lowerHint
    );
    event MicroCreditDrawn(
        address indexed user,
        address indexed caller,
        address indexed recipient,
        uint256 musdDrawn,
        address upperHint,
        address lowerHint
    );
    event TroveDebtRepaid(address indexed user, address indexed troveProxy, uint256 musdRepaid);
    event TroveClosed(address indexed user, address indexed troveProxy, uint256 btcReturned);
    event AgentCreditAuthorized(address indexed user, address indexed agent, uint256 allowanceMusd);
    event RescueParametersUpdated(uint256 rescueIcrThreshold, uint256 targetHealthyIcr, uint256 dangerPercentileBps);

    error Unauthorized();
    error InvalidAmount();
    error NoActiveTrove(address user);
    error RescueNotRequired(address troveAddress, uint256 currentIcr, uint256 queuePercentileBps);
    error InsufficientCreditAllowance(uint256 available, uint256 requested);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(
        address _musd,
        address _borrowerOperations,
        address _troveManager,
        address _sortedTroves,
        address _hintHelpers,
        address _priceFeed,
        address _pegGuard,
        address payable _carryEngine,
        address payable _boostExchange
    ) {
        owner = msg.sender;
        musd = _musd == address(0) ? MezoAddresses.MUSD : _musd;
        borrowerOperations = _borrowerOperations == address(0) ? MezoAddresses.BORROWER_OPERATIONS : _borrowerOperations;
        troveManager = _troveManager == address(0) ? MezoAddresses.TROVE_MANAGER : _troveManager;
        sortedTroves = _sortedTroves == address(0) ? MezoAddresses.SORTED_TROVES : _sortedTroves;
        hintHelpers = _hintHelpers == address(0) ? MezoAddresses.HINT_HELPERS : _hintHelpers;
        priceFeed = _priceFeed == address(0) ? MezoAddresses.PRICE_FEED : _priceFeed;
        pegGuard = MusdPegGuard(_pegGuard);
        carryEngine = MUSDCarryEngine(_carryEngine);
        boostExchange = MezoBoostExchange(_boostExchange);
    }

    receive() external payable {}

    function setFloatRefiller(address _floatRefiller) external onlyOwner {
        floatRefiller = _floatRefiller;
    }

    function setRescueParameters(
        uint256 _rescueIcrThreshold,
        uint256 _targetHealthyIcr,
        uint256 _redemptionDangerPercentileBps
    ) external onlyOwner {
        if (_rescueIcrThreshold < 1.12e18 || _targetHealthyIcr <= _rescueIcrThreshold || _redemptionDangerPercentileBps > 5000) {
            revert InvalidAmount();
        }
        rescueIcrThreshold = _rescueIcrThreshold;
        targetHealthyIcr = _targetHealthyIcr;
        redemptionDangerPercentileBps = _redemptionDangerPercentileBps;
        emit RescueParametersUpdated(_rescueIcrThreshold, _targetHealthyIcr, _redemptionDangerPercentileBps);
    }

    /// @notice Authorizes an x402 AI agent or clearing router to draw up to `allowanceMusd` micro-credit.
    function authorizeAgentCredit(address agent, uint256 allowanceMusd) external {
        agentCreditAllowance[msg.sender][agent] = allowanceMusd;
        emit AgentCreditAuthorized(msg.sender, agent, allowanceMusd);
    }

    /// @notice Deploys or returns the user's isolated AegisUserTroveProxy address.
    function getOrCreateUserProxy(address user) public returns (address proxy) {
        proxy = userTroveProxies[user];
        if (proxy == address(0)) {
            proxy = address(new AegisUserTroveProxy(address(this), borrowerOperations, musd));
            userTroveProxies[user] = proxy;
            proxyToOwner[proxy] = user;
        }
    }

    // =========================================================================
    // 1. Unified Collateral, Fixed-Rate MUSD Minting, Boost Activation & Carry
    // =========================================================================

    /// @notice End-to-End Onboarding Entrypoint:
    ///         1. Splits deposited BTC between Trove collateral and 30-day veBTC lock (if boostLockBtc > 0)
    ///         2. Computes O(1) SortedTroves hints via HintHelpers
    ///         3. Opens a fixed-rate MUSD Trove via BorrowerOperations
    ///         4. Applies Bronze/Silver/Gold borrower minting fee rebates via MezoBoostExchange
    ///         5. Routes designated MUSD into MUSDCarryEngine for positive-carry yield
    function openAndActivateVault(
        uint256 debtAmountMusd,
        uint256 boostLockBtc,
        uint256 carryDeployPercentBps,
        address upperHint,
        address lowerHint
    ) external payable returns (address troveProxy, uint256 mintedMusd) {
        if (msg.value <= boostLockBtc || debtAmountMusd == 0 || carryDeployPercentBps > BPS_DENOMINATOR) {
            revert InvalidAmount();
        }

        uint256 troveCollBtc = msg.value - boostLockBtc;
        troveProxy = getOrCreateUserProxy(msg.sender);

        // Compute optimal insertion hints via HintHelpers + SortedTroves if not supplied
        if (upperHint == address(0) && lowerHint == address(0)) {
            uint256 fee = IBorrowerOperations(borrowerOperations).getBorrowingFee(debtAmountMusd);
            uint256 gasComp = IBorrowerOperations(borrowerOperations).MUSD_GAS_COMPENSATION();
            (upperHint, lowerHint) = computeOptimalHints(troveCollBtc, debtAmountMusd + fee + gasComp);
        }

        // Open canonical Trove on Mezo BorrowerOperations
        mintedMusd = AegisUserTroveProxy(payable(troveProxy)).executeOpenTrove{value: troveCollBtc}(
            debtAmountMusd,
            upperHint,
            lowerHint,
            address(this)
        );

        // Claim Bronze/Silver/Gold borrow-fee rebate if eligible
        uint256 feeRebate = 0;
        if (address(boostExchange) != address(0)) {
            uint256 grossFee = IBorrowerOperations(borrowerOperations).getBorrowingFee(debtAmountMusd);
            try boostExchange.claimBorrowFeeRebate(msg.sender, grossFee) returns (uint256 r) {
                feeRebate = r;
            } catch {}
        }

        // Lock designated BTC slice into MezoBoostExchange for 5x veBTC × veMEZO boost
        if (boostLockBtc > 0 && address(boostExchange) != address(0)) {
            boostExchange.pairVeBtcForBoost{value: boostLockBtc}(msg.sender, 0, boostLockBtc);
        }

        // Deploy designated MUSD slice into MUSDCarryEngine
        uint256 carryMusd = (mintedMusd * carryDeployPercentBps) / BPS_DENOMINATOR;
        if (carryMusd > 0 && address(carryEngine) != address(0)) {
            IERC20(musd).approve(address(carryEngine), carryMusd);
            carryEngine.deployCarry(msg.sender, carryMusd);
        }

        // Send remaining liquid MUSD directly to borrower
        uint256 directMusd = mintedMusd - carryMusd;
        if (directMusd > 0) {
            require(IERC20(musd).transfer(msg.sender, directMusd), "MUSD transfer failed");
        }

        emit UserTroveOpened(
            msg.sender,
            troveProxy,
            troveCollBtc,
            mintedMusd,
            boostLockBtc,
            carryMusd,
            feeRebate
        );
    }

    /// @notice Adds BTC collateral to the caller's active Trove using HintHelpers insertion hints.
    function addCollateralToTrove(address upperHint, address lowerHint) external payable {
        if (msg.value == 0) revert InvalidAmount();
        address troveProxy = userTroveProxies[msg.sender];
        if (troveProxy == address(0) || !ISortedTroves(sortedTroves).contains(troveProxy)) {
            revert NoActiveTrove(msg.sender);
        }

        if (upperHint == address(0) && lowerHint == address(0)) {
            uint256 currentColl = ITroveManager(troveManager).getTroveColl(troveProxy);
            uint256 currentDebt = ITroveManager(troveManager).getTroveDebt(troveProxy);
            (upperHint, lowerHint) = computeOptimalHints(currentColl + msg.value, currentDebt);
        }

        AegisUserTroveProxy(payable(troveProxy)).executeAddColl{value: msg.value}(upperHint, lowerHint);
    }

    // =========================================================================
    // 2. Redemption Distance Radar & O(1) HintHelpers Telemetry
    // =========================================================================

    /// @notice Computes O(1) gas-optimized SortedTroves insertion hints using HintHelpers.
    function computeOptimalHints(uint256 collBtc, uint256 compositeDebtMusd)
        public
        view
        returns (address upperHint, address lowerHint)
    {
        if (compositeDebtMusd == 0) return (address(0), address(0));
        uint256 nicr = IHintHelpers(hintHelpers).computeNominalCR(collBtc, compositeDebtMusd);
        uint256 queueSize = ISortedTroves(sortedTroves).getSize();
        if (queueSize == 0) return (address(0), address(0));

        // O(1) boundary fast-path for head (safest Trove) and tail (front of redemption line)
        address first = ISortedTroves(sortedTroves).getFirst();
        if (first != address(0)) {
            if (nicr >= ITroveManager(troveManager).getNominalICR(first)) {
                return (first, first);
            }
            address nextOfFirst = ISortedTroves(sortedTroves).getNext(first);
            if (nextOfFirst != address(0) && nicr >= ITroveManager(troveManager).getNominalICR(nextOfFirst)) {
                return (nextOfFirst, nextOfFirst);
            }
        }
        address last = ISortedTroves(sortedTroves).getLast();
        if (last != address(0)) {
            uint256 lastNicr = ITroveManager(troveManager).getNominalICR(last);
            if (nicr <= lastNicr) {
                return (last, last);
            }
            address prevOfLast = ISortedTroves(sortedTroves).getPrev(last);
            if (prevOfLast != address(0) && nicr <= ITroveManager(troveManager).getNominalICR(prevOfLast)) {
                return (prevOfLast, prevOfLast);
            }
        }

        uint256 numTrials = _sqrt(queueSize);
        if (numTrials == 0) numTrials = 3;
        if (numTrials > 5) numTrials = 5;

        (address approxHint, , ) = IHintHelpers(hintHelpers).getApproxHint(
            nicr,
            numTrials,
            uint256(keccak256(abi.encodePacked(block.timestamp, collBtc, compositeDebtMusd)))
        );
        return ISortedTroves(sortedTroves).findInsertPosition(nicr, approxHint, approxHint);
    }

    /// @notice Queries SortedTroves and TroveManager to compute exact cumulative MUSD debt ahead of `userOrTrove`
    ///         in the redemption line, queue percentile, ICR, and whether autonomous rescue is needed.
    function getRedemptionRadar(address userOrTrove, uint256 maxIterations)
        public
        view
        returns (RedemptionRadar memory radar)
    {
        address targetTrove = userTroveProxies[userOrTrove] != address(0)
            ? userTroveProxies[userOrTrove]
            : userOrTrove;

        radar.troveAddress = targetTrove;
        radar.totalQueueSize = ISortedTroves(sortedTroves).getSize();
        radar.isActiveInQueue = ISortedTroves(sortedTroves).contains(targetTrove);

        if (!radar.isActiveInQueue || radar.totalQueueSize == 0) {
            return radar;
        }

        uint256 btcPrice = IPriceFeed(priceFeed).fetchPrice();
        radar.troveCollateralBtc = ITroveManager(troveManager).getTroveColl(targetTrove);
        radar.troveTotalDebtMusd = ITroveManager(troveManager).getTroveDebt(targetTrove);
        radar.currentIcr = ITroveManager(troveManager).getCurrentICR(targetTrove, btcPrice);
        radar.nominalIcr = ITroveManager(troveManager).getNominalICR(targetTrove);

        // Traverse SortedTroves from tail (getLast = lowest NICR = first redeemed) toward head
        uint256 limit = maxIterations == 0 ? 10 : maxIterations;
        address curr = ISortedTroves(sortedTroves).getLast();
        uint256 steps = 0;
        uint256 debtAhead = 0;

        while (curr != address(0) && curr != targetTrove && steps < limit) {
            debtAhead += ITroveManager(troveManager).getTroveDebt(curr);
            curr = ISortedTroves(sortedTroves).getPrev(curr);
            steps++;
        }

        radar.trovesAheadInQueue = steps;
        radar.musdDebtAheadInQueue = debtAhead;
        radar.queuePercentileBps = (steps * BPS_DENOMINATOR) / radar.totalQueueSize;

        bool pegDiscounted = false;
        if (address(pegGuard) != address(0)) {
            MusdPegGuard.PegTelemetry memory peg = pegGuard.evaluatePeg();
            pegDiscounted = peg.isPegDiscounted;
        }

        radar.inRedemptionDangerZone =
            radar.queuePercentileBps <= redemptionDangerPercentileBps && pegDiscounted;

        radar.needsAutonomousRescue =
            (radar.currentIcr <= rescueIcrThreshold) || radar.inRedemptionDangerZone;
    }

    // =========================================================================
    // 3. Autonomous Keeper Rescue (Self-Healing Troves)
    // =========================================================================

    /// @notice Autonomous Keeper Rescue: When a Trove's ICR approaches the minimum threshold or moves
    ///         within the bottom 10% of the SortedTroves redemption queue during a peg discount,
    ///         automatically pulls yield reserves from MUSDCarryEngine to execute repayMUSD via BorrowerOperations.
    function autonomousRescue(
        address user,
        uint256 maxRepayMusd,
        uint256 maxRadarIterations
    ) external returns (uint256 musdRepaid, uint256 icrAfter) {
        address troveProxy = userTroveProxies[user];
        if (troveProxy == address(0) || !ISortedTroves(sortedTroves).contains(troveProxy)) {
            revert NoActiveTrove(user);
        }

        RedemptionRadar memory radar = getRedemptionRadar(user, maxRadarIterations);
        if (!radar.needsAutonomousRescue) {
            revert RescueNotRequired(troveProxy, radar.currentIcr, radar.queuePercentileBps);
        }

        uint256 btcPrice = IPriceFeed(priceFeed).fetchPrice();
        uint256 desiredRepay;
        {
            uint256 collUsd = (radar.troveCollateralBtc * btcPrice) / WAD;
            uint256 targetDebt = (collUsd * WAD) / targetHealthyIcr;

            desiredRepay = radar.troveTotalDebtMusd > targetDebt
                ? (radar.troveTotalDebtMusd - targetDebt)
                : (radar.troveTotalDebtMusd / 10);

            if (maxRepayMusd > 0 && desiredRepay > maxRepayMusd) {
                desiredRepay = maxRepayMusd;
            }

            // Respect BorrowerOperations minNetDebt + gasCompensation floor
            uint256 minRemainingDebt = IBorrowerOperations(borrowerOperations).minNetDebt() +
                IBorrowerOperations(borrowerOperations).MUSD_GAS_COMPENSATION();
            if (radar.troveTotalDebtMusd <= minRemainingDebt) {
                revert InvalidAmount();
            }
            uint256 maxAllowedRepay = radar.troveTotalDebtMusd - minRemainingDebt;
            if (desiredRepay > maxAllowedRepay) {
                desiredRepay = maxAllowedRepay;
            }
            if (desiredRepay == 0) revert InvalidAmount();
        }

        // Pull MUSD from MUSDCarryEngine directly to the user's TroveProxy
        musdRepaid = carryEngine.instantUnwindToMusd(user, desiredRepay, 0, troveProxy);

        // Pre-compute O(1) upper/lower hints for new post-repayment NICR
        (address upperHint, address lowerHint) = computeOptimalHints(
            radar.troveCollateralBtc,
            radar.troveTotalDebtMusd - musdRepaid
        );

        AegisUserTroveProxy(payable(troveProxy)).executeRepayMusd(musdRepaid, upperHint, lowerHint);

        icrAfter = ITroveManager(troveManager).getCurrentICR(troveProxy, btcPrice);

        emit AutonomousRescueExecuted(
            user,
            troveProxy,
            musdRepaid,
            radar.currentIcr,
            icrAfter,
            radar.musdDebtAheadInQueue,
            upperHint,
            lowerHint
        );
    }

    /// @notice Direct debt repayment by user or keeper using caller's MUSD.
    function repayUserTroveDebt(address user, uint256 musdAmount, address upperHint, address lowerHint) external {
        if (musdAmount == 0) revert InvalidAmount();
        address troveProxy = userTroveProxies[user];
        if (troveProxy == address(0) || !ISortedTroves(sortedTroves).contains(troveProxy)) {
            revert NoActiveTrove(user);
        }

        require(IERC20(musd).transferFrom(msg.sender, troveProxy, musdAmount), "MUSD transferFrom failed");

        if (upperHint == address(0) && lowerHint == address(0)) {
            uint256 coll = ITroveManager(troveManager).getTroveColl(troveProxy);
            uint256 debt = ITroveManager(troveManager).getTroveDebt(troveProxy);
            uint256 newDebt = debt > musdAmount ? debt - musdAmount : 0;
            (upperHint, lowerHint) = computeOptimalHints(coll, newDebt);
        }

        AegisUserTroveProxy(payable(troveProxy)).executeRepayMusd(musdAmount, upperHint, lowerHint);
        emit TroveDebtRepaid(user, troveProxy, musdAmount);
    }

    // =========================================================================
    // 4. Agentic & In-Checkout Micro-Credit Draw (Track 2 x402 Integration)
    // =========================================================================

    /// @notice Draws fixed-rate MUSD micro-credit against the user's AegisTroveVault to settle an x402 payment.
    function drawMicroCredit(
        address user,
        uint256 musdAmount,
        address recipient,
        address upperHint,
        address lowerHint
    ) external returns (uint256 musdDrawn) {
        if (musdAmount == 0 || recipient == address(0)) revert InvalidAmount();
        address troveProxy = userTroveProxies[user];
        if (troveProxy == address(0) || !ISortedTroves(sortedTroves).contains(troveProxy)) {
            revert NoActiveTrove(user);
        }

        if (msg.sender != user) {
            uint256 allowed = agentCreditAllowance[user][msg.sender];
            if (allowed < musdAmount) {
                revert InsufficientCreditAllowance(allowed, musdAmount);
            }
            agentCreditAllowance[user][msg.sender] = allowed - musdAmount;
        }

        if (upperHint == address(0) && lowerHint == address(0)) {
            uint256 coll = ITroveManager(troveManager).getTroveColl(troveProxy);
            uint256 debt = ITroveManager(troveManager).getTroveDebt(troveProxy);
            uint256 fee = IBorrowerOperations(borrowerOperations).getBorrowingFee(musdAmount);
            (upperHint, lowerHint) = computeOptimalHints(coll, debt + musdAmount + fee);
        }

        AegisUserTroveProxy(payable(troveProxy)).executeWithdrawMusd(
            musdAmount,
            upperHint,
            lowerHint,
            recipient
        );

        musdDrawn = musdAmount;
        emit MicroCreditDrawn(user, msg.sender, recipient, musdDrawn, upperHint, lowerHint);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
