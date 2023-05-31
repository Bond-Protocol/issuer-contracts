# Load environment variables
# See .env.sample and review the script for what is required to be set
source .env

# Deploy an oracle using the BondScripts contract
forge script ./src/scripts/BondScripts.sol:BondScripts --sig "deployChainlinkOracle()()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \
# --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY # Uncomment to broadcast the transaction after confirming that the simulation is correct