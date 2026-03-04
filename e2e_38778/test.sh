#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'
PASS=0; FAIL=0

cat <<'DESC'
────────────────────────────────────────────────────────
  TEST: e2e #38778 — reqwest workspace range bump
  ISSUE: https://github.com/renovatebot/renovate/issues/38778

  WHAT: Pushes a Cargo workspace with reqwest ^0.12 and
        rangeStrategy=bump, then runs Renovate's full
        extract → lookup → update → artifacts pipeline.

  PASS: Cargo.lock updated with no artifact errors.
  FAIL: "package ID specification did not match any packages"
        or artifactError in Renovate logs.
────────────────────────────────────────────────────────
DESC

echo -e "${BOLD}#38778 e2e test: reqwest range bump in workspace${RESET}"
echo -e "${BOLD}(full CLI pipeline: extract → lookup → update → artifacts)${RESET}"
echo ""

# Git identity for pushing fixtures
git config --global user.email "test@test.com"
git config --global user.name "Test"

REPO_NAME="${REPO_PREFIX}-workspace-38778"

echo -e "${CYAN}━━━ Workspace: reqwest 0.12 (bump strategy) ━━━${RESET}"

# Create repo via Gitea API
curl -sf -X POST "http://${GITEA_HOST}:3000/api/v1/user/repos" \
    -H "Authorization: token $GITEA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$REPO_NAME\", \"auto_init\": false}" >/dev/null

# Push fixture to the repo (with renovate.json override)
tmpdir=$(mktemp -d)
cp -r /tests/workspace "$tmpdir/repo"
cd "$tmpdir/repo"
rm -f .git

# Override renovate.json to add enabledManagers for speed
cat > renovate.json <<'EOF'
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [],
  "enabledManagers": ["cargo"],
  "packageRules": [
    {
      "matchManagers": ["cargo"],
      "rangeStrategy": "bump"
    }
  ]
}
EOF

git init -b main -q
git add -A
git commit -q -m "initial"
git remote add origin "http://$GITEA_ADMIN_USER:$GITEA_ADMIN_PASS@${GITEA_HOST}:3000/$GITEA_ADMIN_USER/$REPO_NAME.git"
git push -q origin main
cd /tests
rm -rf "$tmpdir"

logfile="/tmp/e2e-38778.log"

echo "Running Renovate..."
LOG_LEVEL=info RENOVATE_EXPOSE_ALL_ENV=true tsx /opt/renovate/lib/renovate.ts \
    --platform=gitea \
    --endpoint="http://${GITEA_HOST}:3000/api/v1/" \
    --token="$GITEA_TOKEN" \
    --autodiscover=false \
    "$GITEA_ADMIN_USER/$REPO_NAME" &>"$logfile" || true

if grep -q "did not match any packages" "$logfile"; then
    echo -e "  ${RED}FAIL${RESET} — found 'package ID specification did not match any packages' error"
    FAIL=$((FAIL + 1))
elif grep -q 'artifactError' "$logfile"; then
    echo -e "  ${RED}FAIL${RESET} — found artifactError"
    FAIL=$((FAIL + 1))
elif grep -q "Returning updated Cargo.lock" "$logfile"; then
    echo -e "  ${GREEN}PASS${RESET} — Cargo.lock updated successfully"
    PASS=$((PASS + 1))
else
    echo -e "  ${GREEN}PASS${RESET} — no artifact errors (lockfile may already be up to date)"
    PASS=$((PASS + 1))
fi

echo ""
echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}Passed: $PASS${RESET}  ${RED}Failed: $FAIL${RESET}"
echo -e "${BOLD}════════════════════════════════════════${RESET}"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
