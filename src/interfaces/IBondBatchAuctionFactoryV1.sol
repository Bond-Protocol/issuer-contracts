// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {ERC20} from "src/lib/ERC20.sol";
import {IBondBatchAuctionV1} from "src/interfaces/IBondBatchAuctionV1.sol";

interface IBondBatchAuctionFactoryV1 {
    /* ========== CLONE DEPLOYMENT ========== */

    /// @notice Deploys a new BondBatchAuctionV1 clone that can be used to create Batch Auctions to sell Fixed Expiry Bond Tokens.
    /// @param owner_ The owner of the BondBatchAuctionV1 clone. This is the only address that will be able to create auctions and claim proceeds.
    function deployClone(address owner_) external returns (IBondBatchAuctionV1);

    /* ========== AUCTION REGISTRATION ========== */

    /// @notice Registers a new auction with the factory.
    /// @notice Access controlled - only callable by BondBatchAuctionV1 clones created by this contract.
    /// @param auctionId_ The auction ID of the auction to register.
    /// @param quoteToken_ The quote token (auction creator is acquiring) for the auction.
    function registerAuction(uint256 auctionId_, ERC20 quoteToken_) external;

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Returns the number of auctions created by clones of the factory.
    /// @dev This is useful for getting the length of auctions array for pagination with liveAuctions, auctionsBy, and liveAuctionsBy.
    function numAuctions() external view returns (uint256);

    /// @notice Returns the number of auctions created by clones of the factory for a given quote token.
    /// @dev This is useful for getting the length of auctions array for a quote tokens for pagination with auctionsFor and liveAuctionsFor.
    /// @param quoteToken_ The quote token to get the number of auctions for.
    function numAuctionsFor(ERC20 quoteToken_) external view returns (uint256);

    /// @notice Returns the stored auction data for a given auction ID.
    /// @param auctionId_ The auction ID to get the data for.
    /// @dev This data can also be retrieved from a specific clone. This functions routes a request for data to the correct clone.
    function auctionData(uint256 auctionId_)
        external
        view
        returns (IBondBatchAuctionV1.AuctionData memory);

    /// @notice Whether or not an auction is live.
    /// @param auctionId_ The auction ID to check status for.
    /// @dev This data can also be retrieved from a specific clone. This functions routes a request for data to the correct clone.
    function isLive(uint256 auctionId_) external view returns (bool);

    /// @notice Returns the auction IDs of all live auctions in the provided index range.
    /// @dev This function uses a start and end index to allow for pagination of the auctions array in order to iterate through an increasingly large array without hitting the gas limit.
    /// @param startIndex_ The start index of the auctions array to start iterating from (inclusive).
    /// @param endIndex_ The end index of the auctions array to stop iterating at (non-inclusive).
    /// @dev The indexes are over the array of all auctions, are 0-indexed, and the endIndex_ is non-inclusive, i.e. [startIndex, endIndex).
    function liveAuctions(uint256 startIndex_, uint256 endIndex_)
        external
        view
        returns (uint256[] memory);

    /// @notice Returns the auction IDs of all live auctions by the provided owner in the provided index range.
    /// @dev This function uses a start and end index to allow for pagination of the auctions array in order to iterate through an increasingly large array without hitting the gas limit.
    /// @param startIndex_ The start index of the auctions array to start iterating from (inclusive).
    /// @param endIndex_ The end index of the auctions array to stop iterating at (non-inclusive).
    /// @dev The indexes are over the array of all auctions, are 0-indexed, and the endIndex_ is non-inclusive, i.e. [startIndex, endIndex).
    function liveAuctionsBy(
        address owner_,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view returns (uint256[] memory);

    /// @notice Returns the auction IDs of all auctions by the provided owner in the provided index range.
    /// @dev This function uses a start and end index to allow for pagination of the auctions array in order to iterate through an increasingly large array without hitting the gas limit.
    /// @param startIndex_ The start index of the auctions array to start iterating from (inclusive).
    /// @param endIndex_ The end index of the auctions array to stop iterating at (non-inclusive).
    /// @dev The indexes are over the array of all auctions, are 0-indexed, and the endIndex_ is non-inclusive, i.e. [startIndex, endIndex).
    function auctionsBy(
        address owner_,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view returns (uint256[] memory);

    /// @notice Returns the auction IDs of all live auctions for the provided quote token in the provided index range.
    /// @dev This function uses a start and end index to allow for pagination of the quote token auctions array in order to iterate through an increasingly large array without hitting the gas limit.
    /// @param quoteToken_ The quote token (address) to get the live auctions for.
    /// @param startIndex_ The start index of the quote token auctions array to start iterating from (inclusive).
    /// @param endIndex_ The end index of the quote token auctions array to stop iterating at (non-inclusive).
    /// @dev The indexes are over the array of auctions for the specific quote token, are 0-indexed, and the endIndex_ is non-inclusive, i.e. [startIndex, endIndex).
    function liveAuctionsFor(
        ERC20 quoteToken_,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view returns (uint256[] memory);

    /// @notice Returns the auction IDs of all auctions for the provided quote token in the provided index range.
    /// @dev This function uses a start and end index to allow for pagination of the quote token auctions array in order to iterate through an increasingly large array without hitting the gas limit.
    /// @param quoteToken_ The quote token (address) to get the live auctions for.
    /// @param startIndex_ The start index of the quote token auctions array to start iterating from (inclusive).
    /// @param endIndex_ The end index of the quote token auctions array to stop iterating at (non-inclusive).
    /// @dev The indexes are over the array of auctions for the specific quote token, are 0-indexed, and the endIndex_ is non-inclusive, i.e. [startIndex, endIndex).
    function auctionsFor(
        ERC20 quoteToken_,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view returns (uint256[] memory);
}
