// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

library PriceFeed {
    function ethToUsd(
        uint256 ethAmount,
        AggregatorV3Interface dataFeed
    ) external view returns (uint256) {
        int ethPriceInUsd = getChainlinkDataFeedLatestAnswer(dataFeed) *
            10 ** 10;

        uint256 ethAmountInUsd = (uint256(ethPriceInUsd) * ethAmount) /
            10 ** 18;

        return ethAmountInUsd;
    }

    /**
     * Returns the latest answer.
     */
    function getChainlinkDataFeedLatestAnswer(
        AggregatorV3Interface dataFeed
    ) internal view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return answer;
    }
}
