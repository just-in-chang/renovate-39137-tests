#!/usr/bin/env bash
# test.sh — Cargo update test suite for renovatebot/renovate#39137
#
# Runs bug reproduction first, then scenarios 1-3.
# Each scenario tests both single-crate and workspace layouts.
set -euo pipefail

CARGO="${CARGO:-cargo}"
export CARGO_NET_RETRY=10
export CARGO_HTTP_TIMEOUT=120
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPRO_DIR="$SCRIPT_DIR/repro_crate"
SINGLE_DIR="$SCRIPT_DIR/single_crate"
WORKSPACE_DIR="$SCRIPT_DIR/workspace"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

# ── Helper functions ────────────────────────────────────────────────────────

reset_single_crate() {
    local toml_content="$1"
    cat > "$SINGLE_DIR/Cargo.toml" <<EOF
$toml_content
EOF
    # Resolve deps into the lockfile to match the new Cargo.toml
    $CARGO update --config net.git-fetch-with-cli=true \
        --manifest-path "$SINGLE_DIR/Cargo.toml" 2>/dev/null
}

reset_workspace() {
    local subdir1_toml="$1"
    local subdir2_toml="$2"
    cat > "$WORKSPACE_DIR/subdir1/Cargo.toml" <<EOF
$subdir1_toml
EOF
    cat > "$WORKSPACE_DIR/subdir2/Cargo.toml" <<EOF
$subdir2_toml
EOF
    # Resolve deps into the lockfile to match the new Cargo.toml
    $CARGO update --config net.git-fetch-with-cli=true \
        --manifest-path "$WORKSPACE_DIR/Cargo.toml" 2>/dev/null
}

pin_version() {
    local manifest="$1" package="$2" version="$3"
    $CARGO update --config net.git-fetch-with-cli=true \
        --manifest-path "$manifest" --package "$package" --precise "$version" 2>/dev/null
}

lockfile_version() {
    local lockfile="$1" pkg="$2" major="$3"
    awk -v pkg="$pkg" -v major="$major" '
        /^\[\[package\]\]/ { name=""; ver="" }
        /^name = / { gsub(/"/, "", $3); name=$3 }
        /^version = / { gsub(/"/, "", $3); ver=$3 }
        name==pkg && ver ~ "^"major"\\." { print ver; exit }
    ' "$lockfile"
}

expect_success() {
    local description="$1"
    shift
    local output
    local exit_code=0
    output=$("$@" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo -e "  ${GREEN}PASS${RESET} $description"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${RED}FAIL${RESET} $description"
        echo "       Expected success, got exit code $exit_code"
        echo "       Output: $output"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

expect_failure() {
    local description="$1"
    local pattern="$2"
    shift 2
    local output
    local exit_code=0
    output=$("$@" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 0 ]] && echo "$output" | grep -qE "$pattern"; then
        echo -e "  ${GREEN}PASS${RESET} $description (failed with expected error)"
        PASS_COUNT=$((PASS_COUNT + 1))
    elif [[ $exit_code -eq 0 ]]; then
        echo -e "  ${RED}FAIL${RESET} $description"
        echo "       Expected failure, but command succeeded"
        echo "       Output: $output"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo -e "  ${RED}FAIL${RESET} $description"
        echo "       Command failed but stderr did not match pattern: $pattern"
        echo "       Output: $output"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

print_summary() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Test Summary${RESET}"
    echo -e "${BOLD}════════════════════════════════════════${RESET}"
    echo -e "  ${GREEN}Passed: $PASS_COUNT${RESET}"
    echo -e "  ${RED}Failed: $FAIL_COUNT${RESET}"
    echo -e "${BOLD}════════════════════════════════════════${RESET}"
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
}

# ── Cargo version info ─────────────────────────────────────────────────────

echo -e "${BOLD}cargo update test suite for renovatebot/renovate#39137${RESET}"
echo -e "Using: $($CARGO --version)"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# BUG REPRODUCTION
# ════════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}=== Reproducing renovatebot/renovate#39137 ===${RESET}"
echo ""

cd "$REPRO_DIR"

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

# Reset repro_crate lockfile for repeatable runs
cd "$REPRO_DIR"
git checkout -- Cargo.lock 2>/dev/null || true

cd "$SCRIPT_DIR"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# SCENARIO 1: Range bump (hashbrown "0.14" → "0.15")
# ════════════════════════════════════════════════════════════════════════════

scenario_1() {

SINGLE_TOML_014='[package]
name = "single-crate"
version = "0.1.0"
edition = "2021"

[dependencies]
hashbrown = "0.14"'

SINGLE_TOML_015='[package]
name = "single-crate"
version = "0.1.0"
edition = "2021"

[dependencies]
hashbrown = "0.15"'

WS_SUBDIR1_TOML_014='[package]
name = "subdir1"
version = "0.1.0"
edition = "2021"

[dependencies]
hashbrown = "0.14"'

WS_SUBDIR2_TOML_014='[package]
name = "subdir2"
version = "0.1.0"
edition = "2021"

[dependencies]
hashbrown = "0.14"'

WS_SUBDIR1_TOML_015='[package]
name = "subdir1"
version = "0.1.0"
edition = "2021"

[dependencies]
hashbrown = "0.15"'

WS_SUBDIR2_TOML_015='[package]
name = "subdir2"
version = "0.1.0"
edition = "2021"

[dependencies]
hashbrown = "0.15"'

# ── Scenario 1: Single crate ───────────────────────────────────────────────

echo -e "${CYAN}━━━ Scenario 1: Range bump (single crate) ━━━${RESET}"

# Test 1a: --precise across major range bump
echo -e "${YELLOW}[setup]${RESET} hashbrown = \"0.14\", then bump to \"0.15\""
reset_single_crate "$SINGLE_TOML_014"
# Lockfile now has hashbrown 0.14.x; overwrite toml to 0.15
cat > "$SINGLE_DIR/Cargo.toml" <<EOF
$SINGLE_TOML_015
EOF

LOCKED_VER=$(lockfile_version "$SINGLE_DIR/Cargo.lock" hashbrown 0)
expect_success "1a: --precise 0.15.2 after range bump 0.14→0.15" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$SINGLE_DIR/Cargo.toml" --package "hashbrown@${LOCKED_VER}" --precise 0.15.2

# Test 1b: --workspace after range bump
echo -e "${YELLOW}[setup]${RESET} hashbrown = \"0.14\", then bump to \"0.15\""
reset_single_crate "$SINGLE_TOML_014"
cat > "$SINGLE_DIR/Cargo.toml" <<EOF
$SINGLE_TOML_015
EOF

expect_success "1b: --workspace after range bump 0.14→0.15" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$SINGLE_DIR/Cargo.toml" --workspace

echo ""

# ── Scenario 1: Workspace ──────────────────────────────────────────────────

echo -e "${CYAN}━━━ Scenario 1: Range bump (workspace) ━━━${RESET}"

# Test 1a-ws: --precise across major range bump
echo -e "${YELLOW}[setup]${RESET} hashbrown = \"0.14\" in both subdirs, then bump to \"0.15\""
reset_workspace "$WS_SUBDIR1_TOML_014" "$WS_SUBDIR2_TOML_014"
cat > "$WORKSPACE_DIR/subdir1/Cargo.toml" <<EOF
$WS_SUBDIR1_TOML_015
EOF
cat > "$WORKSPACE_DIR/subdir2/Cargo.toml" <<EOF
$WS_SUBDIR2_TOML_015
EOF

LOCKED_VER=$(lockfile_version "$WORKSPACE_DIR/Cargo.lock" hashbrown 0)
expect_success "1a-ws: --precise 0.15.2 after range bump 0.14→0.15" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$WORKSPACE_DIR/subdir1/Cargo.toml" --package "hashbrown@${LOCKED_VER}" --precise 0.15.2

# Test 1b-ws: --workspace after range bump
echo -e "${YELLOW}[setup]${RESET} hashbrown = \"0.14\" in both subdirs, then bump to \"0.15\""
reset_workspace "$WS_SUBDIR1_TOML_014" "$WS_SUBDIR2_TOML_014"
cat > "$WORKSPACE_DIR/subdir1/Cargo.toml" <<EOF
$WS_SUBDIR1_TOML_015
EOF
cat > "$WORKSPACE_DIR/subdir2/Cargo.toml" <<EOF
$WS_SUBDIR2_TOML_015
EOF

expect_success "1b-ws: --workspace after range bump 0.14→0.15" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$WORKSPACE_DIR/subdir1/Cargo.toml" --workspace

echo ""

}

# ════════════════════════════════════════════════════════════════════════════
# SCENARIO 2: Stale lockedVersion (sequential --precise)
# ════════════════════════════════════════════════════════════════════════════

scenario_2() {

SINGLE_TOML_REQWEST='[package]
name = "single-crate"
version = "0.1.0"
edition = "2021"

[dependencies]
reqwest = "0.12"'

WS_SUBDIR1_TOML_REQWEST='[package]
name = "subdir1"
version = "0.1.0"
edition = "2021"

[dependencies]
reqwest = "0.12"'

WS_SUBDIR2_TOML_REQWEST='[package]
name = "subdir2"
version = "0.1.0"
edition = "2021"

[dependencies]
reqwest = "0.12"'

# ── Scenario 2: Single crate ───────────────────────────────────────────────

echo -e "${CYAN}━━━ Scenario 2: Stale lockedVersion (single crate) ━━━${RESET}"

echo -e "${YELLOW}[setup]${RESET} reqwest = \"0.12\", pinned to 0.12.23"
reset_single_crate "$SINGLE_TOML_REQWEST"
pin_version "$SINGLE_DIR/Cargo.toml" reqwest 0.12.23

# Test 2a: First --precise succeeds
expect_success "2a: --precise 0.12.24 (first call)" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$SINGLE_DIR/Cargo.toml" --package 'reqwest@0.12.23' --precise 0.12.24

# Test 2b: Second --precise fails (stale spec)
expect_failure "2b: --precise 0.12.24 again (stale @0.12.23 spec)" \
    "did not match" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$SINGLE_DIR/Cargo.toml" --package 'reqwest@0.12.23' --precise 0.12.24

echo ""

# ── Scenario 2: Workspace ──────────────────────────────────────────────────

echo -e "${CYAN}━━━ Scenario 2: Stale lockedVersion (workspace) ━━━${RESET}"

echo -e "${YELLOW}[setup]${RESET} reqwest = \"0.12\" in both subdirs, pinned to 0.12.23"
reset_workspace "$WS_SUBDIR1_TOML_REQWEST" "$WS_SUBDIR2_TOML_REQWEST"
pin_version "$WORKSPACE_DIR/subdir1/Cargo.toml" reqwest 0.12.23

# Test 2a-ws: --precise from subdir1 succeeds
expect_success "2a-ws: --precise 0.12.24 from subdir1" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$WORKSPACE_DIR/subdir1/Cargo.toml" --package 'reqwest@0.12.23' --precise 0.12.24

# Test 2b-ws: --precise from subdir2 fails (lockfile already updated)
expect_failure "2b-ws: --precise 0.12.24 from subdir2 (stale @0.12.23 spec)" \
    "did not match" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$WORKSPACE_DIR/subdir2/Cargo.toml" --package 'reqwest@0.12.23' --precise 0.12.24

echo ""

}

# ════════════════════════════════════════════════════════════════════════════
# SCENARIO 3: Multi-version ambiguity (syn@1 + syn@2)
# ════════════════════════════════════════════════════════════════════════════

scenario_3() {

SINGLE_TOML_SYN='[package]
name = "single-crate"
version = "0.1.0"
edition = "2021"

[dependencies]
syn = "2"
clap = { version = "3", features = ["derive"] }'

WS_SUBDIR1_TOML_SYN='[package]
name = "subdir1"
version = "0.1.0"
edition = "2021"

[dependencies]
syn = "1"'

WS_SUBDIR2_TOML_SYN='[package]
name = "subdir2"
version = "0.1.0"
edition = "2021"

[dependencies]
syn = "2"'

# ── Scenario 3: Single crate ───────────────────────────────────────────────

echo -e "${CYAN}━━━ Scenario 3: Multi-version ambiguity (single crate) ━━━${RESET}"

echo -e "${YELLOW}[setup]${RESET} syn = \"2\" + clap = \"3\" (pulls syn@1 transitively), syn@2 pinned to 2.0.100"
reset_single_crate "$SINGLE_TOML_SYN"
pin_version "$SINGLE_DIR/Cargo.toml" 'syn@2' 2.0.100

# Test 3a: --workspace succeeds
expect_success "3a: --workspace with syn@1 + syn@2" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$SINGLE_DIR/Cargo.toml" --workspace

# Re-pin syn@2 back to 2.0.100 for remaining tests
reset_single_crate "$SINGLE_TOML_SYN"
pin_version "$SINGLE_DIR/Cargo.toml" 'syn@2' 2.0.100

# Test 3b: bare --package syn is ambiguous
expect_failure "3b: --package syn --precise (ambiguous, two syn versions)" \
    "ambiguous" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$SINGLE_DIR/Cargo.toml" --package syn --precise 2.0.100

# Test 3c: disambiguated with @version
expect_success "3c: --package syn@2.0.100 --precise 2.0.90 (disambiguated)" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$SINGLE_DIR/Cargo.toml" --package 'syn@2.0.100' --precise 2.0.90

# Test 3d: range bump + --workspace
echo -e "${YELLOW}[setup]${RESET} Bumping syn range to \">=2.0.110, <3\""
cat > "$SINGLE_DIR/Cargo.toml" <<'EOF'
[package]
name = "single-crate"
version = "0.1.0"
edition = "2021"

[dependencies]
syn = ">=2.0.110, <3"
clap = { version = "3", features = ["derive"] }
EOF

expect_success "3d: --workspace after syn range bump to >=2.0.110" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$SINGLE_DIR/Cargo.toml" --workspace

echo ""

# ── Scenario 3: Workspace ──────────────────────────────────────────────────

echo -e "${CYAN}━━━ Scenario 3: Multi-version ambiguity (workspace) ━━━${RESET}"

echo -e "${YELLOW}[setup]${RESET} subdir1: syn = \"1\", subdir2: syn = \"2\", syn@2 pinned to 2.0.100"
reset_workspace "$WS_SUBDIR1_TOML_SYN" "$WS_SUBDIR2_TOML_SYN"
pin_version "$WORKSPACE_DIR/Cargo.toml" 'syn@2' 2.0.100

# Test 3a-ws: --workspace succeeds
expect_success "3a-ws: --workspace with syn@1 + syn@2" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$WORKSPACE_DIR/Cargo.toml" --workspace

# Re-pin syn@2 back to 2.0.100 for remaining tests
reset_workspace "$WS_SUBDIR1_TOML_SYN" "$WS_SUBDIR2_TOML_SYN"
pin_version "$WORKSPACE_DIR/Cargo.toml" 'syn@2' 2.0.100

# Test 3b-ws: bare --package syn is ambiguous
expect_failure "3b-ws: --package syn --precise (ambiguous, two syn versions)" \
    "ambiguous" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$WORKSPACE_DIR/Cargo.toml" --package syn --precise 2.0.100

# Test 3c-ws: disambiguated with @version
expect_success "3c-ws: --package syn@2.0.100 --precise 2.0.90 (disambiguated)" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$WORKSPACE_DIR/Cargo.toml" --package 'syn@2.0.100' --precise 2.0.90

# Test 3d-ws: range bump + --workspace
echo -e "${YELLOW}[setup]${RESET} Bumping syn range to \">=2.0.110, <3\" in subdir2"
cat > "$WORKSPACE_DIR/subdir2/Cargo.toml" <<'EOF'
[package]
name = "subdir2"
version = "0.1.0"
edition = "2021"

[dependencies]
syn = ">=2.0.110, <3"
EOF

expect_success "3d-ws: --workspace after syn range bump to >=2.0.110" \
    $CARGO update --config net.git-fetch-with-cli=true \
    --manifest-path "$WORKSPACE_DIR/Cargo.toml" --workspace

echo ""

}

# ── Run all scenarios ─────────────────────────────────────────────────────

scenario_1
scenario_2
scenario_3

print_summary
