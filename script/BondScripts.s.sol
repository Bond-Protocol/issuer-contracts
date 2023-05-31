// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";

import {ERC20} from "src/lib/ERC20.sol";
import {IBondAggregator} from "lib/bond-contracts/src/interfaces/IBondAggregator.sol";
import {BondChainlinkOracle} from "src/oracles/BondChainlinkOracle.sol";
import {BondChainlinkOracleL2} from "src/oracles/BondChainlinkOracleL2.sol";
import {BondUniV3Oracle} from "src/oracles/BondUniV3Oracle.sol";
import {BondSampleCallback} from "src/callbacks/BondSampleCallback.sol";
import {AggregatorV2V3Interface} from "src/external/interfaces/AggregatorV2V3Interface.sol";
import {IUniswapV3Pool} from "src/external/interfaces/IUniswapV3Pool.sol";

/// @notice Scripts to deploy and interact with periphery bond contracts
contract BondScripts is Script {
    address public aggregator;
    address public fixedExpiryTeller;
    address public fixedTermTeller;
    address public fixedExpirySDA;
    address public fixedTermSDA;
    address public fixedExpiryOSDA;
    address public fixedTermOSDA;
    address public fixedExpiryOFDA;
    address public fixedTermOFDA;
    address public fixedExpiryFPA;
    address public fixedTermFPA;
    BondChainlinkOracle public chainlinkOracle;
    BondChainlinkOracleL2 public chainlinkOracleL2;
    BondUniV3Oracle public uniV3Oracle;
    BondSampleCallback public sampleCallback;

    /* ========== DEPLOY ========== */
    function deployChainlinkOracle() public {
        aggregator = vm.envAddress("AGGREGATOR_ADDRESS");
        fixedTermOSDA = vm.envAddress("FIXED_TERM_OSDA_ADDRESS");
        fixedExpiryOSDA = vm.envAddress("FIXED_EXP_OSDA_ADDRESS");
        fixedTermOFDA = vm.envAddress("FIXED_TERM_OFDA_ADDRESS");
        fixedExpiryOFDA = vm.envAddress("FIXED_EXP_OFDA_ADDRESS");

        address[] memory auctioneers = new address[](4);
        auctioneers[0] = fixedTermOSDA;
        auctioneers[1] = fixedExpiryOSDA;
        auctioneers[2] = fixedTermOFDA;
        auctioneers[3] = fixedExpiryOFDA;

        vm.broadcast();
        chainlinkOracle = new BondChainlinkOracle(aggregator, auctioneers);
        console2.log("Chainlink Oracle: ", address(chainlinkOracle));
    }

    function deployChainlinkOracleL2() public {
        aggregator = vm.envAddress("AGGREGATOR_ADDRESS");
        fixedTermOSDA = vm.envAddress("FIXED_TERM_OSDA_ADDRESS");
        fixedExpiryOSDA = vm.envAddress("FIXED_EXP_OSDA_ADDRESS");
        fixedTermOFDA = vm.envAddress("FIXED_TERM_OFDA_ADDRESS");
        fixedExpiryOFDA = vm.envAddress("FIXED_EXP_OFDA_ADDRESS");
        address sequencerUptimeFeed = vm.envAddress("SEQUENCER_UPTIME_FEED");

        address[] memory auctioneers = new address[](4);
        auctioneers[0] = fixedTermOSDA;
        auctioneers[1] = fixedExpiryOSDA;
        auctioneers[2] = fixedTermOFDA;
        auctioneers[3] = fixedExpiryOFDA;

        vm.broadcast();
        chainlinkOracleL2 = new BondChainlinkOracleL2(
            aggregator,
            auctioneers,
            sequencerUptimeFeed
        );
        console2.log("Chainlink Oracle: ", address(chainlinkOracleL2));
    }

    function deployUniV3Oracle() public {
        fixedTermOSDA = vm.envAddress("FIXED_TERM_OSDA_ADDRESS");
        fixedExpiryOSDA = vm.envAddress("FIXED_EXP_OSDA_ADDRESS");
        fixedTermOFDA = vm.envAddress("FIXED_TERM_OFDA_ADDRESS");
        fixedExpiryOFDA = vm.envAddress("FIXED_EXP_OFDA_ADDRESS");

        address[] memory auctioneers = new address[](4);
        auctioneers[0] = fixedTermOSDA;
        auctioneers[1] = fixedExpiryOSDA;
        auctioneers[2] = fixedTermOFDA;
        auctioneers[3] = fixedExpiryOFDA;

        vm.broadcast();
        uniV3Oracle = new BondUniV3Oracle(auctioneers);
        console2.log("UniV3 Oracle: ", address(uniV3Oracle));
    }

    function deploySampleCallback() public {
        aggregator = vm.envAddress("AGGREGATOR_ADDRESS");

        vm.broadcast();
        sampleCallback = new BondSampleCallback(IBondAggregator(aggregator));
    }

    /* ========== SET ORACLE DATA ========== */

    function setChainlinkPair(
        address quoteToken,
        address quoteTokenFeed,
        address payoutToken,
        address payoutTokenFeed,
        uint8 decimals,
        bool div
    ) public {
        // Confirm data from feeds
        uint256 quotePrice = uint256(AggregatorV2V3Interface(quoteTokenFeed).latestAnswer());
        uint256 payoutPrice = uint256(AggregatorV2V3Interface(payoutTokenFeed).latestAnswer());

        console2.log("Quote Price: ", quotePrice);
        console2.log("Payout Price: ", payoutPrice);

        console2.log("Oracle Price: ", (payoutPrice * 10**decimals) / quotePrice);

        // Create pair params from inputs
        BondChainlinkOracle.PriceFeedParams memory params = BondChainlinkOracle.PriceFeedParams(
            AggregatorV2V3Interface(payoutTokenFeed),
            24 hours,
            AggregatorV2V3Interface(quoteTokenFeed),
            24 hours,
            decimals,
            div
        );

        // Set the pair on the oracle
        chainlinkOracle = BondChainlinkOracle(vm.envAddress("BOND_CHAINLINK_ORACLE_ADDRESS"));
        vm.broadcast();
        chainlinkOracle.setPair(ERC20(quoteToken), ERC20(payoutToken), true, abi.encode(params));
    }

    function setChainlinkPairL2(
        address quoteToken,
        address quoteTokenFeed,
        address payoutToken,
        address payoutTokenFeed,
        uint8 decimals,
        bool div
    ) public {
        // Confirm data from feeds
        uint256 quotePrice = uint256(AggregatorV2V3Interface(quoteTokenFeed).latestAnswer());
        uint256 payoutPrice = uint256(AggregatorV2V3Interface(payoutTokenFeed).latestAnswer());

        console2.log("Quote Price: ", quotePrice);
        console2.log("Payout Price: ", payoutPrice);

        console2.log("Oracle Price: ", (payoutPrice * 10**decimals) / quotePrice);

        // Create pair params from inputs
        BondChainlinkOracleL2.PriceFeedParams memory params = BondChainlinkOracleL2.PriceFeedParams(
            AggregatorV2V3Interface(payoutTokenFeed),
            24 hours,
            AggregatorV2V3Interface(quoteTokenFeed),
            24 hours,
            decimals,
            div
        );

        // Set the pair on the oracle
        chainlinkOracleL2 = BondChainlinkOracleL2(vm.envAddress("BOND_CHAINLINK_ORACLE_ADDRESS"));
        vm.broadcast();
        chainlinkOracleL2.setPair(ERC20(quoteToken), ERC20(payoutToken), true, abi.encode(params));
    }

    function setUniV3Pair(
        address quoteToken,
        address quoteTokenPool,
        address payoutToken,
        address payoutTokenPool,
        uint32 observationWindowSeconds,
        uint8 decimals,
    ) public {
        // Create pair from inputs
        BondUniV3Oracle.UniswapV3Params memory params = BondUniV3Oracle.UniswapV3Params(
            IUniswapV3Pool(payoutTokenPool),
            IUniswapV3Pool(quoteTokenPool),
            observationWindowSeconds,
            decimals
        );

        // Set the pair on the oracle
        uniV3Oracle = BondUniV3Oracle(vm.envAddress("BOND_UNIV3_ORACLE_ADDRESS"));
        vm.broadcast();
        uniV3Oracle.setPair(ERC20(quoteToken), ERC20(payoutToken), true, abi.encode(params));
    }

    
}