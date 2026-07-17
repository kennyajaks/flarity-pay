// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFtsoV2} from "./interfaces/IFtsoV2.sol";

/**
 * @title MockFtsoV2
 * @notice Mock implementation of FTSOv2 IFtsoV2 interface.
 * @dev Used to simulate oracle price updates in tests.
 */
contract MockFtsoV2 is IFtsoV2 {
    mapping(bytes21 => uint256) public feedPrices;
    mapping(bytes21 => int8) public feedDecimals;

    function setPrice(bytes21 _feedId, uint256 _price, int8 _decimals) external {
        feedPrices[_feedId] = _price;
        feedDecimals[_feedId] = _decimals;
    }

    /**
     * @notice Returns mock price details for a feed.
     */
    function getFeedById(
        bytes21 _feedId
    )
        external
        view
        override
        returns (
            uint256 value,
            int8 decimals,
            uint64 timestamp
        )
    {
        value = feedPrices[_feedId];
        decimals = feedDecimals[_feedId];
        require(value > 0, "Mock feed price not initialized");
        timestamp = uint64(block.timestamp);
    }
}
