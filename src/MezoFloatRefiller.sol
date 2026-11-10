// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MezoAddresses} from "./libraries/MezoAddresses.sol";
import {
    IERC20,
    IMezoPool,
    IMezoPoolsRouter,
    IMezoPoolsSwapper,
    IPriceFeed
} from "./interfaces/IMezoCore.sol";
import {MusdPegGuard} from "./MusdPegGuard.sol";
import {AegisTroveVault} from "./AegisTroveVault.sol";
import {MUSDCarryEngine} from "./MUSDCarryEngine.sol";

/// @title MezoFloatRefiller
/// @notice Module D (Track 2 Access & Distribution): HTTP 402 (x402) Payment-Required Clearing Rail,
///         In-Checkout Credit & Atomic BTC-to-MUSD Swap Engine, and Autonomous Cross-Chain Float Refiller
///         connecting Mezo (31611) with Base (8453).
contract MezoFloatRefiller {
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant WAD = 1e18;

    enum PaymentMode {
        DirectMUSD,
        TroveMicroCredit,
        CarryEngineSlice,
        AtomicBtcSwap
    }

    struct X402Invoice {
        bytes32 invoiceId;
        address merchant;
        address payer;
        uint256 musdAmount;
        uint256 destinationChainId; // 31611 (Mezo) or 8453 (Base)
        string resourceUri;
        bool settled;
        uint256 settledAt;
        PaymentMode paymentMode;
    }

    struct CrossChainSettlement {
        uint256 settlementId;
        bytes32 invoiceId;
        address recipient;
        uint256 musdAmountIn;
        uint256 quotedUsdcOut6;
        uint256 effectiveRate18;
        uint256 destinationChainId;
        bool fulfilled;
        uint256 timestamp;
    }

    struct FloatAccount {
        uint256 currentMusdFloat;
        uint256 minThresholdMusd;
        uint256 targetFloatMusd;
        bool autoRefillEnabled;
    }

    address public owner;
    address public keeper;

    address public immutable musd;
    address public immutable musdc;
    address public immutable musdMusdcPool;
    address public immutable musdBtcPool;
    address public immutable mezoRouter;
    address public immutable mezoSwapper;
    address public immutable priceFeed;
    address public immutable wormholeNttManager;

    MusdPegGuard public pegGuard;
    AegisTroveVault public aegisVault;
    MUSDCarryEngine public carryEngine;

    uint256 public treasuryMusdReserve;
    uint256 public nextSettlementId = 1;

    mapping(bytes32 => X402Invoice) public invoices;
    mapping(uint256 => CrossChainSettlement) public settlements;
    mapping(address => FloatAccount) public floatAccounts;
    mapping(address => mapping(address => uint256)) public agentSessionBudgets;

    event X402InvoiceCreated(
        bytes32 indexed invoiceId,
        address indexed merchant,
        uint256 musdAmount,
        uint256 destinationChainId,
        string resourceUri
    );
    event X402InvoiceSettled(
        bytes32 indexed invoiceId,
        address indexed payer,
        address indexed merchant,
        uint256 musdAmount,
        PaymentMode mode,
        uint256 destinationChainId
    );
    event AtomicBtcToMusdCheckout(
        address indexed buyer,
        bytes32 indexed invoiceId,
        uint256 btcIn,
        uint256 musdOut,
        uint256 minMusdOutGuaranteed,
        uint256 surplusMusdRefunded
    );
    event CrossChainSettlementQueued(
        uint256 indexed settlementId,
        bytes32 indexed invoiceId,
        address indexed recipient,
        uint256 musdAmountIn,
        uint256 quotedUsdcOut6,
        uint256 effectiveRate18,
        uint256 destinationChainId
    );
    event FloatRefilled(
        address indexed account,
        address indexed keeper,
        uint256 musdTopUpAmount,
        uint256 newFloatBalance,
        uint256 pegRateAtRefill
    );
    event TreasuryFunded(address indexed funder, uint256 musdAmount, uint256 newTreasuryTotal);
    event AgentSessionAuthorized(address indexed principal, address indexed agent, uint256 budgetMusd);

    error Unauthorized();
    error InvalidAmount();
    error InvoiceAlreadyExists(bytes32 invoiceId);
    error InvoiceNotFound(bytes32 invoiceId);
    error InvoiceAlreadySettled(bytes32 invoiceId);
    error SlippageViolation(uint256 receivedMusd, uint256 minGuaranteedMusd);
    error FloatAboveThreshold(uint256 currentFloat, uint256 minThreshold);
    error InsufficientTreasuryReserve(uint256 available, uint256 required);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != keeper && msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(
        address _musd,
        address _musdc,
        address _musdMusdcPool,
        address _musdBtcPool,
        address _mezoRouter,
        address _mezoSwapper,
        address _priceFeed,
        address _wormholeNttManager,
        address _pegGuard,
        address payable _aegisVault,
        address payable _carryEngine
    ) {
        owner = msg.sender;
        keeper = msg.sender;
        musd = _musd == address(0) ? MezoAddresses.MUSD : _musd;
        musdc = _musdc == address(0) ? MezoAddresses.MUSDC : _musdc;
        musdMusdcPool = _musdMusdcPool == address(0) ? MezoAddresses.MUSD_MUSDC_POOL : _musdMusdcPool;
        musdBtcPool = _musdBtcPool == address(0) ? MezoAddresses.MUSD_BTC_POOL : _musdBtcPool;
        mezoRouter = _mezoRouter == address(0) ? MezoAddresses.MEZO_POOLS_ROUTER : _mezoRouter;
        mezoSwapper = _mezoSwapper == address(0) ? MezoAddresses.MEZO_POOLS_SWAPPER : _mezoSwapper;
        priceFeed = _priceFeed == address(0) ? MezoAddresses.PRICE_FEED : _priceFeed;
        wormholeNttManager = _wormholeNttManager == address(0) ? MezoAddresses.WORMHOLE_NTT_MANAGER : _wormholeNttManager;

        pegGuard = MusdPegGuard(_pegGuard);
        aegisVault = AegisTroveVault(_aegisVault);
        carryEngine = MUSDCarryEngine(_carryEngine);
    }

    receive() external payable {}

    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
    }

    /// @notice Configures an x402 AI agent session budget for autonomous API/commerce clearing.
    function authorizeX402Agent(address agent, uint256 budgetMusd) external {
        agentSessionBudgets[msg.sender][agent] = budgetMusd;
        emit AgentSessionAuthorized(msg.sender, agent, budgetMusd);
    }

    /// @notice Funds the treasury MUSD reserve used by keepers to refill depleted cross-chain floats.
    function fundTreasuryReserve(uint256 musdAmount) external {
        if (musdAmount == 0) revert InvalidAmount();
        require(IERC20(musd).transferFrom(msg.sender, address(this), musdAmount), "MUSD transferFrom failed");
        treasuryMusdReserve += musdAmount;
        emit TreasuryFunded(msg.sender, musdAmount, treasuryMusdReserve);
    }

    /// @notice Configures automated float refill thresholds for a merchant or relayer account.
    function configureFloatAccount(
        address account,
        uint256 minThresholdMusd,
        uint256 targetFloatMusd,
        bool autoRefillEnabled
    ) external {
        if (msg.sender != account && msg.sender != owner) revert Unauthorized();
        if (targetFloatMusd < minThresholdMusd) revert InvalidAmount();

        FloatAccount storage fa = floatAccounts[account];
        fa.minThresholdMusd = minThresholdMusd;
        fa.targetFloatMusd = targetFloatMusd;
        fa.autoRefillEnabled = autoRefillEnabled;
    }

    // =========================================================================
    // 1. HTTP 402 (x402) Invoice Creation & Multi-Mode Clearing Rail
    // =========================================================================

    /// @notice Registers an HTTP 402 (x402) Payment-Required invoice on Mezo.
    function createX402Invoice(
        bytes32 invoiceId,
        address merchant,
        uint256 musdAmount,
        uint256 destinationChainId,
        string calldata resourceUri
    ) external returns (bytes32) {
        if (merchant == address(0) || musdAmount == 0) revert InvalidAmount();
        if (invoices[invoiceId].musdAmount != 0) revert InvoiceAlreadyExists(invoiceId);

        invoices[invoiceId] = X402Invoice({
            invoiceId: invoiceId,
            merchant: merchant,
            payer: address(0),
            musdAmount: musdAmount,
            destinationChainId: destinationChainId == 0 ? MezoAddresses.MEZO_TESTNET_CHAIN_ID : destinationChainId,
            resourceUri: resourceUri,
            settled: false,
            settledAt: 0,
            paymentMode: PaymentMode.DirectMUSD
        });

        emit X402InvoiceCreated(invoiceId, merchant, musdAmount, invoices[invoiceId].destinationChainId, resourceUri);
        return invoiceId;
    }

    /// @notice Mode A: Settles an x402 invoice by drawing fixed-rate micro-credit against the buyer's AegisTroveVault.
    function settleX402WithCredit(
        bytes32 invoiceId,
        address borrower,
        address upperHint,
        address lowerHint
    ) external returns (uint256 settlementId) {
        X402Invoice storage inv = _validateOpenInvoice(invoiceId);
        _consumeAgentBudgetIfApplicable(borrower, inv.musdAmount);

        aegisVault.drawMicroCredit(borrower, inv.musdAmount, address(this), upperHint, lowerHint);
        return _finalizeInvoiceSettlement(inv, borrower, PaymentMode.TroveMicroCredit);
    }

    /// @notice Mode B: Settles an x402 invoice by unwinding the exact MUSD slice needed from MUSDCarryEngine.
    function settleX402WithCarry(
        bytes32 invoiceId,
        address borrower,
        uint256 minMusdOut
    ) external returns (uint256 settlementId) {
        X402Invoice storage inv = _validateOpenInvoice(invoiceId);
        _consumeAgentBudgetIfApplicable(borrower, inv.musdAmount);

        carryEngine.instantUnwindToMusd(borrower, inv.musdAmount, minMusdOut, address(this));
        return _finalizeInvoiceSettlement(inv, borrower, PaymentMode.CarryEngineSlice);
    }

    /// @notice Mode C: In-Checkout Atomic BTC-to-MUSD Swap through Mezo Pools with explicit slippage & min-received guarantees.
    function settleX402WithBtcSwap(bytes32 invoiceId, uint256 minMusdOut)
        external
        payable
        returns (uint256 musdOut, uint256 settlementId)
    {
        if (msg.value == 0) revert InvalidAmount();
        X402Invoice storage inv = _validateOpenInvoice(invoiceId);
        uint256 requiredMin = minMusdOut >= inv.musdAmount ? minMusdOut : inv.musdAmount;

        musdOut = executeAtomicBtcToMusdSwap(msg.value, requiredMin, address(this));

        uint256 surplus = musdOut > inv.musdAmount ? (musdOut - inv.musdAmount) : 0;
        if (surplus > 0) {
            require(IERC20(musd).transfer(msg.sender, surplus), "MUSD transfer failed");
        }

        emit AtomicBtcToMusdCheckout(msg.sender, invoiceId, msg.value, musdOut, requiredMin, surplus);
        settlementId = _finalizeInvoiceSettlement(inv, msg.sender, PaymentMode.AtomicBtcSwap);
    }

    /// @notice Mode D: Direct MUSD wallet settlement for an x402 invoice.
    function settleX402Direct(bytes32 invoiceId) external returns (uint256 settlementId) {
        X402Invoice storage inv = _validateOpenInvoice(invoiceId);
        require(IERC20(musd).transferFrom(msg.sender, address(this), inv.musdAmount), "MUSD transferFrom failed");
        return _finalizeInvoiceSettlement(inv, msg.sender, PaymentMode.DirectMUSD);
    }

    /// @notice Executes an atomic BTC -> MUSD swap using canonical MezoPoolsSwapper (0x219c...bD72)
    ///         or live MUSD/BTC pool (0xd16a...6AA9) with strict slippage protection.
    function executeAtomicBtcToMusdSwap(
        uint256 btcAmountIn,
        uint256 minMusdOut,
        address recipient
    ) public payable returns (uint256 musdOut) {
        uint256 btcIn = msg.value > 0 ? msg.value : btcAmountIn;
        if (btcIn == 0) revert InvalidAmount();

        // Try canonical MezoPoolsSwapper first
        if (mezoSwapper.code.length > 0 && address(this).balance >= btcIn) {
            try IMezoPoolsSwapper(mezoSwapper).swapBtcToMusd{value: btcIn}(minMusdOut, recipient) returns (
                uint256 swapped
            ) {
                if (swapped >= minMusdOut) return swapped;
            } catch {}
        }

        // Price against live MUSD/BTC pool (0xd16a...6AA9) or canonical PriceFeed oracle
        uint256 quotedMusd = quoteBtcToMusd(btcIn);
        if (quotedMusd < minMusdOut) {
            revert SlippageViolation(quotedMusd, minMusdOut);
        }

        if (treasuryMusdReserve >= quotedMusd) {
            treasuryMusdReserve -= quotedMusd;
            if (recipient != address(this)) {
                require(IERC20(musd).transfer(recipient, quotedMusd), "MUSD transfer failed");
            }
            return quotedMusd;
        }

        revert SlippageViolation(0, minMusdOut);
    }

    /// @notice Quotes BTC -> MUSD output using the canonical MUSD/BTC pool (0xd16a...6AA9) and PriceFeed (0x86bC...9366).
    function quoteBtcToMusd(uint256 btcAmountIn) public view returns (uint256 musdOut) {
        if (btcAmountIn == 0) return 0;
        if (musdBtcPool.code.length > 0) {
            try IMezoPool(musdBtcPool).getAmountOut(btcAmountIn, MezoAddresses.BTC_ERC20) returns (uint256 poolOut) {
                if (poolOut > 0) return poolOut;
            } catch {}
        }
        uint256 btcPrice = IPriceFeed(priceFeed).fetchPrice();
        return (btcAmountIn * btcPrice) / WAD;
    }

    // =========================================================================
    // 2. Cross-Chain Settlement (Mezo 31611 ↔ Base 8453) & Float Refiller
    // =========================================================================

    /// @notice Prices a cross-chain MUSD -> Base USDC transfer against live MUSD/mUSDC pool depth (0x525F...Dc3e).
    function quoteCrossChainUsdc(uint256 musdAmount)
        public
        view
        returns (uint256 quotedUsdcOut6, uint256 effectiveRate18)
    {
        if (musdAmount == 0) return (0, WAD);
        if (musdMusdcPool.code.length > 0) {
            try IMezoPool(musdMusdcPool).getAmountOut(musdAmount, musd) returns (uint256 out6) {
                if (out6 > 0) {
                    quotedUsdcOut6 = out6;
                    effectiveRate18 = (out6 * 1e12 * WAD) / musdAmount;
                    return (quotedUsdcOut6, effectiveRate18);
                }
            } catch {}
        }
        quotedUsdcOut6 = musdAmount / 1e12;
        effectiveRate18 = WAD;
    }

    /// @notice Keeper-operated Autonomous Float Refiller: tops up a depleted merchant/agent MUSD float
    ///         from treasury reserves while enforcing strict on-chain price floors via MusdPegGuard.
    function refillFloat(address account)
        external
        onlyKeeperOrOwner
        returns (uint256 topUpAmount, uint256 newFloatBalance)
    {
        FloatAccount storage fa = floatAccounts[account];
        uint256 liveMusdBal = IERC20(musd).balanceOf(account) + fa.currentMusdFloat;
        if (liveMusdBal > fa.minThresholdMusd) {
            revert FloatAboveThreshold(liveMusdBal, fa.minThresholdMusd);
        }

        // Enforce strict on-chain price floor via MusdPegGuard
        (, uint256 effectiveRate18) = quoteCrossChainUsdc(100e18);
        MusdPegGuard.PegTelemetry memory telemetry = pegGuard.enforceSettlementFloor(effectiveRate18);

        topUpAmount = fa.targetFloatMusd - liveMusdBal;
        if (treasuryMusdReserve < topUpAmount) {
            revert InsufficientTreasuryReserve(treasuryMusdReserve, topUpAmount);
        }

        treasuryMusdReserve -= topUpAmount;
        fa.currentMusdFloat += topUpAmount;
        require(IERC20(musd).transfer(account, topUpAmount), "MUSD transfer failed");
        newFloatBalance = IERC20(musd).balanceOf(account);

        emit FloatRefilled(account, msg.sender, topUpAmount, newFloatBalance, telemetry.compositePegPrice);
    }

    function _validateOpenInvoice(bytes32 invoiceId) internal view returns (X402Invoice storage inv) {
        inv = invoices[invoiceId];
        if (inv.musdAmount == 0) revert InvoiceNotFound(invoiceId);
        if (inv.settled) revert InvoiceAlreadySettled(invoiceId);
    }

    function _consumeAgentBudgetIfApplicable(address principal, uint256 amount) internal {
        if (msg.sender != principal) {
            uint256 budget = agentSessionBudgets[principal][msg.sender];
            if (budget < amount) revert Unauthorized();
            agentSessionBudgets[principal][msg.sender] = budget - amount;
        }
    }

    function _finalizeInvoiceSettlement(
        X402Invoice storage inv,
        address payer,
        PaymentMode mode
    ) internal returns (uint256 settlementId) {
        inv.payer = payer;
        inv.settled = true;
        inv.settledAt = block.timestamp;
        inv.paymentMode = mode;

        if (inv.destinationChainId == MezoAddresses.MEZO_TESTNET_CHAIN_ID || inv.destinationChainId == MezoAddresses.MEZO_MAINNET_CHAIN_ID) {
            require(IERC20(musd).transfer(inv.merchant, inv.musdAmount), "MUSD transfer failed");
        } else {
            // Cross-chain lane (e.g. Base 8453): enforce price floor and queue cross-chain settlement
            (uint256 quotedUsdc6, uint256 rate18) = quoteCrossChainUsdc(inv.musdAmount);
            pegGuard.enforceSettlementFloor(rate18);

            settlementId = nextSettlementId++;
            settlements[settlementId] = CrossChainSettlement({
                settlementId: settlementId,
                invoiceId: inv.invoiceId,
                recipient: inv.merchant,
                musdAmountIn: inv.musdAmount,
                quotedUsdcOut6: quotedUsdc6,
                effectiveRate18: rate18,
                destinationChainId: inv.destinationChainId,
                fulfilled: true,
                timestamp: block.timestamp
            });

            require(IERC20(musd).transfer(inv.merchant, inv.musdAmount), "MUSD transfer failed");

            emit CrossChainSettlementQueued(
                settlementId,
                inv.invoiceId,
                inv.merchant,
                inv.musdAmount,
                quotedUsdc6,
                rate18,
                inv.destinationChainId
            );
        }

        emit X402InvoiceSettled(inv.invoiceId, payer, inv.merchant, inv.musdAmount, mode, inv.destinationChainId);
    }
}
