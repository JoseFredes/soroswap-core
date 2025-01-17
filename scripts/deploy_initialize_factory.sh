#!/bin/bash

# This script is used for setting up and deploying smart contracts to the Soroban network.
# It should be run from the project root directory.
#
# Usage:
# bash /path_to_script/deploy_contracts.sh <network> <n_tokens> <run_setup>
#
# <network>: Name of the Soroban network to connect to.
# <n_tokens>: The number of tokens (this argument is not used in the script but kept for compatibility).
# <run_setup>: Set to "false" to skip running the setup script, any other value will run setup.
#
# Example:
# bash /path_to_script/deploy_contracts.sh standalone 5 false
#
# Dependencies:
# - soroban: Make sure the 'soroban' CLI tool is available.
# - make: Ensure that 'make' is available for building contracts.

# Enable the 'exit immediately' shell option
set -e

# Accept command-line arguments
NETWORK="$1"
N_TOKENS="$2"
RUN_SETUP="$3"

# Validate the input arguments
if [ -z "$NETWORK" ]; then
    echo "Error: Network name must be provided."
    echo "Usage: bash /path_to_script/deploy_contracts.sh <network> <n_tokens> <run_setup>"
    exit 1
fi

# Run the setup script if RUN_SETUP is not set to "false"
if [ "$RUN_SETUP" != "false" ]; then
    bash /workspace/scripts/setup.sh $NETWORK
fi

# Define the arguments to be passed to the 'soroban contract' commands
ARGS="--network $NETWORK --source token-admin"
echo "Using ARGS: $ARGS"

# Create a directory for Soroban files if it doesn't exist
mkdir -p .soroban

echo "--"
echo "--"

# Compile the pair contract
echo "Compile pair contract"
cd /workspace/pair
make build

echo "--"
echo "--"

# Compile the factory contract
echo "Compile factory contract"
cd /workspace/factory
make build

echo "--"
echo "--"

# Define the paths to the compiled WASM files
FACTORY_WASM="/workspace/factory/target/wasm32-unknown-unknown/release/soroswap_factory_contract.wasm"
PAIR_WASM="/workspace/pair/target/wasm32-unknown-unknown/release/soroswap_pair_contract.wasm"
TOKEN_WASM="/workspace/token/soroban_token_contract.wasm"

# Install the Pair contract WASM
echo "Install the Pair contract WASM"
echo "Install a WASM file to the ledger without creating a contract instance"

PAIR_WASM_HASH="$(
soroban contract install $ARGS \
  --wasm $PAIR_WASM
)"
echo "$PAIR_WASM_HASH" > /workspace/.soroban/pair_wasm_hash
echo "Pair contract installed successfully with hash: $PAIR_WASM_HASH"

echo "--"
echo "--"

# Deploy the Factory contract
echo "Deploy the Factory contract"
FACTORY_ID="$(
  soroban contract deploy $ARGS \
    --wasm $FACTORY_WASM
)"
echo "$FACTORY_ID" > /workspace/.soroban/factory_id
echo "SoroswapFactory deployed successfully with FACTORY_ID: $FACTORY_ID"

echo "--"
echo "--"

# Get the token admin address
TOKEN_ADMIN_ADDRESS="$(soroban config identity address token-admin)"

# Initialize the SoroswapFactory contract
echo "Initialize the SoroswapFactory contract"
soroban contract invoke \
  $ARGS \
  --wasm $FACTORY_WASM \
  --id $FACTORY_ID \
  -- \
  initialize \
  --setter "$TOKEN_ADMIN_ADDRESS" \
  --pair_wasm_hash "$PAIR_WASM_HASH"

echo "--"
echo "--"

FACTORY_ADDRESS="$(node /workspace/address_workaround.js $FACTORY_ID)"

# Save the network and factory information in a JSON file
jq -n \
  --arg network "$NETWORK" \
  --arg factory_id "$FACTORY_ID" \
  --arg factory_address "$FACTORY_ADDRESS" \
  '[{"network": $network, "factory_id": $factory_id, "factory_address": $factory_address}]' \
  > /workspace/.soroban/factory.json
# Output the file path and contents
echo "Factory information available in /workspace/.soroban/factory.json"
cat /workspace/.soroban/factory.json
