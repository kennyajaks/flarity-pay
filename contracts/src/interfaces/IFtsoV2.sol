// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFtsoV2
 * @notice Interface for querying price feeds from Flare Time Series Oracle v2.
 */
interface IFtsoV2 {
    /**
     * @notice Fetch the current price value, decimals, and timestamp for a specific feed.
     * @param _feedId The 21-byte feed identifier (e.g., FLR/USD, BTC/USD).
     * @return value The current price multiplied by 10^decimals.
     * @return decimals The decimal scaling factor of the value.
     * @return timestamp The block timestamp when the feed was updated.
     */
    function getFeedById(
        bytes21 _feedId
    )
        external
        view
        returns (
            uint256 value,
            int8 decimals,
            uint64 timestamp
        );
}
