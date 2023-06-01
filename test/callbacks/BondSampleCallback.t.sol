// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "lib/forge-std/src/Test.sol";
import {console2} from "lib/forge-std/src/console2.sol";

import {MockERC20} from "lib/bond-contracts/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {RolesAuthority, Authority} from "lib/bond-contracts/lib/solmate/src/auth/authorities/RolesAuthority.sol";

import {IBondSDA} from "lib/bond-contracts/src/interfaces/IBondSDA.sol";
import {IBondCallback} from "src/interfaces/IBondCallback.sol";

import {BondFixedExpirySDA} from "lib/bond-contracts/src/BondFixedExpirySDA.sol";
import {BondFixedExpiryTeller} from "lib/bond-contracts/src/BondFixedExpiryTeller.sol";
import {BondAggregator} from "lib/bond-contracts/src/BondAggregator.sol";
import {ERC20BondToken} from "lib/bond-contracts/src/ERC20BondToken.sol";
import {BondSampleCallback} from "src/callbacks/BondSampleCallback.sol";

import {FullMath} from "lib/bond-contracts/src/lib/FullMath.sol";

contract BondSampleCallbackTest is Test {
    using FullMath for uint256;

    address internal alice;
    address internal bob;
    address internal carol;
    address internal guardian;
    address internal policy;
    address internal treasury;
    address internal referrer;

    RolesAuthority internal auth;
    BondFixedExpirySDA internal auctioneer;
    BondFixedExpiryTeller internal teller;
    BondAggregator internal aggregator;
    MockERC20 internal payoutToken;
    MockERC20 internal quoteToken;
    IBondSDA.MarketParams internal params;
    BondSampleCallback internal callback;

    uint8 internal constant BASE_DECIMALS = 18;
    uint8 internal constant QUOTE_DECIMALS = 18;
    int8 internal constant BASE_PRICE_DECIMALS = 0;
    int8 internal constant QUOTE_PRICE_DECIMALS = 3;
    uint256 internal bid;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        alice = address(uint160(uint256(keccak256(abi.encodePacked("alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("bob")))));
        carol = address(uint160(uint256(keccak256(abi.encodePacked("carol")))));
        guardian = address(uint160(uint256(keccak256(abi.encodePacked("guardian")))));
        policy = address(uint160(uint256(keccak256(abi.encodePacked("policy")))));
        treasury = address(uint160(uint256(keccak256(abi.encodePacked("treasury")))));
        referrer = address(uint160(uint256(keccak256(abi.encodePacked("referrer")))));
        auth = new RolesAuthority(address(this), Authority(address(0)));

        // Deploy fresh contracts
        aggregator = new BondAggregator(guardian, auth);
        teller = new BondFixedExpiryTeller(policy, aggregator, guardian, auth);
        auctioneer = new BondFixedExpirySDA(teller, aggregator, guardian, auth);

        // Configure access control on Authority
        // Role 0 - Guardian
        // Aggregator
        auth.setRoleCapability(
            uint8(0),
            address(aggregator),
            aggregator.registerAuctioneer.selector,
            true
        );

        // Teller
        auth.setRoleCapability(uint8(0), address(teller), teller.setProtocolFee.selector, true);

        // Auctioneer
        auth.setRoleCapability(
            uint8(0),
            address(auctioneer),
            auctioneer.setAllowNewMarkets.selector,
            true
        );
        auth.setRoleCapability(
            uint8(0),
            address(auctioneer),
            auctioneer.setCallbackAuthStatus.selector,
            true
        );

        // Role 1 - Policy
        // Auctioneer
        auth.setRoleCapability(
            uint8(1),
            address(auctioneer),
            auctioneer.setDefaults.selector,
            true
        );

        // Assign roles to addresses
        auth.setUserRole(guardian, uint8(0), true);
        auth.setUserRole(policy, uint8(1), true);

        // Configure protocol
        vm.prank(guardian);
        auctioneer.setCallbackAuthStatus(address(this), true);
        vm.prank(guardian);
        aggregator.registerAuctioneer(auctioneer);

        // Deploy token and callback contracts
        payoutToken = new MockERC20("Payout Token", "BT", BASE_DECIMALS);
        quoteToken = new MockERC20("Quote Token", "QT", QUOTE_DECIMALS);
        callback = new BondSampleCallback(aggregator);

        // Mint tokens to users for testing
        uint256 testAmount = 1_000_000 * 10**uint8(int8(QUOTE_DECIMALS) - QUOTE_PRICE_DECIMALS);

        quoteToken.mint(alice, testAmount);
        quoteToken.mint(bob, testAmount);
        quoteToken.mint(carol, testAmount);

        // Mint tokens to callback for payouts
        payoutToken.mint(address(callback), testAmount * 3);

        // Approve the teller for the tokens
        vm.prank(alice);
        quoteToken.approve(address(teller), testAmount);
        vm.prank(bob);
        quoteToken.approve(address(teller), testAmount);
        vm.prank(carol);
        quoteToken.approve(address(teller), testAmount);

        // Create market
        bid = createMarket(
            BASE_DECIMALS,
            QUOTE_DECIMALS,
            true,
            BASE_PRICE_DECIMALS,
            QUOTE_PRICE_DECIMALS
        );
    }

    function createMarket(
        uint8 _payoutDecimals,
        uint8 _quoteDecimals,
        bool _capacityInQuote,
        int8 _payoutPriceDecimals,
        int8 _quotePriceDecimals
    ) internal returns (uint256 id_) {
        uint256 capacity = _capacityInQuote
            ? 500_000 * 10**uint8(int8(_quoteDecimals) - _quotePriceDecimals)
            : 100_000 * 10**uint8(int8(_payoutDecimals) - _payoutPriceDecimals);

        int8 scaleAdjustment = int8(_payoutDecimals) -
            int8(_quoteDecimals) -
            (_payoutPriceDecimals - _quotePriceDecimals) /
            2;

        uint256 initialPrice = 5 *
            10 **
                (
                    uint8(
                        int8(36 + _quoteDecimals - _payoutDecimals) +
                            scaleAdjustment +
                            _payoutPriceDecimals -
                            _quotePriceDecimals
                    )
                );

        // PNG - payout token = $0.33
        // USDC/USDT LP - quote token = $2,000,000,000,000
        // price = 8 * 10**(scalingDecimals - 5)
        // capacity (in payout token) = 200_000 * 10**_payoutDecimals

        // console2.log("Price", initialPrice);
        // uint256 debt = _capacityInQuote ? capacity.mulDiv(scale, initialPrice) : capacity;
        // console2.log("Expected Debt", debt);
        // uint256 controlVariable = initialPrice.mulDiv(scale, debt);
        // console2.log("Control Variable", controlVariable);

        uint256 minimumPrice = 2 *
            10 **
                (
                    uint8(
                        int8(36 + _quoteDecimals - _payoutDecimals) +
                            scaleAdjustment +
                            _payoutPriceDecimals -
                            _quotePriceDecimals
                    )
                );
        uint32 debtBuffer = 50_000;
        uint48 vesting = uint48(block.timestamp + 14 days);
        uint32 duration = 7 days;
        uint32 depositInterval = 7 days / 10;

        params = IBondSDA.MarketParams(
            payoutToken, // ERC20 payoutToken
            quoteToken, // ERC20 quoteToken
            address(callback), // address callbackAddr
            _capacityInQuote, // bool capacityIn
            capacity, // uint256 capacity
            initialPrice, // uint256 initialPrice
            minimumPrice, // uint256 minimumPrice
            debtBuffer, // uint32 debtBuffer
            vesting, // uint48 vesting (timestamp or duration)
            uint48(0), // uint48 start (timestamp), 0 means immediate
            duration, // uint32 duration (seconds)
            depositInterval, // uint32 depositInterval (duration)
            scaleAdjustment // int8 scaleAdjustment
        );

        return auctioneer.createMarket(abi.encode(params));
    }

    function testCorrectness_OnlyWhitelistedMarketsCanCallback() public {
        // Mint tokens to callback to simulate deposit from teller
        quoteToken.mint(address(callback), 10);

        // Get balance of payoutTokens in callback to start
        uint256 oldCallbackBal = payoutToken.balanceOf(address(callback));
        uint256 oldTellerBal = payoutToken.balanceOf(address(teller));

        // Attempt callback from teller before whitelist, expect to fail
        bytes memory err = abi.encodeWithSignature("Callback_MarketNotSupported(uint256)", bid);
        vm.prank(address(teller));
        vm.expectRevert(err);
        callback.callback(bid, 10, 10);

        // Check balances are still the same
        uint256 newCallbackBal = payoutToken.balanceOf(address(callback));
        uint256 newTellerBal = payoutToken.balanceOf(address(teller));
        assertEq(newCallbackBal, oldCallbackBal);
        assertEq(newTellerBal, oldTellerBal);

        // Whitelist the bond market
        callback.whitelist(address(teller), bid);

        // Attempt callback from teller after whitelist, expect to succeed
        vm.prank(address(teller));
        callback.callback(bid, 10, 10);

        // Check new balances are different
        newCallbackBal = payoutToken.balanceOf(address(callback));
        newTellerBal = payoutToken.balanceOf(address(teller));
        assertEq(newCallbackBal, oldCallbackBal - 10);
        assertEq(newTellerBal, oldTellerBal + 10);
    }

    function testCorrectness_OwnerCanWhitelist() public {
        // Whitelist the bond market from the owner address
        callback.whitelist(address(teller), bid);

        // Check whitelist is applied
        assert(callback.approvedMarkets(address(teller), bid));
    }

    function testCorrectness_TellerMustMatchForMarketId() public {
        // Try to whitelist a market Id on a teller that doesn't match the market
        bytes memory err = abi.encodeWithSignature("Callback_TellerMismatch()");
        vm.expectRevert(err);
        callback.whitelist(address(bob), bid);

        // Whitelist the bond market from the owner address
        callback.whitelist(address(teller), bid);

        // Try to black list a market ID on a teller that doesn't match the market
        vm.expectRevert(err);
        callback.blacklist(address(bob), bid);
    }

    function testCorrectness_MarketIdMustBeValid() public {
        // Try to whitelist a market Id that doesn't exist on the aggregator
        uint256 nextMarket = aggregator.marketCounter();
        bytes memory err = abi.encodeWithSignature(
            "Callback_MarketNotSupported(uint256)",
            nextMarket
        );
        vm.expectRevert(err);
        callback.whitelist(address(teller), nextMarket);

        // Try to whitelist a market Id that has been closed
        auctioneer.closeMarket(bid);

        err = abi.encodeWithSignature("Callback_MarketNotSupported(uint256)", bid);
        vm.expectRevert(err);
        callback.whitelist(address(teller), bid);
    }

    function testFail_NonOwnerCannotWhitelist() public {
        // Try to whitelist from a non-owner address
        vm.prank(alice);
        callback.whitelist(address(teller), bid);
    }

    function testCorrectness_blacklist() public {
        // Whitelist the bond market from the owner address
        callback.whitelist(address(teller), bid);

        // Check whitelist is applied
        assert(callback.approvedMarkets(address(teller), bid));

        // Remove the market from the whitelist from the owner address
        callback.blacklist(address(teller), bid);

        // Check whitelist is removed
        assert(!callback.approvedMarkets(address(teller), bid));
    }

    function testFail_NonOwnerCannotBlacklist() public {
        // Whitelist the bond market from the owner address
        callback.whitelist(address(teller), bid);

        // Try to blacklist from a non-owner address
        vm.prank(alice);
        callback.blacklist(address(teller), bid);
    }

    function testCorrectness_AmountsForMarketView() public {
        // Mint tokens to callback to simulate deposit from teller
        quoteToken.mint(address(callback), 10);

        // Whitelist the bond market
        callback.whitelist(address(teller), bid);

        // Check that the amounts for market doesn't reflect transfer in tokens
        (uint256 oldQuoteAmount, uint256 oldPayoutAmount) = callback.amountsForMarket(bid);
        assertEq(oldQuoteAmount, 0);
        assertEq(oldPayoutAmount, 0);

        // Attempt callback from teller after whitelist, expect to succeed
        vm.prank(address(teller));
        callback.callback(bid, 10, 10);

        // Check amounts are updated after callback
        (uint256 newQuoteAmount, uint256 newPayoutAmount) = callback.amountsForMarket(bid);
        assertEq(newQuoteAmount, 10);
        assertEq(newPayoutAmount, 10);
    }
}
