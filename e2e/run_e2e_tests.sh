#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

test_fixture() {
    local dir="$1" name="$2" scenario_json="$3"
    local logfile="/tmp/e2e-$(basename "$dir").log"

    echo -e "${CYAN}━━━ $name ━━━${RESET}"

    # Run updateArtifacts against the fixture via tsx
    tsx /tests/e2e/test_update_artifacts.ts "$dir" "$scenario_json" 2>&1 | tee "$logfile" || true

    # Check results
    if grep -q "package ID specification did not match" "$logfile"; then
        echo -e "  ${RED}FAIL${RESET} $name — found 'package ID specification did not match' error"
        FAIL=$((FAIL + 1))
    elif grep -q "RESULT:SUCCESS" "$logfile"; then
        echo -e "  ${GREEN}PASS${RESET} $name — updateArtifacts succeeded"
        PASS=$((PASS + 1))
    elif grep -q "RESULT:NO_CHANGE" "$logfile"; then
        echo -e "  ${GREEN}PASS${RESET} $name — updateArtifacts found no changes (lockfile already up to date)"
        PASS=$((PASS + 1))
    elif grep -q "RESULT:ERROR" "$logfile"; then
        echo -e "  ${RED}FAIL${RESET} $name — updateArtifacts returned an error"
        grep "ARTIFACT_ERROR\|EXCEPTION\|STDERR" "$logfile" | head -5
        FAIL=$((FAIL + 1))
    else
        echo -e "  ${RED}FAIL${RESET} $name — unexpected output"
        tail -10 "$logfile"
        FAIL=$((FAIL + 1))
    fi
    echo ""
}

echo -e "${BOLD}Renovate e2e tests for cargoUpdatePrecise fix${RESET}"
echo -e "${BOLD}(directly invoking updateArtifacts from cargo manager)${RESET}"
echo ""

# Read the original Cargo.toml for each fixture and construct the scenario JSON.
# Each scenario simulates what Renovate would pass to updateArtifacts().

# --- Scenario A: Range bump (single crate, rangeStrategy=replace) ---
# Renovate bumps hashbrown "0.14" -> "0.15" in Cargo.toml.
# The fix: cargoUpdatePrecise skips --precise (currentValue != newValue),
# relies on --workspace to re-resolve.
CARGO_TOML_A=$(cat /tests/e2e/fixtures/range-bump-single/Cargo.toml)
NEW_CARGO_TOML_A="${CARGO_TOML_A//hashbrown = \"0.14\"/hashbrown = \"0.15\"}"
SCENARIO_A=$(jq -n \
  --arg pkg "Cargo.toml" \
  --arg newContent "$NEW_CARGO_TOML_A" \
  '{
    packageFileName: $pkg,
    updatedDeps: [{
      depName: "hashbrown",
      packageName: "hashbrown",
      currentValue: "0.14",
      newValue: "0.15",
      lockedVersion: "0.14.5",
      newVersion: "0.15.2"
    }],
    newPackageFileContent: $newContent
  }')
test_fixture /tests/e2e/fixtures/range-bump-single \
    "Scenario A: Range bump (single crate, rangeStrategy=replace)" \
    "$SCENARIO_A"

# --- Scenario B: Range bump (workspace, rangeStrategy=replace) ---
# Same as A but in workspace context. Tests both members via separate calls.
MEMBER1_TOML_B=$(cat /tests/e2e/fixtures/range-bump-workspace/member1/Cargo.toml)
NEW_MEMBER1_TOML_B="${MEMBER1_TOML_B//hashbrown = \"0.14\"/hashbrown = \"0.15\"}"
SCENARIO_B1=$(jq -n \
  --arg pkg "member1/Cargo.toml" \
  --arg newContent "$NEW_MEMBER1_TOML_B" \
  '{
    packageFileName: $pkg,
    updatedDeps: [{
      depName: "hashbrown",
      packageName: "hashbrown",
      currentValue: "0.14",
      newValue: "0.15",
      lockedVersion: "0.14.5",
      newVersion: "0.15.2"
    }],
    newPackageFileContent: $newContent
  }')
test_fixture /tests/e2e/fixtures/range-bump-workspace \
    "Scenario B1: Range bump (workspace member1, rangeStrategy=replace)" \
    "$SCENARIO_B1"

MEMBER2_TOML_B=$(cat /tests/e2e/fixtures/range-bump-workspace/member2/Cargo.toml)
NEW_MEMBER2_TOML_B="${MEMBER2_TOML_B//hashbrown = \"0.14\"/hashbrown = \"0.15\"}"
SCENARIO_B2=$(jq -n \
  --arg pkg "member2/Cargo.toml" \
  --arg newContent "$NEW_MEMBER2_TOML_B" \
  '{
    packageFileName: $pkg,
    updatedDeps: [{
      depName: "hashbrown",
      packageName: "hashbrown",
      currentValue: "0.14",
      newValue: "0.15",
      lockedVersion: "0.14.5",
      newVersion: "0.15.2"
    }],
    newPackageFileContent: $newContent
  }')
test_fixture /tests/e2e/fixtures/range-bump-workspace \
    "Scenario B2: Range bump (workspace member2, rangeStrategy=replace)" \
    "$SCENARIO_B2"

# --- Scenario C: Stale lockedVersion (workspace, update-lockfile) ---
# currentValue === newValue ("0.12" stays "0.12"), so --precise IS used.
# The second member's --precise may fail (stale lockedVersion), but the
# retry logic in updateArtifactsImpl filters out already-updated deps.
MEMBER1_TOML_C=$(cat /tests/e2e/fixtures/stale-lockver-workspace/member1/Cargo.toml)
SCENARIO_C1=$(jq -n \
  --arg pkg "member1/Cargo.toml" \
  --arg newContent "$MEMBER1_TOML_C" \
  '{
    packageFileName: $pkg,
    updatedDeps: [{
      depName: "reqwest",
      packageName: "reqwest",
      currentValue: "0.12",
      newValue: "0.12",
      lockedVersion: "0.12.23",
      newVersion: "0.12.24"
    }],
    newPackageFileContent: $newContent
  }')
test_fixture /tests/e2e/fixtures/stale-lockver-workspace \
    "Scenario C1: Stale lockedVersion (workspace member1, update-lockfile)" \
    "$SCENARIO_C1"

# Scenario C2: Second member — this is where the bug would manifest.
# After C1 updates the lockfile, the lockedVersion "0.12.23" is stale.
# The retry logic should handle this by filtering out the already-updated dep.
MEMBER2_TOML_C=$(cat /tests/e2e/fixtures/stale-lockver-workspace/member2/Cargo.toml)
SCENARIO_C2=$(jq -n \
  --arg pkg "member2/Cargo.toml" \
  --arg newContent "$MEMBER2_TOML_C" \
  '{
    packageFileName: $pkg,
    updatedDeps: [{
      depName: "reqwest",
      packageName: "reqwest",
      currentValue: "0.12",
      newValue: "0.12",
      lockedVersion: "0.12.23",
      newVersion: "0.12.24"
    }],
    newPackageFileContent: $newContent
  }')
test_fixture /tests/e2e/fixtures/stale-lockver-workspace \
    "Scenario C2: Stale lockedVersion (workspace member2, update-lockfile)" \
    "$SCENARIO_C2"

echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "${BOLD}  E2E Summary${RESET}"
echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}Passed: $PASS${RESET}"
echo -e "  ${RED}Failed: $FAIL${RESET}"
echo -e "${BOLD}════════════════════════════════════════${RESET}"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
