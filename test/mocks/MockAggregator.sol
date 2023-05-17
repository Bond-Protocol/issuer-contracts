// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

contract MockAggregator {
    mapping(uint256 => address) public marketsToAuctioneers;

    function getAuctioneer(uint256 id) public view returns (address) {
        return marketsToAuctioneers[id];
    }

    function setMarketAuctioneer(uint256 id, address auctioneer) public {
        marketsToAuctioneers[id] = auctioneer;
    }
}