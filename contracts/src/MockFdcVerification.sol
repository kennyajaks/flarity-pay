// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPaymentVerification} from "./interfaces/IPaymentVerification.sol";

/**
 * @title MockFdcVerification
 * @notice Mock implementation of FDC IPaymentVerification interface.
 * @dev Used for local testing and simulating FDC verification responses.
 */
contract MockFdcVerification is IPaymentVerification {
    bool public mockVerificationResult = true;

    function setMockResult(bool _result) external {
        mockVerificationResult = _result;
    }

    /**
     * @notice Simulates proof verification.
     * @return The mock result set by setMockResult (defaults to true).
     */
    function verifyPayment(Proof calldata) external view override returns (bool) {
        return mockVerificationResult;
    }
}
