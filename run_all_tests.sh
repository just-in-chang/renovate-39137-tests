#!/usr/bin/env bash
set -euo pipefail

BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
RESULTS=()

# ═══════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════

banner() {
    local num="$1" total="$2" title="$3" expect="$4"
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  TEST $num/$total: $title${RESET}"
    echo -e "${YELLOW}  EXPECT: $expect${RESET}"
    echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
    echo ""
}

record_result() {
    local name="$1" expected="$2" actual_exit="$3"

    if [[ "$expected" == "pass" && "$actual_exit" -eq 0 ]]; then
        echo ""
        echo -e "  ${GREEN}RESULT: PASS (as expected)${RESET}"
        RESULTS+=("${GREEN}PASS${RESET}  $name")
        TESTS_PASSED=$((TESTS_PASSED + 1))
    elif [[ "$expected" == "fail" && "$actual_exit" -ne 0 ]]; then
        echo ""
        echo -e "  ${GREEN}RESULT: FAIL (as expected — bug confirmed)${RESET}"
        RESULTS+=("${GREEN}PASS${RESET}  $name  (failed as expected)")
        TESTS_PASSED=$((TESTS_PASSED + 1))
    elif [[ "$expected" == "pass" && "$actual_exit" -ne 0 ]]; then
        echo ""
        echo -e "  ${RED}RESULT: UNEXPECTED FAIL — fix should have worked${RESET}"
        RESULTS+=("${RED}FAIL${RESET}  $name  (unexpected failure)")
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo ""
        echo -e "  ${RED}RESULT: UNEXPECTED PASS — bug should still exist${RESET}"
        RESULTS+=("${RED}FAIL${RESET}  $name  (unexpected pass)")
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Setup: Shared Gitea via Docker Compose
# ═══════════════════════════════════════════════════════════════════════════

trap 'docker compose down 2>/dev/null' EXIT

echo -e "${BOLD}Starting shared Gitea instance...${RESET}"
docker compose up -d --wait gitea

echo "Creating admin user and API token..."
docker compose exec -T -u git gitea gitea admin user create \
    --username renovate-bot \
    --password password123 \
    --email renovate-bot@localhost \
    --admin \
    --must-change-password=false >/dev/null 2>&1

token_output=$(docker compose exec -T -u git gitea gitea admin user generate-access-token \
    --username renovate-bot \
    --token-name e2e \
    --scopes all 2>/dev/null)
export GITEA_TOKEN
GITEA_TOKEN=$(echo "$token_output" | awk -F': ' '{print $2}' | tr -d '[:space:]')
echo "Gitea ready, token acquired."

# ═══════════════════════════════════════════════════════════════════════════
# Build all images up front
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}Building test images...${RESET}"
docker compose build

# ═══════════════════════════════════════════════════════════════════════════
# TEST 1/5: Cargo-level tests (no Renovate, no Gitea)
# ═══════════════════════════════════════════════════════════════════════════

banner 1 5 "#39137: Cargo Update Tests" "PASS (cargo behavior verification)"

exit_code=0
docker compose run --rm cargo-tests 2>&1 || exit_code=$?
record_result "#39137 cargo tests" "pass" "$exit_code"

# ═══════════════════════════════════════════════════════════════════════════
# TEST 2/5: e2e #38778 — Old Renovate (upstream)
# ═══════════════════════════════════════════════════════════════════════════

banner 2 5 "e2e #38778 — Old Renovate (upstream)" \
    "FAIL (bug #38778 exists in upstream — reqwest workspace range bump broken)"

exit_code=0
docker compose run --rm e2e-38778-old 2>&1 || exit_code=$?
record_result "e2e #38778 old (upstream)" "fail" "$exit_code"

# ═══════════════════════════════════════════════════════════════════════════
# TEST 3/5: e2e #38778 — New Renovate (fork)
# ═══════════════════════════════════════════════════════════════════════════

banner 3 5 "e2e #38778 — New Renovate (fork)" \
    "PASS (fix for #38778 applied — reqwest workspace range bump works)"

exit_code=0
docker compose run --rm e2e-38778-new 2>&1 || exit_code=$?
record_result "e2e #38778 new (fork)" "pass" "$exit_code"

# ═══════════════════════════════════════════════════════════════════════════
# TEST 4/5: e2e #39137 — Old Renovate (upstream)
# ═══════════════════════════════════════════════════════════════════════════

banner 4 5 "e2e #39137 — Old Renovate (upstream)" \
    "FAIL (bug #39137 exists in upstream — cargoUpdatePrecise broken)"

exit_code=0
docker compose run --rm e2e-39137-old 2>&1 || exit_code=$?
record_result "e2e #39137 old (upstream)" "fail" "$exit_code"

# ═══════════════════════════════════════════════════════════════════════════
# TEST 5/5: e2e #39137 — New Renovate (fork)
# ═══════════════════════════════════════════════════════════════════════════

banner 5 5 "e2e #39137 — New Renovate (fork)" \
    "PASS (fix for #39137 applied — cargoUpdatePrecise works)"

exit_code=0
docker compose run --rm e2e-39137-new 2>&1 || exit_code=$?
record_result "e2e #39137 new (fork)" "pass" "$exit_code"

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  FINAL RESULTS${RESET}"
echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
for r in "${RESULTS[@]}"; do
    echo -e "  $r"
done
echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}Passed: $TESTS_PASSED${RESET}  ${RED}Failed: $TESTS_FAILED${RESET}"
echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"

[[ $TESTS_FAILED -gt 0 ]] && exit 1 || exit 0
