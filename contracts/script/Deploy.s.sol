// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {FlarityMerchantGateway} from "../src/FlarityMerchantGateway.sol";
import {MockFdcVerification} from "../src/MockFdcVerification.sol";
import {MockFAsset} from "../src/MockFAsset.sol";

contract DeployFlarityPay is Script {
    // Official Coston2 FTSOv2 address
    address public constant COSTON2_FTSO_V2 = 0x7BDE3Df0624114eDB3A67dFe6753e62f4e7c1d20;

    function run() external {
        // Load private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("COSTON2_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying Flarity Pay to Coston2 Testnet...");
        console.log("Deployer Address:", deployerAddress);

        // 1. Deploy Mock FDC Verification contract
        MockFdcVerification fdc = new MockFdcVerification();
        console.log("Deployed MockFdcVerification at:", address(fdc));

        // 2. Deploy core FlarityMerchantGateway contract
        // We set the merchant wallet to the deployer's address for simplicity
        FlarityMerchantGateway gateway = new FlarityMerchantGateway(
            COSTON2_FTSO_V2,
            address(fdc),
            deployerAddress
        );
        console.log("Deployed FlarityMerchantGateway at:", address(gateway));

        // 3. Deploy FAssets
        MockFAsset fXrp = new MockFAsset("Flarity Wrapped XRP", "fXRP", 6);
        MockFAsset fBtc = new MockFAsset("Flarity Wrapped BTC", "fBTC", 8);
        MockFAsset fDoge = new MockFAsset("Flarity Wrapped DOGE", "fDOGE", 8);
        
        console.log("Deployed MockFAsset XRP at:", address(fXrp));
        console.log("Deployed MockFAsset BTC at:", address(fBtc));
        console.log("Deployed MockFAsset DOGE at:", address(fDoge));

        // 4. Transfer FAsset gateway permissions
        fXrp.setGateway(address(gateway));
        fBtc.setGateway(address(gateway));
        fDoge.setGateway(address(gateway));

        // 5. Register FAssets on the gateway
        gateway.setFAsset("XRP", address(fXrp));
        gateway.setFAsset("BTC", address(fBtc));
        gateway.setFAsset("DOGE", address(fDoge));
        console.log("Registered all FAssets on Gateway successfully.");

        vm.stopBroadcast();
        
        console.log("=========================================");
        console.log("DEPLOYMENT COMPLETED SUCCESSFULLY!");
        console.log("=========================================");
    }
}
