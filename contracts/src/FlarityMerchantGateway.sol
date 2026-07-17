// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFtsoV2} from "./interfaces/IFtsoV2.sol";
import {IPaymentVerification} from "./interfaces/IPaymentVerification.sol";
import {MockFAsset} from "./MockFAsset.sol";

/**
 * @title FlarityMerchantGateway
 * @notice Core smart contract for Flarity Pay Decentralized Marketplace.
 * @dev Combines FTSOv2 price feeds (on-chain rates) and FDC payment verification (cross-chain proofs).
 */
contract FlarityMerchantGateway {
    
    enum ListingType { Product, Service }

    struct Listing {
        uint256 id;
        address seller;
        string title;
        string description;
        uint256 priceUSD;           // Product cost in USD (18 decimal precision)
        string imageUrl;
        ListingType listingType;
        bool active;
    }

    struct Review {
        uint256 id;
        address seller;
        address buyer;
        uint8 rating;                // 1 to 5 Flarity Stars
        string comment;
        uint256 timestamp;
    }

    struct Invoice {
        uint256 id;
        address buyer;               // Address of the buyer who created invoice
        address seller;              // Address of the seller receiving payment
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
    address public merchantWallet; // Default admin wallet for platform fees

    // Mapping of currency tickers to FTSOv2 feed IDs (21-bytes hex)
    mapping(string => bytes21) public ftsoFeeds;
    // Mapping of currency tickers to token decimals (XRP = 6, BTC = 8, DOGE = 8)
    mapping(string => uint8) public tokenDecimals;
    // Mapping of currency tickers to FAsset representation token contracts
    mapping(string => MockFAsset) public fAssets;

    // Database counts and mappings
    uint256 public listingCount;
    mapping(uint256 => Listing) public listings;

    uint256 public invoiceCount;
    mapping(uint256 => Invoice) public invoices;
    mapping(bytes32 => uint256) public referenceToInvoiceId;

    uint256 public reviewCount;
    mapping(address => Review[]) public sellerReviews;
    mapping(address => uint256) public sellerRatingSums;
    
    // Verified purchase check: hasPurchasedFrom[buyer][seller] = true
    mapping(address => mapping(address => bool)) public hasPurchasedFrom;

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        string title,
        uint256 priceUSD,
        ListingType listingType
    );

    event InvoiceCreated(
        uint256 indexed invoiceId,
        address indexed buyer,
        address indexed seller,
        uint256 amountUSD,
        string currency,
        uint256 amountCrypto,
        bytes32 paymentReference
    );
    
    event PaymentSettled(
        uint256 indexed invoiceId,
        bytes32 transactionId,
        uint256 amountPaid,
        uint256 fassetsMinted
    );

    event ReviewSubmitted(
        uint256 indexed reviewId,
        address indexed seller,
        address indexed buyer,
        uint8 rating,
        string comment
    );

    event ListingUpdated(
        uint256 indexed listingId,
        string title,
        uint256 priceUSD,
        bool active
    );

    event ListingDeleted(uint256 indexed listingId);

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
     * @notice Update the default platform fee wallet.
     */
    function setMerchantWallet(address _merchantWallet) external onlyOwner {
        merchantWallet = _merchantWallet;
    }

    /**
     * @notice Query the live FTSOv2 exchange rate directly on Coston2.
     */
    function getLivePrice(string memory _ticker) public view returns (uint256 price, int8 decimals) {
        bytes21 feedId = ftsoFeeds[_ticker];
        require(feedId != bytes21(0), "Unsupported price feed");
        (price, decimals, ) = ftsoV2.getFeedById(feedId);
    }

    /**
     * @notice List a new product or service for sale in the marketplace.
     */
    function listItem(
        string calldata _title,
        string calldata _description,
        uint256 _priceUSD,
        string calldata _imageUrl,
        ListingType _listingType
    ) external returns (uint256 listingId) {
        require(_priceUSD > 0, "Price must be positive");
        
        listingCount++;
        listingId = listingCount;
        
        listings[listingId] = Listing({
            id: listingId,
            seller: msg.sender,
            title: _title,
            description: _description,
            priceUSD: _priceUSD,
            imageUrl: _imageUrl,
            listingType: _listingType,
            active: true
        });
        
        emit ListingCreated(listingId, msg.sender, _title, _priceUSD, _listingType);
    }

    /**
     * @notice Edit an existing listing.
     * @dev Restricts editing to the listing seller.
     */
    function editListing(
        uint256 _listingId,
        string calldata _title,
        string calldata _description,
        uint256 _priceUSD,
        string calldata _imageUrl,
        ListingType _listingType,
        bool _active
    ) external {
        Listing storage listing = listings[_listingId];
        require(listing.id != 0, "Listing does not exist");
        require(msg.sender == listing.seller, "Only the listing seller can edit");
        require(_priceUSD > 0, "Price must be positive");

        listing.title = _title;
        listing.description = _description;
        listing.priceUSD = _priceUSD;
        listing.imageUrl = _imageUrl;
        listing.listingType = _listingType;
        listing.active = _active;

        emit ListingUpdated(_listingId, _title, _priceUSD, _active);
    }

    /**
     * @notice Delete (deactivate) an existing listing.
     * @dev Restricts deactivation to the listing seller.
     */
    function deleteListing(uint256 _listingId) external {
        Listing storage listing = listings[_listingId];
        require(listing.id != 0, "Listing does not exist");
        require(msg.sender == listing.seller, "Only the listing seller can delete");

        listing.active = false;

        emit ListingDeleted(_listingId);
    }

    /**
     * @notice Create a new checkout payment invoice associated with a specific listing.
     * @dev Dynamically computes the crypto amount due using the live FTSOv2 price oracle.
     */
    function createInvoice(
        uint256 _listingId,
        string calldata _currency,
        bytes32 _paymentReference
    ) external returns (uint256 invoiceId) {
        Listing memory listing = listings[_listingId];
        require(listing.id != 0, "Listing does not exist");
        require(listing.active, "Listing is inactive");
        require(referenceToInvoiceId[_paymentReference] == 0, "Payment reference already exists");
        
        // Fetch live exchange rate from FTSOv2
        (uint256 price, int8 decimals) = getLivePrice(_currency);
        require(price > 0, "Invalid oracle price");

        // Native decimals of the target payment token
        uint8 nativeDec = tokenDecimals[_currency];
        require(nativeDec > 0, "Unsupported currency decimals");

        // Formula: cryptoDue = (amountUSD * 10^oracleDecimals * 10^nativeDecimals) / (oraclePrice * 1e18)
        uint256 cryptoDue = (listing.priceUSD * (10 ** uint8(decimals)) * (10 ** nativeDec)) / (price * 1e18);

        invoiceCount++;
        invoiceId = invoiceCount;

        invoices[invoiceId] = Invoice({
            id: invoiceId,
            buyer: msg.sender,
            seller: listing.seller,
            amountUSD: listing.priceUSD,
            paymentReference: _paymentReference,
            currency: _currency,
            amountCrypto: cryptoDue,
            settled: false
        });

        referenceToInvoiceId[_paymentReference] = invoiceId;

        emit InvoiceCreated(invoiceId, msg.sender, listing.seller, listing.priceUSD, _currency, cryptoDue, _paymentReference);
    }

    /**
     * @notice Settle an invoice by verifying its FDC cross-chain payment proof.
     * @dev Calls the FDC verification contract, checks constraints, and mints FAssets to the Seller.
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

        // 4. Verify that the attestation type is a payment
        require(keccak256(bytes(_proof.requestBody.attestationType)) == keccak256(bytes("Payment")), "Invalid attestation type");

        // 5. Call Flare's FDC verification contract
        bool verified = fdcVerification.verifyPayment(_proof);
        require(verified, "FDC attestation proof verification failed");

        // Mark invoice as settled
        invoice.settled = true;

        // Record purchase to verify reviews
        hasPurchasedFrom[invoice.buyer][invoice.seller] = true;

        // Mint wrapped FAssets equivalent to the paid amount to the specific seller's wallet
        MockFAsset fAsset = fAssets[invoice.currency];
        uint256 mintedAmount = _proof.requestBody.amount;
        
        if (address(fAsset) != address(0)) {
            fAsset.mint(invoice.seller, mintedAmount);
        }

        emit PaymentSettled(_invoiceId, _proof.requestBody.transactionId, _proof.requestBody.amount, mintedAmount);
    }

    /**
     * @notice Submit a review for a seller using "Flarity Stars" (1-5).
     * @dev Restricts reviews to buyers with verified transactions with that seller.
     */
    function submitReview(
        address _seller,
        uint8 _rating,
        string calldata _comment
    ) external {
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5 Flarity Stars");
        require(hasPurchasedFrom[msg.sender][_seller], "Only verified buyers can review");

        reviewCount++;
        
        Review memory review = Review({
            id: reviewCount,
            seller: _seller,
            buyer: msg.sender,
            rating: _rating,
            comment: _comment,
            timestamp: block.timestamp
        });

        sellerReviews[_seller].push(review);
        sellerRatingSums[_seller] += _rating;

        emit ReviewSubmitted(reviewCount, _seller, msg.sender, _rating, _comment);
    }

    /**
     * @notice Helper to get the total reviews count for a seller.
     */
    function getReviewsCount(address _seller) external view returns (uint256) {
        return sellerReviews[_seller].length;
    }

    /**
     * @notice Helper to get all reviews for a seller.
     */
    function getSellerReviews(address _seller) external view returns (Review[] memory) {
        return sellerReviews[_seller];
    }
}
