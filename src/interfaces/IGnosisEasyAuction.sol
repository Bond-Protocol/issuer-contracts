// SPDX-License-Identifier: None
pragma solidity 0.8.15;

import {ERC20} from "src/lib/ERC20.sol";

interface IGnosisEasyAuction {
    /// @notice                         Initiates an auction through Gnosis Auctions
    /// @param tokenToSell              The token being sold
    /// @param biddingToken             The token used to bid on the sale token and set its price
    /// @param lastCancellation         The last timestamp a user can cancel their bid at
    /// @param auctionEnd               The timestamp the auction ends at
    /// @param auctionAmount            The number of sale tokens to sell
    /// @param minBuyAmount             The minimum number of bidding tokens to be bought for the auctionAmount (sets minimum price as minimumTotalProceeds/auctionAmount)
    /// @param minBuyAmountPerOrder     The minimum purchase size in bidding tokens for an order
    /// @param minFundingThreshold      The minimal funding thresholding for finalizing settlement. If not reached, bids will be returned
    /// @param isAtomicClosureAllowed   Can users call settleAuctionAtomically when end date has been reached
    /// @param accessManager            The contract to manage an allowlist
    /// @param accessManagerData        The data for managing an allowlist
    function initiateAuction(
        ERC20 tokenToSell,
        ERC20 biddingToken,
        uint256 lastCancellation,
        uint256 auctionEnd,
        uint96 auctionAmount,
        uint96 minBuyAmount,
        uint256 minBuyAmountPerOrder,
        uint256 minFundingThreshold,
        bool isAtomicClosureAllowed,
        address accessManager,
        bytes calldata accessManagerData
    ) external returns (uint256);

    /// @notice                         Settles the auction and determines the clearing orders
    /// @param auctionId                The auction to settle
    function settleAuction(uint256 auctionId) external returns (bytes32);

    function placeSellOrders(
        uint256 auctionId,
        uint96[] memory _minBuyAmounts,
        uint96[] memory _sellAmounts,
        bytes32[] memory _prevSellOrders,
        bytes calldata allowListCallData
    ) external returns (uint64 userId);

    function claimFromParticipantOrder(uint256 auctionId, bytes32[] memory orders)
        external
        returns (uint256 sumAuctioningTokenAmount, uint256 sumBiddingTokenAmount);

    function setFeeParameters(uint256 newFeeNumerator, address newfeeReceiverAddress) external;

    struct AuctionData {
        ERC20 auctioningToken;
        ERC20 biddingToken;
        uint256 orderCancellationEndDate;
        uint256 auctionEndDate;
        bytes32 initialAuctionOrder;
        uint256 minimumBiddingAmountPerOrder;
        uint256 interimSumBidAmount;
        bytes32 interimOrder;
        bytes32 clearingPriceOrder;
        uint96 volumeClearingPriceOrder;
        bool minFundingThresholdNotReached;
        bool isAtomicClosureAllowed;
        uint256 feeNumerator;
        uint256 minFundingThreshold;
    }

    function auctionData(uint256 auctionId) external view returns (AuctionData memory);

    function auctionAccessManager(uint256 auctionId) external view returns (address);

    function auctionAccessData(uint256 auctionId) external view returns (bytes memory);

    function auctionCounter() external view returns (uint256);

    function feeNumerator() external view returns (uint256);

    function FEE_DENOMINATOR() external view returns (uint256);
}
