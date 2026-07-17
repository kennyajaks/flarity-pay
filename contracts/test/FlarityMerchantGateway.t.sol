// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FlarityMerchantGateway} from "../src/FlarityMerchantGateway.sol";
import {MockFtsoV2} from "../src/MockFtsoV2.sol";
import {MockFdcVerification} from "../src/MockFdcVerification.sol";
import {MockFAsset} from "../src/MockFAsset.sol";
import {IPaymentVerification} from "../src/interfaces/IPaymentVerification.sol";

contract FlarityMerchantGatewayTest is Test {
    FlarityMerchantGateway public gateway;
    MockFtsoV2 public mockFtso;
    MockFdcVerification public mockFdc;
    
    MockFAsset public fXrp;
    MockFAsset public fBtc;
    
    address public merchantWallet = address(0x999);
    address public sellerAddress = address(0x123);
    address public buyerAddress = address(0x456);
    
    bytes21 public constant XRP_FEED = 0x015852502f55534400000000000000000000000000;
    bytes21 public constant BTC_FEED = 0x014254432f55534400000000000000000000000000;

    function setUp() public {
        // Deploy mock dependencies
        mockFtso = new MockFtsoV2();
        mockFdc = new MockFdcVerification();
        
        // Deploy Gateway
        gateway = new FlarityMerchantGateway(
            address(mockFtso),
            address(mockFdc),
            merchantWallet
        );
        
        // Deploy FAssets
        fXrp = new MockFAsset("Wrapped XRP FAsset", "fXRP", 6);
        fBtc = new MockFAsset("Wrapped BTC FAsset", "fBTC", 8);
        
        // Transfer gateway privileges to FlarityMerchantGateway contract
        fXrp.setGateway(address(gateway));
        fBtc.setGateway(address(gateway));
        
        // Configure Gateway mapping
        gateway.setFAsset("XRP", address(fXrp));
        gateway.setFAsset("BTC", address(fBtc));
        
        // Set up mock prices
        // 1 XRP = $0.58400 (5 decimals)
        mockFtso.setPrice(XRP_FEED, 58400, 5);
        // 1 BTC = $58,240.00 (2 decimals)
        mockFtso.setPrice(BTC_FEED, 5824000, 2);
    }

    function testListItem() public {
        vm.prank(sellerAddress);
        uint256 listingId = gateway.listItem(
            "Solidity Contract Audit",
            "Professional smart contract vulnerability check.",
            150 * 1e18, // $150.00
            "http://audit-mock.jpg",
            FlarityMerchantGateway.ListingType.Service
        );

        assertEq(listingId, 1);
        (
            uint256 id,
            address seller,
            string memory title,
            string memory description,
            uint256 priceUSD,
            string memory imageUrl,
            FlarityMerchantGateway.ListingType listingType,
            bool active
        ) = gateway.listings(listingId);

        assertEq(id, 1);
        assertEq(seller, sellerAddress);
        assertEq(title, "Solidity Contract Audit");
        assertEq(description, "Professional smart contract vulnerability check.");
        assertEq(priceUSD, 150 * 1e18);
        assertEq(imageUrl, "http://audit-mock.jpg");
        assertTrue(listingType == FlarityMerchantGateway.ListingType.Service);
        assertTrue(active);
    }

    function testInvoiceCreationXRP() public {
        // 1. Create a listing
        vm.prank(sellerAddress);
        uint256 listingId = gateway.listItem(
            "Flarity Ledger Vault",
            "Sleek and secure digital vault.",
            100 * 1e18, // 100 USD
            "http://vault.jpg",
            FlarityMerchantGateway.ListingType.Product
        );

        // 2. Create invoice
        bytes32 paymentReference = keccak256("tx-ref-1");
        vm.prank(buyerAddress);
        uint256 invoiceId = gateway.createInvoice(listingId, "XRP", paymentReference);
        
        (
            uint256 id,
            address buyer,
            address seller,
            uint256 storedUSD,
            bytes32 storedRef,
            string memory currency,
            uint256 amountCrypto,
            bool settled
        ) = gateway.invoices(invoiceId);

        assertEq(id, 1);
        assertEq(buyer, buyerAddress);
        assertEq(seller, sellerAddress);
        assertEq(storedUSD, 100 * 1e18);
        assertEq(storedRef, paymentReference);
        assertEq(currency, "XRP");
        
        // Math check:
        // cryptoDue = (100 * 1e18 * 10^5 * 10^6) / (58400 * 1e18) = 171.232876 XRP
        // in drops: 171232876
        assertEq(amountCrypto, 171232876);
        assertFalse(settled);
    }

    function testInvoiceCreationBTC() public {
        vm.prank(sellerAddress);
        uint256 listingId = gateway.listItem(
            "Workstation Core",
            "High-end visual processing unit.",
            1000 * 1e18, // 1000 USD
            "http://workstation.jpg",
            FlarityMerchantGateway.ListingType.Product
        );

        bytes32 paymentReference = keccak256("tx-ref-2");
        vm.prank(buyerAddress);
        uint256 invoiceId = gateway.createInvoice(listingId, "BTC", paymentReference);
        
        (, , , , , , uint256 amountCrypto, ) = gateway.invoices(invoiceId);
        
        // Math check:
        // cryptoDue = (1000 * 1e18 * 10^2 * 10^8) / (5824000 * 1e18) = 0.01717032 BTC
        // in satoshis: 1717032
        assertEq(amountCrypto, 1717032);
    }

    function testPaymentSettlementSuccessAndDirectSellerPayout() public {
        vm.prank(sellerAddress);
        uint256 listingId = gateway.listItem(
            "Custom Keyboard",
            "Mechanical cyberpunk keyboard.",
            100 * 1e18,
            "http://kb.jpg",
            FlarityMerchantGateway.ListingType.Product
        );

        bytes32 paymentReference = keccak256("tx-ref-1");
        vm.prank(buyerAddress);
        uint256 invoiceId = gateway.createInvoice(listingId, "XRP", paymentReference);
        
        // Build mock FDC proof
        IPaymentVerification.RequestBody memory request = IPaymentVerification.RequestBody({
            attestationType: "Payment",
            sourceId: "XRP",
            transactionId: keccak256("ext-tx-hash"),
            paymentReference: paymentReference,
            amount: 171232876, 
            receivingAddress: "rFlarityPayAgentAddressCoston2TestnetXRPLXXXXXXXXX"
        });
        
        bytes32[] memory emptyProof;
        IPaymentVerification.Proof memory proof = IPaymentVerification.Proof({
            merkleRoot: keccak256("root"),
            merkleProof: emptyProof,
            requestBody: request
        });
        
        // Settle payment
        gateway.settlePayment(invoiceId, proof);
        
        // Verify state
        (, , , , , , , bool settled) = gateway.invoices(invoiceId);
        assertTrue(settled);
        
        // Verify FAsset tokens were minted directly to the SELLER (not the admin merchantWallet)
        assertEq(fXrp.balanceOf(sellerAddress), 171232876);
        assertEq(fXrp.balanceOf(merchantWallet), 0);
    }

    function testReviewsSystem() public {
        // 1. Setup seller, buyer, listing, invoice, and payment settlement
        vm.prank(sellerAddress);
        uint256 listingId = gateway.listItem(
            "Audit Service",
            "Contract audit",
            100 * 1e18,
            "http://audit.jpg",
            FlarityMerchantGateway.ListingType.Service
        );

        bytes32 paymentReference = keccak256("review-ref-1");
        vm.prank(buyerAddress);
        uint256 invoiceId = gateway.createInvoice(listingId, "XRP", paymentReference);

        IPaymentVerification.RequestBody memory request = IPaymentVerification.RequestBody({
            attestationType: "Payment",
            sourceId: "XRP",
            transactionId: keccak256("ext-tx-hash-2"),
            paymentReference: paymentReference,
            amount: 171232876,
            receivingAddress: "rFlarityPayAgentAddressCoston2TestnetXRPLXXXXXXXXX"
        });
        
        bytes32[] memory emptyProof;
        IPaymentVerification.Proof memory proof = IPaymentVerification.Proof({
            merkleRoot: keccak256("root"),
            merkleProof: emptyProof,
            requestBody: request
        });

        // Settle transaction
        gateway.settlePayment(invoiceId, proof);

        // 2. Submit review from verified buyer
        vm.prank(buyerAddress);
        gateway.submitReview(sellerAddress, 5, "Outstanding audit service, found all critical bugs!");

        // 3. Assert review was saved correctly
        assertEq(gateway.getReviewsCount(sellerAddress), 1);
        
        FlarityMerchantGateway.Review[] memory reviews = gateway.getSellerReviews(sellerAddress);
        assertEq(reviews[0].buyer, buyerAddress);
        assertEq(reviews[0].rating, 5);
        assertEq(reviews[0].comment, "Outstanding audit service, found all critical bugs!");

        // 4. Test review submission from unverified buyer (should fail)
        address hacker = address(0x666);
        vm.prank(hacker);
        vm.expectRevert("Only verified buyers can review");
        gateway.submitReview(sellerAddress, 4, "Trying to submit fake review.");
    }
}
