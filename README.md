# Cargo Update Test Suite for renovatebot/renovate#39137

Reproducible test suite for `cargo update` behavior that exposed a bug in Renovate's `cargoUpdatePrecise` logic. Uses Docker Compose to orchestrate a shared Gitea instance and run all tests.

## Quick Start

```bash
./run_all_tests.sh
```

This uses Docker Compose to:
1. Start a Gitea instance (with healthcheck)
2. Create an admin user and API token
3. Build all test images
4. Run 5 tests sequentially with clear pass/fail expectations
5. Print a summary table

No local Rust, Node.js, or Gitea installation required — only Docker with Compose.

## What the Tests Do

| # | Test | Expects | Why |
|---|------|---------|-----|
| 1 | `cargo-tests` (39137/) | PASS | Cargo-level behavior verification, no Renovate |
| 2 | `e2e-38778-old` (upstream) | FAIL | Bug #38778 exists in upstream Renovate |
| 3 | `e2e-38778-new` (fork) | PASS | Fix for #38778 applied |
| 4 | `e2e-39137-old` (upstream) | FAIL | Bug #39137 exists in upstream Renovate |
| 5 | `e2e-39137-new` (fork) | PASS | Fix for #39137 applied |

"Old" tests build Renovate from `renovatebot/renovate` (upstream).
"New" tests build from `just-in-chang/renovate` (fork with fix).

## Test Output

```
════════════════════════════════════════════════════════
  TEST 1/5: #39137: Cargo Update Tests
  EXPECT: PASS (cargo behavior verification)
════════════════════════════════════════════════════════

cargo update test suite for renovatebot/renovate#39137
Using: cargo 1.90.0

=== Reproducing renovatebot/renovate#39137 ===
[cmd 1] cargo update --package reqwest@0.12.23 --precise 0.12.24
  PASS — command 1 succeeded (as expected)
[cmd 2] cargo update --workspace
  PASS — command 2 succeeded (as expected)
[cmd 3] cargo update --package reqwest@0.12.23 --precise 0.12.24
  PASS — command 3 failed with 'did not match' (this is the bug from #39137)

━━━ Scenario 1: Range bump (single crate) ━━━
  PASS 1a: --precise 0.15.2 after range bump 0.14→0.15
  PASS 1b: --workspace after range bump 0.14→0.15

━━━ Scenario 1: Range bump (workspace) ━━━
  PASS 1a-ws: --precise 0.15.2 after range bump 0.14→0.15
  PASS 1b-ws: --workspace after range bump 0.14→0.15

━━━ Scenario 2: Stale lockedVersion (single crate) ━━━
  PASS 2a: --precise 0.12.24 (first call)
  PASS 2b: --precise 0.12.24 again (stale @0.12.23 spec) (failed with expected error)

━━━ Scenario 2: Stale lockedVersion (workspace) ━━━
  PASS 2a-ws: --precise 0.12.24 from subdir1
  PASS 2b-ws: --precise 0.12.24 from subdir2 (stale @0.12.23 spec) (failed with expected error)

━━━ Scenario 3: Multi-version ambiguity (single crate) ━━━
  PASS 3a: --workspace with syn@1 + syn@2
  PASS 3b: --package syn --precise (ambiguous, two syn versions) (failed with expected error)
  PASS 3c: --package syn@2.0.100 --precise 2.0.90 (disambiguated)
  PASS 3d: --workspace after syn range bump to >=2.0.110

━━━ Scenario 3: Multi-version ambiguity (workspace) ━━━
  PASS 3a-ws: --workspace with syn@1 + syn@2
  PASS 3b-ws: --package syn --precise (ambiguous, two syn versions) (failed with expected error)
  PASS 3c-ws: --package syn@2.0.100 --precise 2.0.90 (disambiguated)
  PASS 3d-ws: --workspace after syn range bump to >=2.0.110

  Passed: 16  Failed: 0

  RESULT: PASS (as expected)

════════════════════════════════════════════════════════
  TEST 2/5: e2e #38778 — Old Renovate (upstream)
  EXPECT: FAIL (bug #38778 exists in upstream — reqwest workspace range bump broken)
════════════════════════════════════════════════════════

━━━ Workspace: reqwest 0.12 (bump strategy) ━━━
Running Renovate...
  FAIL — found 'package ID specification did not match any packages' error

  RESULT: FAIL (as expected — bug confirmed)

════════════════════════════════════════════════════════
  TEST 3/5: e2e #38778 — New Renovate (fork)
  EXPECT: PASS (fix for #38778 applied — reqwest workspace range bump works)
════════════════════════════════════════════════════════

━━━ Workspace: reqwest 0.12 (bump strategy) ━━━
Running Renovate...
  PASS — no artifact errors (lockfile may already be up to date)

  RESULT: PASS (as expected)

════════════════════════════════════════════════════════
  TEST 4/5: e2e #39137 — Old Renovate (upstream)
  EXPECT: FAIL (bug #39137 exists in upstream — cargoUpdatePrecise broken)
════════════════════════════════════════════════════════

━━━ Range bump (single) ━━━
  PASS Range bump (single) — no artifact errors

━━━ Range bump (workspace) ━━━
  FAIL Range bump (workspace) — found 'package ID specification did not match any packages' error

━━━ Stale lockedVersion (workspace) ━━━
  FAIL Stale lockedVersion (workspace) — found 'package ID specification did not match any packages' error

  RESULT: FAIL (as expected — bug confirmed)

════════════════════════════════════════════════════════
  TEST 5/5: e2e #39137 — New Renovate (fork)
  EXPECT: PASS (fix for #39137 applied — cargoUpdatePrecise works)
════════════════════════════════════════════════════════

━━━ Range bump (single) ━━━
  PASS Range bump (single) — no artifact errors

━━━ Range bump (workspace) ━━━
  PASS Range bump (workspace) — no artifact errors

━━━ Stale lockedVersion (workspace) ━━━
  PASS Stale lockedVersion (workspace) — no artifact errors

  RESULT: PASS (as expected)

════════════════════════════════════════════════════════
  FINAL RESULTS
════════════════════════════════════════════════════════
  PASS  #39137 cargo tests
  PASS  e2e #38778 old (upstream)  (failed as expected)
  PASS  e2e #38778 new (fork)
  PASS  e2e #39137 old (upstream)  (failed as expected)
  PASS  e2e #39137 new (fork)
════════════════════════════════════════════════════════
  Passed: 5  Failed: 0
════════════════════════════════════════════════════════
```

## Test Philosophy

### Why Docker?

Renovate's cargo artifact pipeline depends on exact interactions between specific tool versions — Rust/cargo, Node.js, pnpm, and a Git hosting platform. Running these tests on a bare host would mean:

- Installing Rust, Node.js, and pnpm at specific versions
- Running a Gitea instance (or mocking one)
- Hoping the host environment doesn't interfere with results
- Making it impossible for someone else to reproduce

Docker eliminates all of that. Each test image pins its toolchain (e.g. `rust:1.90-slim`, `node:24-slim`), Gitea runs as a container with a healthcheck, and the entire suite is a single `./run_all_tests.sh` on any machine with Docker.

### Why Gitea?

Renovate's e2e behavior depends on a real Git platform — it clones repos, creates branches, opens PRs, and posts artifact error comments. Mocking all of that would test the mock, not Renovate. Gitea is lightweight, starts in seconds, and supports the full Gitea platform API that Renovate uses. Docker Compose manages Gitea's lifecycle (start, healthcheck, teardown) so the tests don't need to.

### Test structure: prove the bug, then prove the fix

Each e2e test pair follows the same pattern:

1. **Old (upstream)**: Build Renovate from `renovatebot/renovate`. Push a fixture repo to Gitea. Run Renovate. **Expect failure** — the bug should produce an artifact error (`package ID specification did not match any packages`).
2. **New (fork)**: Same fixture, same Gitea, but Renovate is built from the fork with the fix applied. **Expect success** — no artifact errors.

This structure makes it impossible to accidentally "pass" — if the old test stops failing, something changed upstream (the bug was fixed, or the test no longer triggers it). If the new test starts failing, the fix regressed.

The cargo-level tests (test 1) complement the e2e tests by demonstrating the underlying `cargo update` behavior directly, without Renovate in the loop.

### Fixture design

Each fixture is a minimal Cargo project (or workspace) committed with a `Cargo.lock` that locks dependencies to specific older versions. This guarantees Renovate will find an update to propose, triggering the artifact update pipeline where the bug lives.

Workspace fixtures include per-member `Cargo.lock` files. This is what causes Renovate to run `cargo update --precise` separately for each member rather than once at the workspace root — which is the exact code path that triggers the collision bug.

## Directory Structure

```
docker-compose.yml        Service definitions (Gitea + all test containers)
run_all_tests.sh          Orchestrator — starts Gitea, runs tests, prints summary

39137/                    Cargo-level unit tests (no Renovate)
  Dockerfile              FROM rust:1.90-slim
  test.sh                 Bug repro + scenarios 1-3
  repro_crate/            Static workspace fixture (reqwest)
  single_crate/           Template fixture (overwritten per scenario)
  workspace/              Template workspace fixture

e2e_38778/                Renovate e2e test for issue #38778
  Dockerfile              Multi-stage: node+renovate, rust runtime
  test.sh                 Push workspace to Gitea, run Renovate
  workspace/              reqwest 0.12 workspace (bump strategy)

e2e_39137/                Renovate e2e test for issue #39137
  Dockerfile              Multi-stage: node+renovate, rust runtime
  test.sh                 Push 3 fixtures to Gitea, run Renovate
  fixtures/               3 fixture scenarios
```

## Running Individual Tests

The recommended way is `./run_all_tests.sh`, but you can run pieces independently:

```bash
# Start just Gitea
docker compose up -d --wait gitea

# Run only the cargo-level tests (no Gitea needed)
docker compose run --rm cargo-tests

# Run a single e2e test (requires Gitea + GITEA_TOKEN)
docker compose run --rm e2e-39137-new
```

To tear everything down:

```bash
docker compose down
```

## The Bug

Renovate's `cargoUpdatePrecise` function runs `cargo update --package <dep>@<lockedVersion> --precise <newVersion>` for each dependency. In a workspace with shared dependencies, the first `--precise` call mutates the shared `Cargo.lock`, causing subsequent calls to fail because the `@lockedVersion` spec no longer matches.

## The Fix

The fix adds a guard: when `currentValue !== newValue` (manifest range was bumped), skip `--precise` and let the trailing `--workspace` re-resolve against the new range.
