# Load environment variables
# See .env.sample and review the script for what is required to be set
source .env

# Set pair data on the oracle using the BondScripts contract
forge script ./src/scripts/BondScripts.sol:BondScripts --sig "setUniV3Pair(address, address, address, address, uint32, uint8)()" $QUOTE_TOKEN $QUOTE_TOKEN_POOL $PAYOUT_TOKEN $PAYOUT_TOKEN_POOL $UNIV3_TWAP_DURATION 18 --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \
# --broadcast # Uncomment to broadcast the transaction after confirming that the simulation is correct