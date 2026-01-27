#!/bin/bash

# OneCal Local Deployment Script
# This script deploys the OneCal booking system to a local blockchain

set -e

echo "==========================================="
echo "OneCal Local Deployment"
echo "==========================================="
echo ""

# Set defaults if not provided
PRIVATE_KEY=${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
PLATFORM_FEE_ADDRESS=${PLATFORM_FEE_ADDRESS:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}
RPC_URL=${RPC_URL:-http://localhost:8545}

# Check if local blockchain is running
echo "🔍 Checking if local blockchain is running on $RPC_URL..."
if ! curl -s -X POST $RPC_URL -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' > /dev/null 2>&1; then
    echo "❌ Error: Cannot connect to local blockchain at $RPC_URL"
    echo ""
    echo "Please start a local blockchain first:"
    echo ""
    echo "Option 1 - Using Anvil (Recommended):"
    echo "  anvil"
    echo ""
    echo "Option 2 - Using Hardhat:"
    echo "  npx hardhat node"
    echo ""
    echo "Option 3 - Using Ganache:"
    echo "  ganache-cli"
    echo ""
    exit 1
fi

echo "✅ Local blockchain is running"
echo ""

# Deploy contracts
echo "🚀 Starting deployment..."
echo ""
echo "Using configuration:"
echo "  RPC URL: $RPC_URL"
echo "  Private Key: ${PRIVATE_KEY:0:10}..."
echo "  Platform Fee Address: $PLATFORM_FEE_ADDRESS"
echo ""

echo "🚀 Deploying MinimalForwarder first..."
echo ""

# Deploy MinimalForwarder and capture the address
MINIMAL_FORWARDER_OUTPUT=$(forge script script/DeployMinimalForwarder.s.sol \
    --fork-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast 2>&1)

echo "$MINIMAL_FORWARDER_OUTPUT"

# Extract MinimalForwarder address from output
MINIMAL_FORWARDER_ADDRESS=$(echo "$MINIMAL_FORWARDER_OUTPUT" | grep -oP 'MinimalForwarder deployed at: \K0x[0-9a-fA-F]{40}' | head -1)

if [ -z "$MINIMAL_FORWARDER_ADDRESS" ]; then
    echo "❌ Failed to extract MinimalForwarder address from deployment output"
    exit 1
fi

echo ""
echo "✅ MinimalForwarder deployed at: $MINIMAL_FORWARDER_ADDRESS"
echo ""

echo "🚀 Deploying MentorRegistry next..."
echo ""

# Deploy MentorRegistry and capture the address
MENTOR_REGISTRY_OUTPUT=$(forge script script/DeployMentorRegistry.s.sol \
    --fork-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast 2>&1)

echo "$MENTOR_REGISTRY_OUTPUT"

# Extract MentorRegistry address from output
MENTOR_REGISTRY_ADDRESS=$(echo "$MENTOR_REGISTRY_OUTPUT" | grep -oP 'MentorRegistry deployed at: \K0x[0-9a-fA-F]{40}' | head -1)

if [ -z "$MENTOR_REGISTRY_ADDRESS" ]; then
    echo "❌ Failed to extract MentorRegistry address from deployment output"
    exit 1
fi

echo ""
echo "✅ MentorRegistry deployed at: $MENTOR_REGISTRY_ADDRESS"
echo ""

echo "🚀 Deploying BookingSystem with MentorRegistry address..."
echo ""

export MENTOR_REGISTRY_ADDRESS=$MENTOR_REGISTRY_ADDRESS

forge script script/DeployBookingSystem.s.sol \
    --fork-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast

echo ""
echo "==========================================="
echo "✅ Deployment Complete!"
echo "==========================================="
echo ""
echo "📝 Contract addresses have been logged above."
echo ""
echo "Next steps:"
echo "1. Save the contract addresses to your frontend config"
echo "2. Run integration tests:"
echo "   forge test"
echo ""
echo "💡 Tip: Use cast to interact with contracts:"
echo "   cast call <CONTRACT_ADDRESS> <FUNCTION> --rpc-url $RPC_URL"
echo ""
