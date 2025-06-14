//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @dev Library for handling oracle-related operations.
 * @notice This library is used to check the Chainlink Oracle price feeds
 * If the price is stale, the function will revert and render the DSCEngine unusable- this is by design.
 * We want the DSCEngine to be unusable if the price feed is stale, so that users cannot manipulate the system.
 */
library OracleLib {
    uint256 private constant TIMEOUT = 3 hours; //10800 seconds

    error OracleLib_StalePriceFeed();

    function staleCheckLatestRoundData(
        AggregatorV3Interface priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib_StalePriceFeed();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
