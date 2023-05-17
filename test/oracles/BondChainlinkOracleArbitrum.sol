// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "lib/forge-std/src/Test.sol";
import {console2} from "lib/forge-std/src/console2.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {MockPriceFeed} from "../mocks/MockPriceFeed.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";

import {BondChainlinkOracleArbitrum, AggregatorV2V3Interface} from "src/oracles/BondChainlinkOracleArbitrum.sol";

import {FullMath} from "src/lib/FullMath.sol";

contract BondChainlinkOracleArbitrumTest is Test {
    using FullMath for uint256;

    address public user;
    address public auctioneer;
    MockAggregator public aggregator;

    MockERC20 public tokenOne;
    MockERC20 public tokenTwo;
    MockERC20 public tokenThree;
    MockERC20 public tokenFour;

    MockPriceFeed public feedOne;
    MockPriceFeed public feedTwo;
    MockPriceFeed public feedThree;
    MockPriceFeed public sequencerFeed;
    BondChainlinkOracleArbitrum public oracle;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        user = address(uint160(uint256(keccak256(abi.encodePacked("user")))));
        vm.label(user, "user");

        auctioneer = address(uint160(uint256(keccak256(abi.encodePacked("auctioneer")))));
        vm.label(auctioneer, "auctioneer");

        vm.label(address(this), "owner");

        // Deploy mock tokens
        tokenOne = new MockERC20("Token One", "T1", 18);
        tokenTwo = new MockERC20("Token Two", "T2", 18);
        tokenThree = new MockERC20("Token Three", "T3", 18);
        tokenFour = new MockERC20("Token Four", "T4", 18);

        // Deploy mock price feeds and set params

        // T1 / T2
        feedOne = new MockPriceFeed();
        feedOne.setLatestAnswer(int256(8e18));
        feedOne.setTimestamp(block.timestamp);
        feedOne.setRoundId(1);
        feedOne.setAnsweredInRound(1);
        feedOne.setDecimals(18);

        // T2 / T3
        feedTwo = new MockPriceFeed();
        feedTwo.setLatestAnswer(int256(5e17));
        feedTwo.setTimestamp(block.timestamp);
        feedTwo.setRoundId(1);
        feedTwo.setAnsweredInRound(1);
        feedTwo.setDecimals(18);

        // T4 / T2
        feedThree = new MockPriceFeed();
        feedThree.setLatestAnswer(int256(4e18));
        feedThree.setTimestamp(block.timestamp);
        feedThree.setRoundId(1);
        feedThree.setAnsweredInRound(1);
        feedThree.setDecimals(18);

        // Cases:
        // Single feed: feedOne = T1 / T2 => 8e18
        // Double Feed Mul: feedOne MUL feedTwo = T1 / T3 => 4e18
        // Double Feed Div: feedOne DIV feedThree = T1 / T4 => 2e18

        // Deploy mock aggregator
        aggregator = new MockAggregator();

        // Deploy mock Arbitrum sequencer feed
        sequencerFeed = new MockPriceFeed();
        sequencerFeed.setLatestAnswer(int256(0)); // 0 means it is up
        sequencerFeed.setStartedAt(block.timestamp - 1 days); // just needs to further in the past the the grace period (1 hour)

        // Deploy oracle
        address[] memory auctioneers = new address[](1);
        auctioneers[0] = auctioneer;
        oracle = new BondChainlinkOracleArbitrum(
            address(aggregator),
            auctioneers,
            address(sequencerFeed)
        );

        // Set pairs on oracle

        // Case 1: Single Feed = T1 / T2
        bytes memory singleFeed = abi.encode(
            address(feedOne),
            uint48(1 days),
            address(0),
            uint48(0),
            uint8(18),
            false
        );

        oracle.setPair(tokenOne, tokenTwo, true, singleFeed);

        // Case 2: Single Feed Inverse = T2 / T1
        bytes memory singleFeedInverse = abi.encode(
            address(feedOne),
            uint48(1 days),
            address(0),
            uint48(0),
            uint8(18),
            true
        );

        oracle.setPair(tokenTwo, tokenOne, true, singleFeedInverse);

        // Case 3: Double Feed Mul = T1 / T3
        bytes memory doubleFeedMul = abi.encode(
            address(feedOne),
            uint48(1 days),
            address(feedTwo),
            uint48(1 days),
            uint8(18),
            false
        );

        oracle.setPair(tokenOne, tokenThree, true, doubleFeedMul);

        // Case 4: Double Feed Div = T1 / T4
        bytes memory doubleFeedDiv = abi.encode(
            address(feedOne),
            uint48(1 days),
            address(feedThree),
            uint48(1 days),
            uint8(18),
            true
        );

        oracle.setPair(tokenOne, tokenFour, true, doubleFeedDiv);
    }

    /* ==================== BASE ORACLE TESTS ==================== */
    //  [X] Register Market
    //      [X] Can register market with valid pair
    //      [X] Cannot register market with invalid pair
    //      [X] Only supported auctioneer can register market
    //  [X] Current Price
    //      [X] Can get current price for supported token pair
    //      [X] Cannot get current price for unsupported token pair
    //      [X] Can get current price for registered market with id
    //      [X] Cannot get current price for market that hasn't been registered
    //  [X] Decimals
    //      [X] Can get decimals for supported token pair
    //      [X] Cannot get decimals for unsupported token pair
    //      [X] Can get decimals for registered market with id
    //      [X] Cannot get decimals for market that hasn't been registered
    //  [X] Set Auctioneer
    //      [X] Owner can set supported status of an auctioneer
    //      [X] Non-owner cannot set supported status of an auctioneer
    //      [X] Cannot call set auctioneer with no status change
    //  [X] Set Pair
    //      [X] Owner can set oracle data and/or supported status for a pair
    //      [X] Non-owner cannot set oracle data and/or supported status for a pair

    /* ==================== SAMPLE CHAINLINK ORACLE TESTS ==================== */
    //  [X] Set Pair
    //      [X] Price feed parameters are set correctly - one feed
    //      [X] Price feed parameters are set correctly - one feed inverse
    //      [X] Price feed parameters are set correctly - double feed mul
    //      [X] Price feed parameters are set correctly - double feed div
    //      [X] Price reverts if support for pair is removed
    //  [X] One Feed Price
    //      [X] Price for single feed is returned correctly when feed is valid
    //      [X] Reverts when feed is invalid
    //  [X] One Feed Price Inverse
    //      [X] Price for single feed inverse is returned correctly when feed is valid
    //      [X] Reverts when feed is invalid
    //  [X] Double Feed Mul Price
    //      [X] Price for double feed mul is returned correctly when feeds are valid
    //      [X] Reverts when either feed is invalid
    //  [X] Double Feed Div Price
    //      [X] Price for double feed div is returned correctly when feeds are valid
    //      [X] Reverts when either feed is invalid
    //  [X] Decimals
    //      [X] Decimals are returned correctly from params
    //  [X] Arbitrum Sequencer Feed
    //      [X] currentPrice reverts when sequencer feed is down

    function test_registerMarket() public {
        // Set auctioneer for market 0 on aggregator
        aggregator.setMarketAuctioneer(0, auctioneer);

        // Try to register market with non-auctioneer, should fail
        bytes memory err = abi.encodeWithSignature("BondOracle_NotAuctioneer(address)", user);
        vm.expectRevert(err);
        vm.prank(user);
        oracle.registerMarket(0, tokenOne, tokenTwo);

        // Try to register market that doesn't exist on aggregator, should fail
        err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(auctioneer);
        oracle.registerMarket(1, tokenOne, tokenTwo);

        // Try to register market with invalid pair, should fail
        err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            tokenFour,
            tokenOne
        );
        vm.expectRevert(err);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenFour, tokenOne);

        // Register market with auctioneer and valid pair, should succeed
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);
    }

    function test_currentPrice() public {
        // Try to get current price for market that hasn't been registered, should fail
        bytes memory err = abi.encodeWithSignature("BondOracle_MarketNotRegistered(uint256)", 0);
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Register market
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);

        // Get current price for registered market, should succeed
        uint256 price = oracle.currentPrice(0);
        assertEq(price, 8e18);
    }

    function testFuzz_currentPrice_oneFeed(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            decimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenTwo, true, oracleData);

        // Register market for auctioneer
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(0);

        // Calculate expected price and compare
        uint256 expectedPrice = (uint256(feedOne.latestAnswer()) * 10 ** decimals_) /
            10 ** numerDecimals_;

        assertEq(price, expectedPrice);

        // Set roundId different than answeredInRound, should fail
        feedOne.setRoundId(2);
        bytes memory err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        feedOne.setRoundId(1);

        // Set price to zero, should fail
        int256 answer = feedOne.latestAnswer();
        feedOne.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set price negative, should fail
        feedOne.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        feedOne.setLatestAnswer(answer);

        // Set block timestamp past the update threshold, should fail
        vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
        vm.expectRevert(err);
        oracle.currentPrice(0);
    }

    function testFuzz_currentPrice_oneFeedInverse(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);

        // Register market for auctioneer
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenTwo, tokenOne);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(0);

        // Calculate expected price and compare
        uint256 expectedPrice = (10 ** decimals_ * 10 ** numerDecimals_) /
            uint256(feedOne.latestAnswer());

        assertEq(price, expectedPrice);

        // Set roundId different than answeredInRound, should fail
        feedOne.setRoundId(2);
        bytes memory err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        feedOne.setRoundId(1);

        // Set price to zero, should fail
        int256 answer = feedOne.latestAnswer();
        feedOne.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set price negative, should fail
        feedOne.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        feedOne.setLatestAnswer(answer);

        // Set block timestamp past the update threshold, should fail
        vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
        vm.expectRevert(err);
        oracle.currentPrice(0);
    }

    function testFuzz_currentPrice_doubleFeedMul(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ > numerDecimals_ + denomDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedTwo.setDecimals(denomDecimals_);
        feedTwo.setLatestAnswer(
            (feedTwo.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenThree, true, oracleData);

        // Register market for auctioneer
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenThree);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(0);

        // Calculate expected price and compare
        uint256 expectedPrice = uint256(feedOne.latestAnswer()).mulDiv(
            uint256(feedTwo.latestAnswer()),
            10 ** (numerDecimals_ + denomDecimals_ - decimals_)
        );

        assertEq(price, expectedPrice);

        // Set roundId different than answeredInRound, should fail
        feedOne.setRoundId(2);
        bytes memory err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        feedOne.setRoundId(1);

        // Set numerator feed price to zero, should fail
        int256 numerAnswer = feedOne.latestAnswer();
        feedOne.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set numerator feed price negative, should fail
        feedOne.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set denominator feed price to zero, should fail on numer first
        int256 denomAnswer = feedTwo.latestAnswer();
        feedTwo.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set denominator feed price negative, should fail on numer first
        feedTwo.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set numerator feed price back to original
        feedOne.setLatestAnswer(numerAnswer);

        // Try again, should fail on denom feed with price zero
        err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedTwo));
        feedTwo.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set denominator feed price negative, should fail on denom feed
        feedTwo.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set denominator feed price back to original
        feedTwo.setLatestAnswer(denomAnswer);

        // Set block timestamp past the lower update threshold, should fail on that one
        if (numerUpdateThreshold_ <= denomUpdateThreshold_) {
            vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        } else {
            vm.warp(block.timestamp + denomUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedTwo));
        }
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set block timestamp past the higher update threshold, should fail on the numerator feed
        if (numerUpdateThreshold_ > denomUpdateThreshold_) {
            vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        } else {
            vm.warp(block.timestamp + denomUpdateThreshold_ + 1);
        }
        vm.expectRevert(err);
        oracle.currentPrice(0);
    }

    function testFuzz_currentPrice_doubleFeedDiv(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ + denomDecimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedTwo.setDecimals(denomDecimals_);
        feedTwo.setLatestAnswer(
            (feedTwo.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenThree, true, oracleData);

        // Register market for auctioneer
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenThree);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(0);

        // Calculate expected price and compare
        uint256 expectedPrice = uint256(feedOne.latestAnswer()).mulDiv(
            10 ** (decimals_ + denomDecimals_ - numerDecimals_),
            uint256(feedTwo.latestAnswer())
        );

        assertEq(price, expectedPrice);

        // Set roundId different than answeredInRound, should fail
        feedOne.setRoundId(2);
        bytes memory err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        feedOne.setRoundId(1);

        // Set numerator feed price to zero, should fail
        int256 numerAnswer = feedOne.latestAnswer();
        feedOne.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set numerator feed price negative, should fail
        feedOne.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set denominator feed price to zero, should fail on numer first
        int256 denomAnswer = feedTwo.latestAnswer();
        feedTwo.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set denominator feed price negative, should fail on numer first
        feedTwo.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set numerator feed price back to original
        feedOne.setLatestAnswer(numerAnswer);

        // Try again, should fail on denom feed with price zero
        err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedTwo));
        feedTwo.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set denominator feed price negative, should fail on denom feed
        feedTwo.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set denominator feed price back to original
        feedTwo.setLatestAnswer(denomAnswer);

        // Set block timestamp past the lower update threshold, should fail on that one
        if (numerUpdateThreshold_ <= denomUpdateThreshold_) {
            vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        } else {
            vm.warp(block.timestamp + denomUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedTwo));
        }
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Set block timestamp past the higher update threshold, should fail on the numerator feed
        if (numerUpdateThreshold_ > denomUpdateThreshold_) {
            vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        } else {
            vm.warp(block.timestamp + denomUpdateThreshold_ + 1);
        }
        vm.expectRevert(err);
        oracle.currentPrice(0);
    }

    function test_currentPricePair() public {
        // Try to get current price for a pair that is not set, should fail
        bytes memory err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            tokenFour,
            tokenOne
        );
        vm.expectRevert(err);
        oracle.currentPrice(tokenFour, tokenOne);

        // Set pair on the oracle
        bytes memory oracleData = abi.encode(
            address(feedThree),
            1 days,
            address(feedOne),
            1 days,
            18,
            true
        );

        oracle.setPair(tokenFour, tokenOne, true, oracleData);

        // Get current price for registered market, should succeed
        uint256 price = oracle.currentPrice(tokenFour, tokenOne);
        assertEq(price, 5e17);

        // Try to get current price for a pair with first token zero address, should fail
        err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            address(0),
            tokenOne
        );
        vm.expectRevert(err);
        oracle.currentPrice(MockERC20(address(0)), tokenOne);

        // Try to get current price for a pair with second token zero address, should fail
        err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            tokenFour,
            address(0)
        );
        vm.expectRevert(err);
        oracle.currentPrice(tokenFour, MockERC20(address(0)));

        // Try to get current price for a pair with both tokens zero address, should fail
        err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            address(0),
            address(0)
        );
        vm.expectRevert(err);
        oracle.currentPrice(MockERC20(address(0)), MockERC20(address(0)));
    }

    function testFuzz_currentPricePair_oneFeed(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            decimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenTwo, true, oracleData);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(tokenOne, tokenTwo);

        // Calculate expected price and compare
        uint256 expectedPrice = (uint256(feedOne.latestAnswer()) * 10 ** decimals_) /
            10 ** numerDecimals_;

        assertEq(price, expectedPrice);

        // Set roundId different than answeredInRound, should fail
        feedOne.setRoundId(2);
        bytes memory err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenTwo);

        feedOne.setRoundId(1);

        // Set price to zero, should fail
        int256 answer = feedOne.latestAnswer();
        feedOne.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenTwo);

        // Set price negative, should fail
        feedOne.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenTwo);

        feedOne.setLatestAnswer(answer);

        // Set block timestamp past the update threshold, should fail
        vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenTwo);
    }

    function testFuzz_currentPricePair_oneFeedInverse(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(tokenTwo, tokenOne);

        // Calculate expected price and compare
        uint256 expectedPrice = (10 ** decimals_ * 10 ** numerDecimals_) /
            uint256(feedOne.latestAnswer());

        assertEq(price, expectedPrice);

        // Set roundId different than answeredInRound, should fail
        feedOne.setRoundId(2);
        bytes memory err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        vm.expectRevert(err);
        oracle.currentPrice(tokenTwo, tokenOne);

        feedOne.setRoundId(1);

        // Set price to zero, should fail
        int256 answer = feedOne.latestAnswer();
        feedOne.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(tokenTwo, tokenOne);

        // Set price negative, should fail
        feedOne.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(tokenTwo, tokenOne);

        feedOne.setLatestAnswer(answer);

        // Set block timestamp past the update threshold, should fail
        vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
        vm.expectRevert(err);
        oracle.currentPrice(tokenTwo, tokenOne);
    }

    function testFuzz_currentPricePair_doubleFeedMul(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ > numerDecimals_ + denomDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedTwo.setDecimals(denomDecimals_);
        feedTwo.setLatestAnswer(
            (feedTwo.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenThree, true, oracleData);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(tokenOne, tokenThree);

        // Calculate expected price and compare
        uint256 expectedPrice = uint256(feedOne.latestAnswer()).mulDiv(
            uint256(feedTwo.latestAnswer()),
            10 ** (numerDecimals_ + denomDecimals_ - decimals_)
        );

        assertEq(price, expectedPrice);

        // Set roundId different than answeredInRound, should fail
        feedOne.setRoundId(2);
        bytes memory err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        feedOne.setRoundId(1);

        // Set numerator feed price to zero, should fail
        int256 numerAnswer = feedOne.latestAnswer();
        feedOne.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set numerator feed price negative, should fail
        feedOne.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set denominator feed price to zero, should fail on numer first
        int256 denomAnswer = feedTwo.latestAnswer();
        feedTwo.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set denominator feed price negative, should fail on numer first
        feedTwo.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set numerator feed price back to original
        feedOne.setLatestAnswer(numerAnswer);

        // Try again, should fail on denom feed with price zero
        err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedTwo));
        feedTwo.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set denominator feed price negative, should fail on denom feed
        feedTwo.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set denominator feed price back to original
        feedTwo.setLatestAnswer(denomAnswer);

        // Set block timestamp past the lower update threshold, should fail on that one
        if (numerUpdateThreshold_ <= denomUpdateThreshold_) {
            vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        } else {
            vm.warp(block.timestamp + denomUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedTwo));
        }
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set block timestamp past the higher update threshold, should fail on the numerator feed
        if (numerUpdateThreshold_ > denomUpdateThreshold_) {
            vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        } else {
            vm.warp(block.timestamp + denomUpdateThreshold_ + 1);
        }
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);
    }

    function testFuzz_currentPricePair_doubleFeedDiv(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ + denomDecimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedTwo.setDecimals(denomDecimals_);
        feedTwo.setLatestAnswer(
            (feedTwo.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenThree, true, oracleData);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(tokenOne, tokenThree);

        // Calculate expected price and compare
        uint256 expectedPrice = uint256(feedOne.latestAnswer()).mulDiv(
            10 ** (decimals_ + denomDecimals_ - numerDecimals_),
            uint256(feedTwo.latestAnswer())
        );

        assertEq(price, expectedPrice);

        // Set roundId different than answeredInRound, should fail
        feedOne.setRoundId(2);
        bytes memory err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        feedOne.setRoundId(1);

        // Set numerator feed price to zero, should fail
        int256 numerAnswer = feedOne.latestAnswer();
        feedOne.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set numerator feed price negative, should fail
        feedOne.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set denominator feed price to zero, should fail on numer first
        int256 denomAnswer = feedTwo.latestAnswer();
        feedTwo.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set denominator feed price negative, should fail on numer first
        feedTwo.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set numerator feed price back to original
        feedOne.setLatestAnswer(numerAnswer);

        // Try again, should fail on denom feed with price zero
        err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedTwo));
        feedTwo.setLatestAnswer(int256(0));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set denominator feed price negative, should fail on denom feed
        feedTwo.setLatestAnswer(int256(-1));
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set denominator feed price back to original
        feedTwo.setLatestAnswer(denomAnswer);

        // Set block timestamp past the lower update threshold, should fail on that one
        if (numerUpdateThreshold_ <= denomUpdateThreshold_) {
            vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        } else {
            vm.warp(block.timestamp + denomUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedTwo));
        }
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);

        // Set block timestamp past the higher update threshold, should fail on the numerator feed
        if (numerUpdateThreshold_ > denomUpdateThreshold_) {
            vm.warp(block.timestamp + numerUpdateThreshold_ + 1);
            err = abi.encodeWithSignature("BondOracle_BadFeed(address)", address(feedOne));
        } else {
            vm.warp(block.timestamp + denomUpdateThreshold_ + 1);
        }
        vm.expectRevert(err);
        oracle.currentPrice(tokenOne, tokenThree);
    }

    function test_decimals() public {
        // Try to get current price for market that hasn't been registered, should fail
        bytes memory err = abi.encodeWithSignature("BondOracle_MarketNotRegistered(uint256)", 0);
        vm.expectRevert(err);
        oracle.decimals(0);

        // Register market
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);

        // Get current price for registered market, should succeed
        uint8 decimals = oracle.decimals(0);
        assertEq(decimals, 18);
    }

    function testFuzz_decimals_oneFeed(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            decimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenTwo, true, oracleData);

        // Register market for auctioneer
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(0);

        // Compare actual and expected decimals
        assertEq(decimals, decimals_);
    }

    function testFuzz_decimals_oneFeedInverse(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);

        // Register market for auctioneer
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenTwo, tokenOne);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(0);

        // Compare actual and expected decimals
        assertEq(decimals, decimals_);
    }

    function testFuzz_decimals_doubleFeedMul(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ > numerDecimals_ + denomDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedTwo.setDecimals(denomDecimals_);
        feedTwo.setLatestAnswer(
            (feedTwo.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenThree, true, oracleData);

        // Register market for auctioneer
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenThree);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(0);

        // Compare actual and expected decimals
        assertEq(decimals, decimals_);
    }

    function testFuzz_decimals_doubleFeedDiv(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ + denomDecimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedTwo.setDecimals(denomDecimals_);
        feedTwo.setLatestAnswer(
            (feedTwo.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenThree, true, oracleData);

        // Register market for auctioneer
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenThree);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(0);

        // Compare actual and expected decimals
        assertEq(decimals, decimals_);
    }

    function test_decimalsPair() public {
        // Try to get current price for market that hasn't been registered, should fail
        bytes memory err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            tokenFour,
            tokenOne
        );
        vm.expectRevert(err);
        oracle.decimals(tokenFour, tokenOne);

        // Set pair on the oracle, should succeed
        bytes memory oracleData = abi.encode(
            address(feedThree),
            uint48(1 days),
            address(feedOne),
            uint48(1 days),
            uint8(18),
            true
        );
        oracle.setPair(tokenFour, tokenOne, true, oracleData);

        // Get current price for pair, should succeed
        uint8 decimals = oracle.decimals(tokenFour, tokenOne);
        assertEq(decimals, 18);

        // Try to get decimals for a pair with first token zero address, should fail
        err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            address(0),
            tokenOne
        );
        vm.expectRevert(err);
        oracle.decimals(MockERC20(address(0)), tokenOne);

        // Try to get decimals for a pair with second token zero address, should fail
        err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            tokenFour,
            address(0)
        );
        vm.expectRevert(err);
        oracle.decimals(tokenFour, MockERC20(address(0)));

        // Try to get decimals for a pair with both tokens zero address, should fail
        err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            address(0),
            address(0)
        );
        vm.expectRevert(err);
        oracle.decimals(MockERC20(address(0)), MockERC20(address(0)));
    }

    function testFuzz_decimalsPair_oneFeed(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            decimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenTwo, true, oracleData);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(tokenOne, tokenTwo);

        // Compare actual and expected decimals
        assertEq(decimals, decimals_);
    }

    function testFuzz_decimalsPair_oneFeedInverse(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(tokenTwo, tokenOne);

        // Compare actual and expected decimals
        assertEq(decimals, decimals_);
    }

    function testFuzz_decimalsPair_doubleFeedMul(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ > numerDecimals_ + denomDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedTwo.setDecimals(denomDecimals_);
        feedTwo.setLatestAnswer(
            (feedTwo.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenThree, true, oracleData);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(tokenOne, tokenThree);

        // Compare actual and expected decimals
        assertEq(decimals, decimals_);
    }

    function testFuzz_decimalsPair_doubleFeedDiv(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ + denomDecimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedTwo.setDecimals(denomDecimals_);
        feedTwo.setLatestAnswer(
            (feedTwo.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenThree, true, oracleData);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(tokenOne, tokenThree);

        // Compare actual and expected decimals
        assertEq(decimals, decimals_);
    }

    function testFuzz_setAuctioneer(address addr, address auct) public {
        vm.assume(addr != address(this));
        vm.assume(auct != auctioneer);

        // Try to add new auctioneer as non-owner, should fail
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(addr);
        oracle.setAuctioneer(auct, true);

        // Add new auctioneer as owner, should succeed
        oracle.setAuctioneer(auct, true);

        // Try to remove auctioneer as non-owner, should fail
        vm.expectRevert(err);
        vm.prank(addr);
        oracle.setAuctioneer(auct, false);

        // Remove auctioneer as owner, should succeed
        oracle.setAuctioneer(auct, false);

        // Try to remove auctioneer that is already removed, should fail
        err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        oracle.setAuctioneer(auct, false);

        // Try to add auctioneer that is already added, should fail
        vm.expectRevert(err);
        oracle.setAuctioneer(auctioneer, true);
    }

    function testFuzz_setPair_onlyOwner(address addr) public {
        vm.assume(addr != address(this));

        // Setup oracle data for pair
        bytes memory oracleData = abi.encode(
            address(feedOne),
            uint48(1 days),
            address(0),
            uint48(0),
            uint8(18),
            false
        );

        // Confirm pair is not set yet
        (
            AggregatorV2V3Interface numerFeed,
            uint48 numerUT,
            AggregatorV2V3Interface denomFeed,
            uint48 denomUT,
            uint8 decimals,
            bool div
        ) = oracle.priceFeedParams(tokenFour, tokenOne);
        bytes memory params = abi.encode(
            address(numerFeed),
            numerUT,
            address(denomFeed),
            denomUT,
            decimals,
            div
        );
        assertEq(params, abi.encode(0, 0, 0, 0, 0, 0));

        // Try to set pair with non-owner, should fail
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(addr);
        oracle.setPair(tokenFour, tokenOne, true, oracleData);

        // Set pair with owner (this contract), should succeed
        // Pair is backwards, but that's ok for this test
        oracle.setPair(tokenFour, tokenOne, true, oracleData);

        // Confirm pair is set correctly
        (numerFeed, numerUT, denomFeed, denomUT, decimals, div) = oracle.priceFeedParams(
            tokenFour,
            tokenOne
        );
        params = abi.encode(
            address(numerFeed),
            numerUT,
            address(denomFeed),
            denomUT,
            decimals,
            div
        );
        assertEq(params, oracleData);

        // Try to remove pair with non-owner, should fail
        vm.expectRevert(err);
        vm.prank(addr);
        oracle.setPair(tokenFour, tokenOne, false, oracleData);

        // Remove pair with owner (this contract), should succeed
        // Pair is backwards, but that's ok for this test
        oracle.setPair(tokenFour, tokenOne, false, oracleData);

        // Confirm pair is removed
        (numerFeed, numerUT, denomFeed, denomUT, decimals, div) = oracle.priceFeedParams(
            tokenFour,
            tokenOne
        );
        params = abi.encode(
            address(numerFeed),
            numerUT,
            address(denomFeed),
            denomUT,
            decimals,
            div
        );
        assertEq(params, abi.encode(0, 0, 0, 0, 0, 0));
    }

    function testFuzz_setPair_oneFeed_add_valid(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            decimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenTwo, true, oracleData);

        // Confirm price feed params are set for the pair
        (
            AggregatorV2V3Interface numerFeed,
            uint48 numerUT,
            AggregatorV2V3Interface denomFeed,
            uint48 denomUT,
            uint8 decimals,
            bool div
        ) = oracle.priceFeedParams(tokenOne, tokenTwo);
        bytes memory params = abi.encode(
            address(numerFeed),
            numerUT,
            address(denomFeed),
            denomUT,
            decimals,
            div
        );
        assertEq(params, oracleData);
    }

    function testFuzzRevert_setPair_oneFeed_add_invalid(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out valid params
        if (
            decimals_ >= 6 &&
            decimals_ <= 18 &&
            numerDecimals_ >= 6 &&
            numerDecimals_ <= 18 &&
            decimals_ >= numerDecimals_ &&
            numerUpdateThreshold_ >= 1 hours &&
            numerUpdateThreshold_ <= 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            false
        );

        // Set pair with owner (this contract), should revert
        // Pair is backwards, but that's ok for this test
        bytes memory err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        oracle.setPair(tokenOne, tokenTwo, true, oracleData);
    }

    function testFuzz_setPair_oneFeedInverse_add_valid(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            numerUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);

        // Confirm price feed params are set for the pair
        (
            AggregatorV2V3Interface numerFeed,
            uint48 numerUT,
            AggregatorV2V3Interface denomFeed,
            uint48 denomUT,
            uint8 decimals,
            bool div
        ) = oracle.priceFeedParams(tokenTwo, tokenOne);
        bytes memory params = abi.encode(
            address(numerFeed),
            numerUT,
            address(denomFeed),
            denomUT,
            decimals,
            div
        );
        assertEq(params, oracleData);
    }

    function testFuzzRevert_setPair_oneFeedInverse_add_invalid(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_
    ) public {
        // Filter out valid params
        if (
            decimals_ >= 6 &&
            decimals_ <= 18 &&
            numerDecimals_ >= 6 &&
            numerDecimals_ <= 18 &&
            numerUpdateThreshold_ >= 1 hours &&
            numerUpdateThreshold_ <= 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(0),
            uint48(0),
            decimals_,
            true
        );

        // Set pair with owner (this contract), should revert
        // Pair is backwards, but that's ok for this test
        bytes memory err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);
    }

    function testFuzz_setPair_doubleFeedMul_add_valid(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ > numerDecimals_ + denomDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedTwo.setDecimals(denomDecimals_);
        feedTwo.setLatestAnswer(
            (feedTwo.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            false
        );

        // Set pair with owner (this contract), should succeed
        // Pair is backwards, but that's ok for this test
        oracle.setPair(tokenThree, tokenOne, true, oracleData);

        // Confirm price feed params are set for the pair
        (
            AggregatorV2V3Interface numerFeed,
            uint48 numerUT,
            AggregatorV2V3Interface denomFeed,
            uint48 denomUT,
            uint8 decimals,
            bool div
        ) = oracle.priceFeedParams(tokenThree, tokenOne);
        bytes memory params = abi.encode(
            address(numerFeed),
            numerUT,
            address(denomFeed),
            denomUT,
            decimals,
            div
        );
        assertEq(params, oracleData);
    }

    function testFuzzRevert_setPair_doubleFeedMul_add_invalid(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out valid params
        if (
            decimals_ >= 6 &&
            decimals_ <= 18 &&
            numerDecimals_ >= 6 &&
            numerDecimals_ <= 18 &&
            denomDecimals_ >= 6 &&
            denomDecimals_ <= 18 &&
            decimals_ <= numerDecimals_ + denomDecimals_ &&
            numerUpdateThreshold_ >= 1 hours &&
            denomUpdateThreshold_ >= 1 hours &&
            numerUpdateThreshold_ <= 7 days &&
            denomUpdateThreshold_ <= 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedTwo.setDecimals(denomDecimals_);
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedTwo),
            denomUpdateThreshold_,
            decimals_,
            false
        );

        // Set pair with owner (this contract), should revert
        // Pair is backwards, but that's ok for this test
        bytes memory err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        oracle.setPair(tokenThree, tokenOne, true, oracleData);
    }

    function testFuzz_setPair_doubleFeedDiv_valid(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            numerDecimals_ < 6 ||
            numerDecimals_ > 18 ||
            denomDecimals_ < 6 ||
            denomDecimals_ > 18 ||
            decimals_ + denomDecimals_ < numerDecimals_ ||
            numerUpdateThreshold_ < 1 hours ||
            denomUpdateThreshold_ < 1 hours ||
            numerUpdateThreshold_ > 7 days ||
            denomUpdateThreshold_ > 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedOne.setLatestAnswer(
            (feedOne.latestAnswer() * int256(10 ** (numerDecimals_))) / int256(1e18)
        );
        feedThree.setDecimals(denomDecimals_);
        feedThree.setLatestAnswer(
            (feedThree.latestAnswer() * int256(10 ** (denomDecimals_))) / int256(1e18)
        );
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedThree),
            denomUpdateThreshold_,
            decimals_,
            true
        );

        // Set pair with owner (this contract), should succeed
        // Pair is backwards, but that's ok for this test
        oracle.setPair(tokenFour, tokenOne, true, oracleData);

        // Confirm price feed params are set for the pair
        (
            AggregatorV2V3Interface numerFeed,
            uint48 numerUT,
            AggregatorV2V3Interface denomFeed,
            uint48 denomUT,
            uint8 decimals,
            bool div
        ) = oracle.priceFeedParams(tokenFour, tokenOne);
        bytes memory params = abi.encode(
            address(numerFeed),
            numerUT,
            address(denomFeed),
            denomUT,
            decimals,
            div
        );
        assertEq(params, oracleData);
    }

    function testFuzzRevert_setPair_doubleFeedDiv_add_invalid(
        uint8 decimals_,
        uint8 numerDecimals_,
        uint48 numerUpdateThreshold_,
        uint8 denomDecimals_,
        uint48 denomUpdateThreshold_
    ) public {
        // Filter out valid params
        if (
            decimals_ >= 6 &&
            decimals_ <= 18 &&
            numerDecimals_ >= 6 &&
            numerDecimals_ <= 18 &&
            denomDecimals_ >= 6 &&
            denomDecimals_ <= 18 &&
            decimals_ + denomDecimals_ >= numerDecimals_ &&
            numerUpdateThreshold_ >= 1 hours &&
            denomUpdateThreshold_ >= 1 hours &&
            numerUpdateThreshold_ <= 7 days &&
            denomUpdateThreshold_ <= 7 days
        ) return;

        // Setup oracle data for pair
        feedOne.setDecimals(numerDecimals_);
        feedThree.setDecimals(denomDecimals_);
        bytes memory oracleData = abi.encode(
            address(feedOne),
            numerUpdateThreshold_,
            address(feedThree),
            denomUpdateThreshold_,
            decimals_,
            true
        );

        // Set pair with owner (this contract), should revert
        // Pair is backwards, but that's ok for this test
        bytes memory err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        oracle.setPair(tokenFour, tokenOne, true, oracleData);
    }

    function test_setPair_remove() public {
        // Confirm price feed params are set for the pair initially (params not zero)
        (
            AggregatorV2V3Interface numerFeed,
            uint48 numerUT,
            AggregatorV2V3Interface denomFeed,
            uint48 denomUT,
            uint8 decimals,
            bool div
        ) = oracle.priceFeedParams(tokenOne, tokenTwo);
        bytes memory params = abi.encode(numerFeed, numerUT, denomFeed, denomUT, decimals, div);
        assertTrue(keccak256(params) != keccak256(abi.encode(0, 0, 0, 0, 0, 0)));

        // Remove pair with owner (this contract), should succeed
        // Use non-zero data to ensure that it is not stored
        oracle.setPair(tokenOne, tokenTwo, false, abi.encode(1, 1, 1, 1, 1, 1));

        // Confirm price feed params are removed for the pair
        (numerFeed, numerUT, denomFeed, denomUT, decimals, div) = oracle.priceFeedParams(
            tokenOne,
            tokenTwo
        );
        params = abi.encode(numerFeed, numerUT, denomFeed, denomUT, decimals, div);
        assertEq(params, abi.encode(0, 0, 0, 0, 0, 0));
    }

    function testRevert_currentPrice_ArbSequencerDown() public {
        // Register market
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);

        // Get current price for registered market, should succeed
        uint256 price = oracle.currentPrice(0);
        assertEq(price, 8e18);

        // Change Arb Sequencer status to down, should revert
        sequencerFeed.setLatestAnswer(1);

        // Confirm current price reverts
        bytes memory err = abi.encodeWithSignature("BondOracle_SequencerDown()");
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Change Arb Sequencer status to up, but within the restart grace period
        sequencerFeed.setLatestAnswer(0);
        sequencerFeed.setStartedAt(block.timestamp - 60);

        // Confirm current price reverts
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Change Arb Sequencer status to up, and at the restart grace period
        sequencerFeed.setStartedAt(block.timestamp - 1 hours);

        // Confirm current price reverts
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Change Arb Sequencer status to up, and past the restart grace period
        sequencerFeed.setStartedAt(block.timestamp - 1 hours - 1);

        // Confirm current price succeeds
        oracle.currentPrice(0);
    }
}
