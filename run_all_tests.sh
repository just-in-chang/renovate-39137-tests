#!/usr/bin/env bash
set -euo pipefail

IMAGE="cargo-update-tests"
docker build -t "$IMAGE" .

echo "=== Bug Reproduction ==="
docker run --rm "$IMAGE" ./repro_bug.sh

echo ""
echo "=== Scenario 1: Range bump (hashbrown) ==="
docker run --rm "$IMAGE" ./run_tests.sh 1

echo ""
echo "=== Scenario 2: Stale lockedVersion (reqwest) ==="
docker run --rm "$IMAGE" ./run_tests.sh 2

echo ""
echo "=== Scenario 3: Multi-version ambiguity (syn) ==="
docker run --rm "$IMAGE" ./run_tests.sh 3

echo ""
echo "=== E2E Tests (Renovate CLI integration) ==="
E2E_IMAGE="cargo-update-e2e-tests"
docker build -t "$E2E_IMAGE" -f e2e/Dockerfile.e2e .
docker run --rm "$E2E_IMAGE"
