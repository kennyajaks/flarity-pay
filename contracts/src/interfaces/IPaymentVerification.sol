// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPaymentVerification
 * @notice Interface for verifying external payment transactions via Flare's FDC.
 */
interface IPaymentVerification {
    struct RequestBody {
        string attestationType;      // Type of attestation (e.g., "Payment")
        string sourceId;             // Source chain ID (e.g., "XRP", "BTC", "DOGE")
        bytes32 transactionId;       // Transaction hash on the external chain
        bytes32 paymentReference;    // 32-byte payment reference generated on checkout
        uint256 amount;              // Amount paid in the native base unit of the external chain
        string receivingAddress;     // Destination address on the external chain
    }

    struct Proof {
        bytes32 merkleRoot;          // Merkle root of the attestation batch
        bytes32[] merkleProof;       // Merkle path showing inclusion in the batch
        RequestBody requestBody;     // The payment transaction details
    }

    /**
     * @notice Verifies a payment proof against the FDC consensus root.
     * @param _proof The FDC payment proof struct.
     * @return true if the proof is valid, false otherwise.
     */
    function verifyPayment(Proof calldata _proof) external view returns (bool);
}
