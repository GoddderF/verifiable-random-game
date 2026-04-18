#!/usr/bin/env bash
# Install Foundry dependencies for contracts/
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/contracts"

echo "Installing forge-std, OpenZeppelin 5.x, Chainlink contracts..."
forge install foundry-rs/forge-std@v1.9.6 --no-commit
forge install OpenZeppelin/openzeppelin-contracts@v5.2.0 --no-commit
forge install smartcontractkit/chainlink-brownie-contracts@1.3.0 --no-commit

echo "Done. Run 'forge build' from contracts/ to verify."
