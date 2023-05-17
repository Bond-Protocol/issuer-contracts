// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {ERC20} from "src/lib/ERC20.sol";

import {IGnosisEasyAuction} from "src/interfaces/IGnosisEasyAuction.sol";
import {IBondFixedExpiryTeller} from "src/interfaces/IBondFixedExpiryTeller.sol";
import {IBondBatchAuctionFactoryV1} from "src/interfaces/IBondBatchAuctionFactoryV1.sol";

interface IBondBatchAuctionV1 {
    /* ========== STRUCTS ========== */

    struct AuctionData {
        ERC20 quoteToken; // The token that the auction owner is acquiring
        ERC20 payoutToken; // The token that the auction owner is selling (an ERC20BondToken which wraps a token provided by the owner)
        bool created; // Whether the auction has been created. Used to gate "settling" functions which don't exist.
        bool settled; // Whether the auction has been settled. Accurate if settleBatchAuction or withdrawExternallySettledFunds is called after an auction ends, but may contain dirty state when emergency measures are used or if not action is taken. Rely on isLive to know if an auction has ended.
        uint48 auctionEnd; // The timestamp that the batch auction ends on.
        uint256 payoutAmount; // The amount of payout tokens being auctioned off.
    }

    struct BondTokenParams {
        ERC20 underlying; // The underlying ERC20 token to create payout bond tokens from.
        uint48 expiry; // The timestamp that the payout bond tokens will vest at.
    }

    struct BatchAuctionParams {
        BondTokenParams payoutTokenParams; // The parameters for the payout bond token to be created and sold in the auction.
        ERC20 quoteToken; // The token that the auction owner is acquiring.
        uint256 cancelUntil; // The timestamp that users can cancel their orders until.
        uint256 auctionEnd; // The timestamp that the batch auction ends on.
        uint96 auctionAmount; // The amount of payout tokens being auctioned off.
        uint96 minBuyAmount; // The minimum number of quote tokens to be bought for the auctionAmount (sets minimum price as minBuyAmount/auctionAmount)
        uint256 minBuyAmountPerOrder; // The minimum purchase size in quote tokens for an order (prevents running out of gas settling the auction with a bunch of small orders)
        uint256 minFundingThreshold; // Minimum amount of quote tokens that must be raised for the auction to be considered successful.
        uint96 liquidityAmount; // amount of payoutToken to be returned to sender to provide external liquidity with
        address accessManager; // Optional: a contract that can provide whitelist functionality for the auction
        bytes accessManagerData; // Optional: data to be passed to the accessManager contract
    }

    /* ========== IMMUTABLE CLONE ARGS ========== */

    /// @notice The Gnosis Easy Auction contract that the contract will create batch auctions on.
    function gnosisAuction() external pure returns (IGnosisEasyAuction);

    /// @notice The Bond Protocol Fixed Expiry Teller contract that the contract will create bond tokens on.
    function teller() external pure returns (IBondFixedExpiryTeller);

    /// @notice The Bond Protocol Batch Auction Factory contract that created this contract.
    function factory() external pure returns (IBondBatchAuctionFactoryV1);

    /// @notice The address of the owner of the contract.
    function owner() external pure returns (address);

    /* ========== AUCTION MANAGEMENT ========== */

    /// @notice Creates a new batch auction to sell bond tokens for a quote token using Gnosis EasyAuction.
    /// @notice Access controlled - only the owner of this contract can call
    /// @param batchAuctionParams_ Parameters for the batch auction. See struct definition in IBondBatchAuctionV1.sol.
    /// @dev Warning: In case the auction is expected to raise more than
    /// 2^96 units of the quoteToken, don't start the auction, as
    /// it will not be settlable. This corresponds to about 79
    /// billion DAI.
    ///
    /// Prices between quoteToken and payoutToken are expressed by a
    /// fraction whose components are stored as uint96.
    function initiateBatchAuction(BatchAuctionParams memory batchAuctionParams_)
        external
        returns (uint256);

    /// @notice Settle a batch auction that has concluded on the Gnosis Easy Auction contract
    /// @notice Access controlled - only the owner of this contract can call
    /// @param  auctionId_ The ID of the auction to settle
    /// @return The clearing order from the Easy Auction contract
    /// @dev We assume the auction is at the correct stage on the Easy Auction contract, if not, it will revert
    function settleBatchAuction(uint256 auctionId_) external returns (bytes32);

    /// @notice Withdraw quote and/or payout tokens received from a batch auction settled outside of this contract.
    /// @notice Access controlled - only the owner of this contract can call
    /// @dev Gnosis EasyAuction allows anyone to settle a batch auction that has ended.
    ///      This function allows the owner to withdraw the tokens received when the auction is settled externally.
    ///      Additionally, this function "settles" the auction on this contract to avoid dirty state remaining.
    /// @param auctionId_ The ID of the auction to withdraw tokens from.
    function withdrawExternallySettledFunds(uint256 auctionId_) external;

    /// @notice Withdraw tokens or ETH that are stuck in the contract
    /// @notice Access controlled - only the owner of this contract can call
    /// @dev This function is an emergency failsafe to prevent tokens or ETH from being stuck in the contract.
    ///      In general, withdrawExternallySettledFunds should be preferred over this for auctions settled externally.
    /// @param token_ The token to withdraw. If address(0), withdraws ETH.
    function emergencyWithdraw(ERC20 token_) external;

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Returns the number of auctions created by this contract.
    /// @dev This is useful for getting the length of auctions array for pagination with liveAuctions.
    function numAuctions() external view returns (uint256);

    /// @notice Returns the auction data for a given auction ID.
    /// @param auctionId_ The ID of the auction to get data for.
    function auctionData(uint256 auctionId_) external view returns (AuctionData memory);

    /// @notice Returns the amount of payout tokens that is required, inclusive of any fees charged by the Gnosis Auction and Teller contracts.
    /// @dev This method should be used to determine the amount of payout tokens required to approve for the given amount of tokens to auction.
    /// @dev Both contracts currently charge zero fees, but this function is provided in case they do in the future.
    /// @param auctionAmount_ The amount of payout tokens to auction.
    function amountWithFee(uint256 auctionAmount_) external view returns (uint256);

    /// @notice Returns the amount of payout tokens that is required for the desired liquidity amount, inclusive of any fee charged by the Teller contract.
    /// @dev This method should be used to determine the amount of payout tokens required to approve for the given amount of additional tokens to mint for liquidity.
    /// @dev The Teller contract currently charges zero fees, but this function is provided in case it does in the future.
    /// @param liquidityAmount_ The amount of payout tokens to mint for liquidity.
    function amountWithTellerFee(uint256 liquidityAmount_) external view returns (uint256);

    /// @notice Whether or not an auction is live.
    /// @param auctionId_ The auction ID to check status for.
    /// @dev This data can also be retrieved from a specific clone. This functions routes a request for data to the correct clone.
    function isLive(uint256 auctionId_) external view returns (bool);

    /// @notice Returns the auction IDs of live auctions created by this contract in the provided index range.
    /// @dev This function uses a start and end index to allow for pagination of the auctions array in order to iterate through an increasingly large array without hitting the gas limit.
    /// @param startIndex_ The start index of the auctions array to start iterating from (inclusive).
    /// @param endIndex_ The end index of the auctions array to stop iterating at (non-inclusive).
    /// @dev The indexes are over the array of all auctions, are 0-indexed, and the endIndex_ is non-inclusive, i.e. [startIndex, endIndex).
    function liveAuctions(uint256 startIndex_, uint256 endIndex_)
        external
        view
        returns (uint256[] memory);
}
