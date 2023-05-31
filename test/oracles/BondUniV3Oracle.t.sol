// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "lib/forge-std/src/Test.sol";
import {console2} from "lib/forge-std/src/console2.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

import {BondUniV3Oracle, IUniswapV3Pool, OracleLibrary} from "src/oracles/BondUniV3Oracle.sol";

import {FullMath} from "src/lib/FullMath.sol";

contract MockAggregator {
    mapping(uint256 => address) public marketsToAuctioneers;

    function getAuctioneer(uint256 id) public view returns (address) {
        return marketsToAuctioneers[id];
    }

    function setMarketAuctioneer(uint256 id, address auctioneer) public {
        marketsToAuctioneers[id] = auctioneer;
    }
}

contract BondUniV3OracleTest is Test {
    using FullMath for uint256;

    address public user;
    address public auctioneer;
    MockAggregator public aggregator;

    MockERC20 public tokenOne;
    MockERC20 public tokenTwo;
    MockERC20 public tokenThree;

    MockUniV3Pair public poolOne;
    MockUniV3Pair public poolTwo;
    BondUniV3Oracle public oracle;

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

        // Deploy mock pool and set params

        // T1 <> T2
        // Set to a price of 2 T1 per T2
        // Weighted tick needs to be 6931
        // Therefore, tick difference needs to be 415909 for a 60 second period
        poolOne = new MockUniV3Pair();
        poolOne.setToken0(address(tokenOne));
        poolOne.setToken1(address(tokenTwo));
        // 600 second tick cumulative
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = int56(-1000415909);
        tickCumulatives[1] = int56(-1000000000);
        poolOne.setTickCumulatives(tickCumulatives);
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - 3600));

        // T2 <> T3
        // Set to a price of 10 T2 per T3
        // Weighted tick needs to be 23027
        // Therefore, tick difference needs to be 1381620 for a 60 second period
        poolTwo = new MockUniV3Pair();
        poolTwo.setToken0(address(tokenTwo));
        poolTwo.setToken1(address(tokenThree));
        tickCumulatives[0] = int56(1001381620);
        tickCumulatives[1] = int56(1000000000);
        poolTwo.setTickCumulatives(tickCumulatives);
        poolTwo.setFirstObsTimestamp(uint32(block.timestamp - 3600));

        // Cases:
        // Single pool: poolOne = T1 <> T2
        // Double pool: poolOne & poolTwo = T1 <> T2 <> T3

        // Deploy mock aggregator
        aggregator = new MockAggregator();

        // Deploy oracle
        address[] memory auctioneers = new address[](1);
        auctioneers[0] = auctioneer;
        oracle = new BondUniV3Oracle(address(aggregator), auctioneers);

        // Set pairs on oracle

        // Case 1: Single Pool: T1 <> T2 and T2 <> T3
        bytes memory singlePool = abi.encode(address(poolOne), address(0), uint32(60), uint8(18));
        oracle.setPair(tokenOne, tokenTwo, true, singlePool);

        singlePool = abi.encode(address(poolTwo), address(0), uint32(60), uint8(18));
        oracle.setPair(tokenTwo, tokenThree, true, singlePool);

        // Case 3: Double Pool: T1 <> T2 <> T3
        bytes memory doublePool = abi.encode(
            address(poolTwo),
            address(poolOne),
            uint32(60),
            uint8(18)
        );

        oracle.setPair(tokenOne, tokenThree, true, doublePool);
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

    /* ==================== SAMPLE UNIV3 ORACLE TESTS ==================== */
    //  [X] Set Pair
    //      [X] Price feed parameters are set correctly - one pool
    //      [X] Price feed parameters are set correctly - two pool
    //      [X] Price reverts if support for pair is removed
    //  [X] One Pool Price
    //  [X] Two Pool Price
    //  [X] Decimals

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
            tokenThree,
            tokenOne
        );
        vm.expectRevert(err);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenThree, tokenOne);

        // Register market with auctioneer and valid pair, should succeed
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);
    }

    function test_currentPrice() public {
        // Try to get current price for market that hasn't been registered, should fail
        bytes memory err = abi.encodeWithSignature("BondOracle_MarketNotRegistered(uint256)", 0);
        vm.expectRevert(err);
        oracle.currentPrice(0);

        // Pool One
        // Register market
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);

        // Get current price for registered market, should succeed
        uint256 price = oracle.currentPrice(0);
        // Calculate the return value
        assertApproxEqAbsDecimal(price, 2 ether, 10 ** 15, 18); // accurate to the nearest thousandths, not exact due to tick math

        // Register market
        aggregator.setMarketAuctioneer(1, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(1, tokenTwo, tokenThree);

        // Get current price for registered market, should succeed
        price = oracle.currentPrice(1);
        // Calculate the return value
        assertApproxEqAbsDecimal(price, 10 ether, 10 ** 15, 18); // accurate to the nearest thousandths, not exact due to tick math
    }

    function testFuzz_currentPrice_singlePool(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (decimals_ < 6 || decimals_ > 18 || obsWindow_ < 19 || obsWindow_ > 86400) return;

        // Setup oracle data for pair
        // Target is 2 T1 per T2
        // Weighted tick needs to be 6931
        // Therefore, we calculate the tick difference from the obsWindow provided
        int56 tick = int56(6931 * int32(obsWindow_));
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = -1000000000 - tick;
        tickCumulatives[1] = -1000000000;
        poolOne.setTickCumulatives(tickCumulatives);
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(address(poolOne), address(0), obsWindow_, decimals_);

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenTwo, true, oracleData);

        // Register market for auctioneer
        aggregator.setMarketAuctioneer(0, auctioneer);
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(0);

        // Calculate expected price and compare
        uint256 expectedPrice = 2 * 10 ** decimals_;

        assertApproxEqAbsDecimal(price, expectedPrice, 10 ** (decimals_ - 3), decimals_);
    }

    function testFuzz_currentPrice_doublePool(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (decimals_ < 6 || decimals_ > 18 || obsWindow_ < 19 || obsWindow_ > 86400) return;

        // Setup oracle data for pairs
        // Target is 2 T1 per T2
        // Weighted tick needs to be 6931
        // Therefore, we calculate the tick difference from the obsWindow provided
        int56 tick = int56(6931 * int32(obsWindow_));
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = -1000000000 - tick;
        tickCumulatives[1] = -1000000000;
        poolOne.setTickCumulatives(tickCumulatives);
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));

        // Target is 10 T2 per T3
        // Weighted tick needs to be 23027
        // Therefore, we calculate the tick difference from the obsWindow provided
        tick = int56(23027 * int32(obsWindow_));
        tickCumulatives[0] = 1000000000 + tick;
        tickCumulatives[1] = 1000000000;
        poolTwo.setTickCumulatives(tickCumulatives);
        poolTwo.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(
            address(poolTwo),
            address(poolOne),
            obsWindow_,
            decimals_
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
        uint256 expectedPrice = 2 * 10 * 10 ** decimals_;

        assertApproxEqAbsDecimal(price, expectedPrice, 10 ** (decimals_ - 2), decimals_);
    }

    function test_currentPricePair() public {
        // Try to get current price for a pair that is not set, should fail
        bytes memory err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            tokenTwo,
            tokenOne
        );
        vm.expectRevert(err);
        oracle.currentPrice(tokenTwo, tokenOne);

        // Set pair on the oracle
        bytes memory oracleData = abi.encode(address(poolOne), address(0), uint32(60), uint8(18));
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(tokenTwo, tokenOne);
        assertApproxEqAbsDecimal(price, 0.5 ether, 10 ** 14, 18);

        // Set a two pool pair on the oracle
        oracleData = abi.encode(address(poolOne), address(poolTwo), uint32(60), uint8(18));
        oracle.setPair(tokenThree, tokenOne, true, oracleData);

        // Get current price for pair, should succeed
        price = oracle.currentPrice(tokenThree, tokenOne);
        assertApproxEqAbsDecimal(price, 0.05 ether, 10 ** 13, 18);

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
            tokenTwo,
            address(0)
        );
        vm.expectRevert(err);
        oracle.currentPrice(tokenTwo, MockERC20(address(0)));

        // Try to get current price for a pair with both tokens zero address, should fail
        err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            address(0),
            address(0)
        );
        vm.expectRevert(err);
        oracle.currentPrice(MockERC20(address(0)), MockERC20(address(0)));
    }

    function testFuzz_currentPricePair_singlePool(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (decimals_ < 6 || decimals_ > 18 || obsWindow_ < 19 || obsWindow_ > 86400) return;

        // Setup oracle data for pair
        // Target is 0.5 T2 per T1
        // Weighted tick needs to be 6931
        // Therefore, we calculate the tick difference from the obsWindow provided
        int56 tick = int56(6931 * int32(obsWindow_));
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = -1000000000 - tick;
        tickCumulatives[1] = -1000000000;
        poolOne.setTickCumulatives(tickCumulatives);
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(address(poolOne), address(0), obsWindow_, decimals_);

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(tokenTwo, tokenOne);

        // Calculate expected price and compare
        uint256 expectedPrice = (5 * 10 ** decimals_) / 10;

        assertApproxEqAbsDecimal(price, expectedPrice, 10 ** (decimals_ - 4), decimals_);
    }

    function testFuzz_currentPricePair_doublePool(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (decimals_ < 6 || decimals_ > 18 || obsWindow_ < 19 || obsWindow_ > 86400) return;

        // Setup oracle data for pairs
        // Target is 0.5 T2 per T1
        // Weighted tick needs to be 6931
        // Therefore, we calculate the tick difference from the obsWindow provided
        int56 tick = int56(6931 * int32(obsWindow_));
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = -1000000000 - tick;
        tickCumulatives[1] = -1000000000;
        poolOne.setTickCumulatives(tickCumulatives);
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));

        // Target is 0.1 T3 per T2
        // Weighted tick needs to be 23027
        // Therefore, we calculate the tick difference from the obsWindow provided
        tick = int56(23027 * int32(obsWindow_));
        tickCumulatives[0] = 1000000000 + tick;
        tickCumulatives[1] = 1000000000;
        poolTwo.setTickCumulatives(tickCumulatives);
        poolTwo.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(
            address(poolOne),
            address(poolTwo),
            obsWindow_,
            decimals_
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenThree, tokenOne, true, oracleData);

        // Get current price for pair, should succeed
        uint256 price = oracle.currentPrice(tokenThree, tokenOne);

        // Calculate expected price and compare
        uint256 expectedPrice = (5 * 10 ** decimals_) / 100;

        assertApproxEqAbsDecimal(price, expectedPrice, 10 ** (decimals_ - 5), decimals_);
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

    function testFuzz_decimals_onePool(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (decimals_ < 6 || decimals_ > 18 || obsWindow_ < 19 || obsWindow_ > 86400) return;

        // Setup oracle data for pair
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(address(poolOne), address(0), obsWindow_, decimals_);

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

    function testFuzz_decimals_twoPool(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (decimals_ < 6 || decimals_ > 18 || obsWindow_ < 19 || obsWindow_ > 86400) return;

        // Setup oracle data for pair
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        poolTwo.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(
            address(poolTwo),
            address(poolOne),
            obsWindow_,
            decimals_
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
            tokenThree,
            tokenOne
        );
        vm.expectRevert(err);
        oracle.decimals(tokenThree, tokenOne);

        // Set pair on the oracle with single pool, should succeed
        bytes memory oracleData = abi.encode(address(poolOne), address(0), uint32(60), uint8(18));
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(tokenTwo, tokenOne);
        assertEq(decimals, 18);

        // Set pair on the oracle with single pool, should succeed
        oracleData = abi.encode(address(poolOne), address(poolTwo), uint32(60), uint8(18));
        oracle.setPair(tokenThree, tokenOne, true, oracleData);

        // Get decimals for pair, should succeed
        decimals = oracle.decimals(tokenThree, tokenOne);
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
            tokenThree,
            address(0)
        );
        vm.expectRevert(err);
        oracle.decimals(tokenThree, MockERC20(address(0)));

        // Try to get decimals for a pair with both tokens zero address, should fail
        err = abi.encodeWithSignature(
            "BondOracle_PairNotSupported(address,address)",
            address(0),
            address(0)
        );
        vm.expectRevert(err);
        oracle.decimals(MockERC20(address(0)), MockERC20(address(0)));
    }

    function testFuzz_decimalsPair_onePool(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (decimals_ < 6 || decimals_ > 18 || obsWindow_ < 19 || obsWindow_ > 86400) return;

        // Setup oracle data for pair
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(address(poolOne), address(0), obsWindow_, decimals_);

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenTwo, tokenOne, true, oracleData);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(tokenTwo, tokenOne);

        // Compare actual and expected decimals
        assertEq(decimals, decimals_);
    }

    function testFuzz_decimalsPair_twoPool(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (decimals_ < 6 || decimals_ > 18 || obsWindow_ < 19 || obsWindow_ > 86400) return;

        // Setup oracle data for pair
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        poolTwo.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(
            address(poolOne),
            address(poolTwo),
            obsWindow_,
            decimals_
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenThree, tokenOne, true, oracleData);

        // Get decimals for pair, should succeed
        uint8 decimals = oracle.decimals(tokenThree, tokenOne);

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
            address(poolOne),
            address(poolTwo),
            uint32(60),
            uint8(18)
        );

        // Confirm pair is not set yet
        (
            IUniswapV3Pool numerPool,
            IUniswapV3Pool denomPool,
            uint32 obsWindow,
            uint8 decimals
        ) = oracle.uniswapV3Params(tokenThree, tokenOne);
        bytes memory params = abi.encode(
            address(numerPool),
            address(denomPool),
            obsWindow,
            decimals
        );
        assertEq(params, abi.encode(0, 0, 0, 0));

        // Try to set pair with non-owner, should fail
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(addr);
        oracle.setPair(tokenThree, tokenOne, true, oracleData);

        // Set pair with owner (this contract), should succeed
        // Pair is backwards, but that's ok for this test
        oracle.setPair(tokenThree, tokenOne, true, oracleData);

        // Confirm pair is set correctly
        (numerPool, denomPool, obsWindow, decimals) = oracle.uniswapV3Params(tokenThree, tokenOne);
        params = abi.encode(address(numerPool), address(denomPool), obsWindow, decimals);
        assertEq(params, oracleData);

        // Try to remove pair with non-owner, should fail
        vm.expectRevert(err);
        vm.prank(addr);
        oracle.setPair(tokenThree, tokenOne, false, oracleData);

        // Remove pair with owner (this contract), should succeed
        // Pair is backwards, but that's ok for this test
        oracle.setPair(tokenThree, tokenOne, false, oracleData);

        // Confirm pair is removed
        (numerPool, denomPool, obsWindow, decimals) = oracle.uniswapV3Params(tokenThree, tokenOne);
        params = abi.encode(address(numerPool), address(denomPool), obsWindow, decimals);
        assertEq(params, abi.encode(0, 0, 0, 0));
    }

    function testFuzz_setPair_onePool_add_valid(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            obsWindow_ < 19 ||
            obsWindow_ > uint32(block.timestamp - 3600)
        ) return;

        // Setup oracle data for pair
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(address(poolOne), address(0), obsWindow_, decimals_);

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenOne, tokenTwo, true, oracleData);

        // Confirm price feed params are set for the pair
        (
            IUniswapV3Pool numerPool,
            IUniswapV3Pool denomPool,
            uint32 obsWindow,
            uint8 decimals
        ) = oracle.uniswapV3Params(tokenOne, tokenTwo);
        bytes memory params = abi.encode(
            address(numerPool),
            address(denomPool),
            obsWindow,
            decimals
        );
        assertEq(params, oracleData);
    }

    function testFuzzRevert_setPair_onePool_add_invalid(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out valid params
        if (
            (decimals_ >= 6 && decimals_ <= 18 && obsWindow_ >= 19) ||
            obsWindow_ > uint32(block.timestamp - 3600)
        ) return;

        // Setup oracle data for pair
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(address(poolOne), address(0), obsWindow_, decimals_);

        // Set pair with owner (this contract), should revert
        // Pair is backwards, but that's ok for this test
        bytes memory err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        oracle.setPair(tokenOne, tokenTwo, true, oracleData);
    }

    function testFuzz_setPair_doublePool_add_valid(uint8 decimals_, uint32 obsWindow_) public {
        // Filter out invalid params
        if (
            decimals_ < 6 ||
            decimals_ > 18 ||
            obsWindow_ < 19 ||
            obsWindow_ > uint32(block.timestamp - 3600)
        ) return;

        // Setup oracle data for pair
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        poolTwo.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(
            address(poolOne),
            address(poolTwo),
            obsWindow_,
            decimals_
        );

        // Set pair with owner (this contract), should succeed
        oracle.setPair(tokenThree, tokenOne, true, oracleData);

        // Confirm price feed params are set for the pair
        (
            IUniswapV3Pool numerPool,
            IUniswapV3Pool denomPool,
            uint32 obsWindow,
            uint8 decimals
        ) = oracle.uniswapV3Params(tokenThree, tokenOne);
        bytes memory params = abi.encode(
            address(numerPool),
            address(denomPool),
            obsWindow,
            decimals
        );
        assertEq(params, oracleData);
    }

    function testFuzzRevert_setPair_doublePool_add_invalid(
        uint8 decimals_,
        uint32 obsWindow_
    ) public {
        // Filter out valid params
        if (
            (decimals_ >= 6 && decimals_ <= 18 && obsWindow_ >= 19) ||
            obsWindow_ > uint32(block.timestamp - 3600)
        ) return;

        // Setup oracle data for pair
        poolOne.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        poolTwo.setFirstObsTimestamp(uint32(block.timestamp - obsWindow_ - 3600));
        bytes memory oracleData = abi.encode(
            address(poolOne),
            address(poolTwo),
            obsWindow_,
            decimals_
        );

        // Set pair with owner (this contract), should revert
        bytes memory err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        oracle.setPair(tokenThree, tokenOne, true, oracleData);
    }

    function test_setPair_noZeroAddress() public {
        // Try to set pair with first token zero address, should revert
        bytes memory err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        oracle.setPair(
            MockERC20(address(0)),
            tokenOne,
            true,
            abi.encode(address(poolOne), 0, 60, 18)
        );

        // Try to set pair with second token zero address, should revert
        vm.expectRevert(err);
        oracle.setPair(
            tokenOne,
            MockERC20(address(0)),
            true,
            abi.encode(address(poolOne), 0, 60, 18)
        );

        // Try to set pair with both tokens zero address, should revert
        vm.expectRevert(err);
        oracle.setPair(
            MockERC20(address(0)),
            MockERC20(address(0)),
            true,
            abi.encode(address(poolOne), 0, 60, 18)
        );
    }

    function test_setPair_remove() public {
        // Confirm price feed params are set for the pair initially (params not zero)
        (
            IUniswapV3Pool numerPool,
            IUniswapV3Pool denomPool,
            uint32 obsWindow,
            uint8 decimals
        ) = oracle.uniswapV3Params(tokenOne, tokenTwo);
        bytes memory params = abi.encode(numerPool, denomPool, obsWindow, decimals);
        assertTrue(keccak256(params) != keccak256(abi.encode(0, 0, 0, 0)));

        // Register market on pair to check price
        aggregator.setMarketAuctioneer(0, address(auctioneer));
        vm.prank(auctioneer);
        oracle.registerMarket(0, tokenOne, tokenTwo);

        // Get price, should succeed
        oracle.currentPrice(0);

        // Remove pair with owner (this contract), should succeed
        // Use non-zero data to ensure that it is not stored
        oracle.setPair(tokenOne, tokenTwo, false, abi.encode(address(poolTwo), address(0), 60, 18));

        // Confirm price feed params are removed for the pair
        (numerPool, denomPool, obsWindow, decimals) = oracle.uniswapV3Params(tokenOne, tokenTwo);
        params = abi.encode(numerPool, denomPool, obsWindow, decimals);
        assertEq(params, abi.encode(0, 0, 0, 0));

        // Get price, should revert
        bytes memory err = abi.encodeWithSignature("BondOracle_InvalidParams()");
        vm.expectRevert(err);
        oracle.currentPrice(0);
    }
}
