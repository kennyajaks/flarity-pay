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
    address public buyerWallet = address(0x888);
    
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

    function testInvoiceCreationXRP() public {
        bytes32 paymentReference = keccak256("tx-ref-1");
        uint256 amountUSD = 100 * 1e18; // 100 USD

        uint256 invoiceId = gateway.createInvoice(amountUSD, "XRP", paymentReference);
        
        (
            uint256 id,
            uint256 storedUSD,
            bytes32 storedRef,
            string memory currency,
            uint256 amountCrypto,
            bool settled
        ) = gateway.invoices(invoiceId);

        assertEq(id, 1);
        assertEq(storedUSD, amountUSD);
        assertEq(storedRef, paymentReference);
        assertEq(currency, "XRP");
        
        // Math check:
        // cryptoDue = (100 * 1e18 * 10^5 * 10^6) / (58400 * 1e18) = 171.232876 XRP
        // in drops: 171232876
        assertEq(amountCrypto, 171232876);
        assertFalse(settled);
    }

    function testInvoiceCreationBTC() public {
        bytes32 paymentReference = keccak256("tx-ref-2");
        uint256 amountUSD = 1000 * 1e18; // 1000 USD

        uint256 invoiceId = gateway.createInvoice(amountUSD, "BTC", paymentReference);
        
        (, , , , uint256 amountCrypto, ) = gateway.invoices(invoiceId);
        
        // Math check:
        // cryptoDue = (1000 * 1e18 * 10^2 * 10^8) / (5824000 * 1e18) = 0.01717032 BTC
        // in satoshis: 1717032
        assertEq(amountCrypto, 1717032);
    }

    function testPaymentSettlementSuccess() public {
        bytes32 paymentReference = keccak256("tx-ref-1");
        uint256 amountUSD = 100 * 1e18; // 100 USD
        
        // 1. Create Invoice
        uint256 invoiceId = gateway.createInvoice(amountUSD, "XRP", paymentReference);
        
        // 2. Build mock FDC proof
        IPaymentVerification.RequestBody memory request = IPaymentVerification.RequestBody({
            attestationType: "Payment",
            sourceId: "XRP",
            transactionId: keccak256("ext-tx-hash"),
            paymentReference: paymentReference,
            amount: 171232876, // Match the calculated amountCrypto
            receivingAddress: "rFlarityPayAgentAddressCoston2TestnetXRPLXXXXXXXXX"
        });
        
        bytes32[] memory emptyProof;
        IPaymentVerification.Proof memory proof = IPaymentVerification.Proof({
            merkleRoot: keccak256("root"),
            merkleProof: emptyProof,
            requestBody: request
        });
        
        // 3. Settle payment
        gateway.settlePayment(invoiceId, proof);
        
        // 4. Verify state
        (, , , , , bool settled) = gateway.invoices(invoiceId);
        assertTrue(settled);
        
        // Verify FAsset tokens were minted to merchant
        assertEq(fXrp.balanceOf(merchantWallet), 171232876);
    }

    function testPaymentSettlementFailInsufficientAmount() public {
        bytes32 paymentReference = keccak256("tx-ref-1");
        uint256 amountUSD = 100 * 1e18;
        
        uint256 invoiceId = gateway.createInvoice(amountUSD, "XRP", paymentReference);
        
        IPaymentVerification.RequestBody memory request = IPaymentVerification.RequestBody({
            attestationType: "Payment",
            sourceId: "XRP",
            transactionId: keccak256("ext-tx-hash"),
            paymentReference: paymentReference,
            amount: 171232875, // 1 drop less than required!
            receivingAddress: "rFlarityPayAgentAddressCoston2TestnetXRPLXXXXXXXXX"
        });
        
        bytes32[] memory emptyProof;
        IPaymentVerification.Proof memory proof = IPaymentVerification.Proof({
            merkleRoot: keccak256("root"),
            merkleProof: emptyProof,
            requestBody: request
        });
        
        vm.expectRevert("Paid amount is insufficient");
        gateway.settlePayment(invoiceId, proof);
    }
}
