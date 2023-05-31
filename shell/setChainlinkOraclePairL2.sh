# Load environment variables
# See .env.sample and review the script for what is required to be set
source .env

# Set pair data on the oracle using the BondScripts contract
forge script ./src/scripts/BondScripts.sol:BondScripts --sig "setChainlinkPairL2(address, address, address, address, uint8, bool)()" $QUOTE_TOKEN $QUOTE_TOKEN_FEED $PAYOUT_TOKEN $PAYOUT_TOKEN_FEED 18 $DIV_FEEDS --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \
# --broadcast # Uncomment to broadcast the transaction after confirming that the simulation is correct