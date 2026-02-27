#!/usr/bin/env bash
# repro_bug.sh — Reproduces the exact bug from renovatebot/renovate#39137
#
# A workspace with two members both depending on reqwest = "0.12".
# After updating reqwest via --precise from one member's manifest,
# the second member's --precise fails because the lockfile no longer
# contains the old version.
set -euo pipefail

CARGO="${CARGO:-cargo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRATE_DIR="$SCRIPT_DIR/repro_crate"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

cd "$CRATE_DIR"

echo -e "${BOLD}=== Reproducing renovatebot/renovate#39137 ===${RESET}"
echo ""

echo -e "${YELLOW}[setup]${RESET} Using committed lockfile with reqwest@0.12.23"

echo ""
echo -e "${BOLD}Running the 3 commands from the issue:${RESET}"
echo ""

# Command 1: --precise from subdir manifest (should succeed)
echo -e "${YELLOW}[cmd 1]${RESET} cargo update --manifest-path subdir/Cargo.toml --package reqwest@0.12.23 --precise 0.12.24"
if $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path subdir/Cargo.toml --package reqwest@0.12.23 --precise 0.12.24 2>&1; then
    echo -e "  ${GREEN}PASS${RESET} — command 1 succeeded (as expected)"
else
    echo -e "  ${RED}UNEXPECTED${RESET} — command 1 failed"
fi
echo ""

# Command 2: --workspace from subdir manifest (should succeed)
echo -e "${YELLOW}[cmd 2]${RESET} cargo update --manifest-path subdir/Cargo.toml --workspace"
if $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path subdir/Cargo.toml --workspace 2>&1; then
    echo -e "  ${GREEN}PASS${RESET} — command 2 succeeded (as expected)"
else
    echo -e "  ${RED}UNEXPECTED${RESET} — command 2 failed"
fi
echo ""

# Command 3: --precise from subdir2 manifest (should FAIL — this is the bug)
echo -e "${YELLOW}[cmd 3]${RESET} cargo update --manifest-path subdir2/Cargo.toml --package reqwest@0.12.23 --precise 0.12.24"
OUTPUT=$($CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path subdir2/Cargo.toml --package reqwest@0.12.23 --precise 0.12.24 2>&1) && CMD3_EXIT=0 || CMD3_EXIT=$?

if [[ $CMD3_EXIT -ne 0 ]]; then
    echo "$OUTPUT"
    if echo "$OUTPUT" | grep -q "did not match"; then
        echo ""
        echo -e "  ${GREEN}PASS${RESET} — command 3 failed with 'did not match' (this is the bug from #39137)"
    else
        echo ""
        echo -e "  ${RED}UNEXPECTED${RESET} — command 3 failed but with unexpected error"
    fi
else
    echo "$OUTPUT"
    echo ""
    echo -e "  ${RED}UNEXPECTED${RESET} — command 3 succeeded (bug may be fixed in this cargo version)"
fi

echo ""
echo -e "${BOLD}=== Explanation ===${RESET}"
echo "Command 1 updated reqwest from 0.12.23 → 0.12.24 in the lockfile."
echo "Command 2 ran --workspace (no-op since the range is already satisfied)."
echo "Command 3 tried --package reqwest@0.12.23 but the lockfile now has 0.12.24,"
echo "so the @0.12.23 spec doesn't match anything → error."
echo ""
echo "This is exactly the bug that renovate's cargoUpdatePrecise fix addresses:"
echo "when the manifest range is bumped, skip --precise and use --workspace instead."
