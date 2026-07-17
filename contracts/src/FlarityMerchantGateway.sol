// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFtsoV2} from "./interfaces/IFtsoV2.sol";
import {IPaymentVerification} from "./interfaces/IPaymentVerification.sol";
import {MockFAsset} from "./MockFAsset.sol";

/**
 * @title FlarityMerchantGateway
 * @notice Core smart contract for Flarity Pay.
 * @dev Combines FTSOv2 price feeds (on-chain rates) and FDC payment verification (cross-chain proofs).
 */
contract FlarityMerchantGateway {
    
    struct Invoice {
        uint256 id;
        uint256 amountUSD;           // Invoice amount in USD (18 decimal precision)
        bytes32 paymentReference;    // Unique 32-byte reference generated on checkout
        string currency;             // Target cryptocurrency ("XRP", "BTC", "DOGE")
        uint256 amountCrypto;        // Crypto due (calculated dynamically via FTSOv2)
        bool settled;                // Settlement status
    }

    // Coston2 standard address mappings
    IFtsoV2 public immutable ftsoV2;
    IPaymentVerification public fdcVerification;
    address public owner;
    address public merchantWallet;

    // Mapping of currency tickers to FTSOv2 feed IDs (21-bytes hex)
    mapping(string => bytes21) public ftsoFeeds;
    // Mapping of currency tickers to token decimals (XRP = 6, BTC = 8, DOGE = 8)
    mapping(string => uint8) public tokenDecimals;
    // Mapping of currency tickers to FAsset representation token contracts
    mapping(string => MockFAsset) public fAssets;

    // Invoice storage
    uint256 public invoiceCount;
    mapping(uint256 => Invoice) public invoices;
    mapping(bytes32 => uint256) public referenceToInvoiceId;

    event InvoiceCreated(
        uint256 indexed invoiceId,
        uint256 amountUSD,
        string currency,
        uint256 amountCrypto,
        bytes32 indexed paymentReference
    );
    
    event PaymentSettled(
        uint256 indexed invoiceId,
        bytes32 transactionId,
        uint256 amountPaid,
        uint256 fassetsMinted
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can execute this");
        _;
    }

    constructor(
        address _ftsoV2,
        address _fdcVerification,
        address _merchantWallet
    ) {
        owner = msg.sender;
        ftsoV2 = IFtsoV2(_ftsoV2);
        fdcVerification = IPaymentVerification(_fdcVerification);
        merchantWallet = _merchantWallet;

        // Initialize default FTSOv2 feed IDs for Coston2
        ftsoFeeds["FLR"] = 0x01464c522f55534400000000000000000000000000;
        ftsoFeeds["BTC"] = 0x014254432f55534400000000000000000000000000;
        ftsoFeeds["XRP"] = 0x015852502f55534400000000000000000000000000;
        ftsoFeeds["DOGE"] = 0x01444f47452f555344000000000000000000000000;

        // Initialize default native token decimals
        tokenDecimals["FLR"] = 18;
        tokenDecimals["XRP"] = 6;
        tokenDecimals["BTC"] = 8;
        tokenDecimals["DOGE"] = 8;
    }

    /**
     * @notice Set or update FAsset contract mapping.
     */
    function setFAsset(string calldata _ticker, address _fAssetAddress) external onlyOwner {
        fAssets[_ticker] = MockFAsset(_fAssetAddress);
    }

    /**
     * @notice Update FDC verification contract.
     */
    function setFdcVerification(address _fdcVerification) external onlyOwner {
        fdcVerification = IPaymentVerification(_fdcVerification);
    }

    /**
     * @notice Update the merchant settlement wallet.
     */
    function setMerchantWallet(address _merchantWallet) external onlyOwner {
        merchantWallet = _merchantWallet;
    }

    /**
     * @notice Query the live FTSOv2 exchange rate directly on Coston2.
     * @param _ticker The ticker symbol (e.g. "XRP").
     * @return price The price scaled by 10^decimals.
     * @return decimals The scale factor.
     */
    function getLivePrice(string memory _ticker) public view returns (uint256 price, int8 decimals) {
        bytes21 feedId = ftsoFeeds[_ticker];
        require(feedId != bytes21(0), "Unsupported price feed");
        (price, decimals, ) = ftsoV2.getFeedById(feedId);
    }

    /**
     * @notice Create a new checkout payment invoice.
     * @dev Dynamically computes the crypto amount due using the live FTSOv2 price oracle.
     * @param _amountUSD The invoice cost in USD (18 decimal precision).
     * @param _currency The target settlement currency ("XRP", "BTC", "DOGE").
     * @param _paymentReference The unique payment reference generated on checkout.
     * @return invoiceId The generated invoice identifier.
     */
    function createInvoice(
        uint256 _amountUSD,
        string calldata _currency,
        bytes32 _paymentReference
    ) external returns (uint256 invoiceId) {
        require(_amountUSD > 0, "Amount must be positive");
        require(referenceToInvoiceId[_paymentReference] == 0, "Payment reference already exists");
        
        // Fetch live exchange rate from FTSOv2
        (uint256 price, int8 decimals) = getLivePrice(_currency);
        require(price > 0, "Invalid oracle price");

        // Native decimals of the target payment token
        uint8 nativeDec = tokenDecimals[_currency];
        require(nativeDec > 0, "Unsupported currency decimals");

        // Formula: cryptoDue = (amountUSD * 10^oracleDecimals * 10^nativeDecimals) / (oraclePrice * 1e18)
        // This ensures the calculated crypto is correctly scaled to its base units (e.g. satoshis, drops).
        uint256 cryptoDue = (_amountUSD * (10 ** uint8(decimals)) * (10 ** nativeDec)) / (price * 1e18);

        invoiceCount++;
        invoiceId = invoiceCount;

        invoices[invoiceId] = Invoice({
            id: invoiceId,
            amountUSD: _amountUSD,
            paymentReference: _paymentReference,
            currency: _currency,
            amountCrypto: cryptoDue,
            settled: false
        });

        referenceToInvoiceId[_paymentReference] = invoiceId;

        emit InvoiceCreated(invoiceId, _amountUSD, _currency, cryptoDue, _paymentReference);
    }

    /**
     * @notice Settle an invoice by verifying its FDC cross-chain payment proof.
     * @dev Calls the FDC verification contract, checks constraints, and mints FAssets.
     * @param _invoiceId The invoice ID to settle.
     * @param _proof The FDC verification proof structure.
     */
    function settlePayment(
        uint256 _invoiceId,
        IPaymentVerification.Proof calldata _proof
    ) external {
        Invoice storage invoice = invoices[_invoiceId];
        require(invoice.id != 0, "Invoice does not exist");
        require(!invoice.settled, "Invoice already settled");

        // 1. Verify that the payment reference matches the invoice
        require(_proof.requestBody.paymentReference == invoice.paymentReference, "Payment reference mismatch");

        // 2. Verify that the payment currency match the invoice source chain
        require(keccak256(bytes(_proof.requestBody.sourceId)) == keccak256(bytes(invoice.currency)), "Currency chain mismatch");

        // 3. Verify that the payment amount meets or exceeds the required amount
        require(_proof.requestBody.amount >= invoice.amountCrypto, "Paid amount is insufficient");

        // 4. Verify that the attestation type is a standard payment
        require(keccak256(bytes(_proof.requestBody.attestationType)) == keccak256(bytes("Payment")), "Invalid attestation type");

        // 5. Call Flare's FDC verification contract
        bool verified = fdcVerification.verifyPayment(_proof);
        require(verified, "FDC attestation proof verification failed");

        // Mark invoice as settled
        invoice.settled = true;

        // Mint wrapped FAssets equivalent to the paid amount to the merchant's wallet
        MockFAsset fAsset = fAssets[invoice.currency];
        uint256 mintedAmount = _proof.requestBody.amount;
        
        if (address(fAsset) != address(0)) {
            fAsset.mint(merchantWallet, mintedAmount);
        }

        emit PaymentSettled(_invoiceId, _proof.requestBody.transactionId, _proof.requestBody.amount, mintedAmount);
    }
}
