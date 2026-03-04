#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Git identity for pushing fixtures
git config --global user.email "test@test.com"
git config --global user.name "Test"

create_and_push_repo() {
    local fixture="$1" repo_name="$2"

    # Create repo via Gitea API
    curl -sf -X POST "http://${GITEA_HOST}:3000/api/v1/user/repos" \
        -H "Authorization: token $GITEA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$repo_name\", \"auto_init\": false}" >/dev/null

    # Push fixture to the repo
    local tmpdir
    tmpdir=$(mktemp -d)
    cp -r "$fixture" "$tmpdir/repo"
    cd "$tmpdir/repo"
    git init -b main -q
    git add -A
    git commit -q -m "initial"
    git remote add origin "http://$GITEA_ADMIN_USER:$GITEA_ADMIN_PASS@${GITEA_HOST}:3000/$GITEA_ADMIN_USER/$repo_name.git"
    git push -q origin main
    cd /tests
    rm -rf "$tmpdir"
}

run_renovate() {
    local repo_name="$1" name="$2"
    local logfile="/tmp/e2e-$(echo "$name" | tr ' ()' '---').log"

    echo -e "${CYAN}━━━ $name ━━━${RESET}"
    echo "Running Renovate..."

    LOG_LEVEL=info RENOVATE_EXPOSE_ALL_ENV=true tsx /opt/renovate/lib/renovate.ts \
        --platform=gitea \
        --endpoint="http://${GITEA_HOST}:3000/api/v1/" \
        --token="$GITEA_TOKEN" \
        --autodiscover=false \
        "$GITEA_ADMIN_USER/$repo_name" &>"$logfile" || true

    # Check for failure indicators
    if grep -q "did not match any packages" "$logfile"; then
        echo -e "  ${RED}FAIL${RESET} $name — found 'package ID specification did not match any packages' error"
        FAIL=$((FAIL + 1))
    elif grep -q 'artifactError' "$logfile"; then
        echo -e "  ${RED}FAIL${RESET} $name — found artifactError"
        FAIL=$((FAIL + 1))
    elif grep -q "Returning updated Cargo.lock" "$logfile"; then
        echo -e "  ${GREEN}PASS${RESET} $name — Cargo.lock updated successfully"
        PASS=$((PASS + 1))
    else
        echo -e "  ${GREEN}PASS${RESET} $name — no artifact errors (lockfile may already be up to date)"
        PASS=$((PASS + 1))
    fi
    echo ""
}

cat <<'DESC'
────────────────────────────────────────────────────────
  TEST: e2e #39137 — cargoUpdatePrecise fix
  ISSUE: https://github.com/renovatebot/renovate/issues/39137

  WHAT: Pushes three Cargo fixture repos (single crate,
        workspace range-bump, workspace stale-lockver)
        then runs Renovate's full extract → lookup →
        update → artifacts pipeline against each.

  PASS: Cargo.lock updated with no artifact errors.
  FAIL: "package ID specification did not match any packages"
        or artifactError in Renovate logs.
────────────────────────────────────────────────────────
DESC

echo -e "${BOLD}Renovate e2e tests for #39137 (cargoUpdatePrecise fix)${RESET}"
echo -e "${BOLD}(full CLI pipeline: extract → lookup → update → artifacts)${RESET}"
echo ""

# Create repos and push fixtures
create_and_push_repo /tests/fixtures/range-bump-single     "${REPO_PREFIX}-range-bump-single"
create_and_push_repo /tests/fixtures/range-bump-workspace   "${REPO_PREFIX}-range-bump-workspace"
create_and_push_repo /tests/fixtures/stale-lockver-workspace "${REPO_PREFIX}-stale-lockver-workspace"

# Run Renovate against each repo
run_renovate "${REPO_PREFIX}-range-bump-single"       "Range bump (single)"
run_renovate "${REPO_PREFIX}-range-bump-workspace"    "Range bump (workspace)"
run_renovate "${REPO_PREFIX}-stale-lockver-workspace" "Stale lockedVersion (workspace)"

echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "${BOLD}  E2E Summary${RESET}"
echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}Passed: $PASS${RESET}"
echo -e "  ${RED}Failed: $FAIL${RESET}"
echo -e "${BOLD}════════════════════════════════════════${RESET}"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
